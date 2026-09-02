import XCTest
@testable import NeuroForge

final class CloudAuthoringTests: XCTestCase {
    func testAuthoringEngineNeverAdvertisesOrSelectsLegacyNativePCCRoute() async throws {
        let engine = NFAuthoringEngine(
            onDeviceRouteResolver: { _ in
                NFAIRouteSnapshot(route: .onDevice, state: .unavailable, reason: "test")
            }
        )
        let request = NFAuthoringRequest(
            capability: .contextualize,
            lab: .quantitative,
            field: .dataScience,
            customTopic: "classifier precision",
            learningObjective: "compute precision from a confusion matrix",
            style: .numerical,
            difficulty: 0.72,
            count: 1,
            seed: 91,
            aiMode: .automatic,
            allowsShortcutAuthoring: true
        )

        let routes = await engine.routeStatus(for: request)
        let result = try await engine.author(request)

        XCTAssertNil(routes.first { $0.route == .privateCloudCompute })
        XCTAssertEqual(result.provenance.route, .deterministicFallback)
        XCTAssertFalse(result.routeCandidates.contains { $0.route == .privateCloudCompute })
    }

    func testShortcutDraftRejectsModelSuppliedArithmeticAuthority() throws {
        let request = NFAuthoringRequest(
            capability: .contextualize,
            lab: .quantitative,
            field: .chemistry,
            customTopic: "solution dilution",
            learningObjective: "apply the dilution relation",
            style: .numerical,
            difficulty: 0.6,
            count: 1,
            seed: 4,
            aiMode: .automatic,
            allowsShortcutAuthoring: true
        )
        let incorrect = NFShortcutQuestionDraft(
            prompt: "A solution dilution uses 10 mL of stock to prepare 50 mL total. What fraction of the final volume is stock?",
            context: "Chemistry · solution dilution",
            choices: [],
            correctAnswer: "0.5",
            acceptedAnswers: [],
            explanation: "The stock fraction is the stock volume divided by final volume.",
            hint: "Use a part-to-whole ratio.",
            decisiveStep: "Divide 10 by 50.",
            citationChunkIDs: [],
            requiredConcepts: [],
            rejectedAssertions: [],
            verificationExpression: "10 / 50"
        )

        XCTAssertThrowsError(
            try NFShortcutAuthoringValidator.validate(
                [incorrect],
                for: request,
                modelIdentifier: "test.shortcuts"
            )
        ) { error in
            guard case let NFShortcutAuthoringValidationError.violations(notes) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(notes.contains { $0.contains("automatic-scoring metadata") })
        }
    }

    func testShortcutDraftRequiresDisplayMathForNativeTypesetting() throws {
        let request = NFAuthoringRequest(
            capability: .contextualize,
            lab: .quantitative,
            field: .dataScience,
            customTopic: "classifier precision",
            learningObjective: "compute precision",
            style: .numerical,
            difficulty: 0.6,
            count: 1,
            seed: 5,
            aiMode: .automatic,
            allowsShortcutAuthoring: true
        )
        let inlineMath = NFShortcutQuestionDraft(
            prompt: "A classifier has 12 true positives among 15 predicted positives. Compute $TP/(TP+FP)$ using the stated counts.",
            context: "Data science · classifier precision",
            choices: [],
            correctAnswer: "0.8",
            acceptedAnswers: [],
            explanation: "Divide the 12 true positives by all 15 predicted positives to obtain 0.8.",
            hint: "Use predicted positives as the denominator.",
            decisiveStep: "Divide 12 by 15.",
            citationChunkIDs: [],
            requiredConcepts: [],
            rejectedAssertions: [],
            verificationExpression: "12 / 15"
        )

        XCTAssertThrowsError(
            try NFShortcutAuthoringValidator.validate(
                [inlineMath],
                for: request,
                modelIdentifier: "test.shortcuts"
            )
        ) { error in
            guard case let NFShortcutAuthoringValidationError.violations(notes) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(notes.contains { $0.contains("display blocks") })
        }
    }

    func testShortcutDraftRejectsUnbalancedDisplayMath() throws {
        let request = NFAuthoringRequest(
            capability: .contextualize,
            lab: .quantitative,
            field: .dataScience,
            customTopic: "classifier precision",
            learningObjective: "compute precision",
            style: .numerical,
            difficulty: 0.6,
            count: 1,
            seed: 6,
            aiMode: .automatic,
            allowsShortcutAuthoring: true
        )
        let malformedMath = NFShortcutQuestionDraft(
            prompt: "A classifier has 12 true positives among 15 predicted positives. Compute precision using the stated counts.",
            context: "Data science · classifier precision",
            choices: [],
            correctAnswer: "0.8",
            acceptedAnswers: [],
            explanation: "Precision is the supported ratio $$\\frac{12}{15} = 0.8 without a closing delimiter.",
            hint: "Use predicted positives as the denominator.",
            decisiveStep: "Divide 12 by 15.",
            citationChunkIDs: [],
            requiredConcepts: [],
            rejectedAssertions: [],
            verificationExpression: "12 / 15"
        )

        XCTAssertThrowsError(
            try NFShortcutAuthoringValidator.validate(
                [malformedMath],
                for: request,
                modelIdentifier: "test.shortcuts"
            )
        ) { error in
            guard case let NFShortcutAuthoringValidationError.violations(notes) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(notes.contains { $0.contains("$$...$$ display blocks") })
        }
    }

    func testShortcutDraftRejectsUnmatchedSingleDollarInReferenceAnswer() throws {
        let request = NFAuthoringRequest(
            capability: .contextualize,
            lab: .quantitative,
            field: .mathematics,
            customTopic: "linear equations",
            learningObjective: "Solve a one-step linear equation.",
            style: .shortAnswer,
            difficulty: 0.45,
            count: 1,
            seed: 9,
            aiMode: .automatic,
            allowsShortcutAuthoring: true
        )
        let malformedAnswer = NFShortcutQuestionDraft(
            prompt: "For a linear equation with a stated coefficient and constant, solve for the unknown.",
            context: "Mathematics · linear equations",
            choices: [],
            correctAnswer: "$x = 4",
            acceptedAnswers: [],
            explanation: "Subtract the constant, divide by the coefficient, and verify the resulting value in the original equation.",
            hint: "Isolate the term containing the unknown first.",
            decisiveStep: "Apply inverse operations in reverse order.",
            citationChunkIDs: [],
            requiredConcepts: [],
            rejectedAssertions: [],
            verificationExpression: ""
        )

        XCTAssertThrowsError(try NFShortcutAuthoringValidator.validate(
            [malformedAnswer],
            for: request,
            modelIdentifier: "test.shortcuts"
        )) { error in
            guard case let NFShortcutAuthoringValidationError.violations(notes) = error else {
                return XCTFail("Expected validation violations, got \(error)")
            }
            XCTAssertTrue(notes.contains { $0.contains("$$...$$ display blocks") })
        }
    }

    func testShortcutDraftRejectsUnclosedMarkdownFence() throws {
        let request = NFAuthoringRequest(
            capability: .contextualize,
            lab: .logicDebugging,
            field: .computing,
            customTopic: "array bounds debugging",
            learningObjective: "Identify an off-by-one boundary error.",
            style: .shortAnswer,
            difficulty: 0.5,
            count: 1,
            seed: 10,
            aiMode: .automatic,
            allowsShortcutAuthoring: true
        )
        let malformedFence = NFShortcutQuestionDraft(
            prompt: "In array bounds debugging, identify why the final loop iteration reads beyond the collection.",
            context: "Computing · array bounds debugging",
            choices: [],
            correctAnswer: "The upper bound includes the array count.",
            acceptedAnswers: [],
            explanation: "Compare the final index with the valid range.\n\n```swift\nfor index in 0...items.count {",
            hint: "Inspect the largest index produced by the range.",
            decisiveStep: "The last valid index is one less than the count.",
            citationChunkIDs: [],
            requiredConcepts: [],
            rejectedAssertions: [],
            verificationExpression: ""
        )

        XCTAssertThrowsError(try NFShortcutAuthoringValidator.validate(
            [malformedFence],
            for: request,
            modelIdentifier: "test.shortcuts"
        )) { error in
            guard case let NFShortcutAuthoringValidationError.violations(notes) = error else {
                return XCTFail("Expected validation violations, got \(error)")
            }
            XCTAssertTrue(notes.contains { $0.contains("complete Markdown fences") })
        }
    }

    func testShortcutDraftRejectsLearnerVisibleReferenceAnswer() throws {
        let request = NFAuthoringRequest(
            capability: .contextualize,
            lab: .logicDebugging,
            field: .computing,
            customTopic: "graph traversal invariants",
            learningObjective: "identify the invariant that prevents repeated work",
            style: .shortAnswer,
            difficulty: 0.55,
            count: 1,
            seed: 7,
            aiMode: .automatic,
            allowsShortcutAuthoring: true
        )
        let leaked = NFShortcutQuestionDraft(
            prompt: "In graph traversal invariants, explain why a visited-set invariant prevents repeated work.",
            context: "Computing · graph traversal invariants",
            choices: [],
            correctAnswer: "visited-set invariant",
            acceptedAnswers: [],
            explanation: "Marking a node when it enters the frontier prevents the same node from being scheduled repeatedly.",
            hint: "Track when a node first becomes scheduled.",
            decisiveStep: "Connect frontier insertion to the visited-set update.",
            citationChunkIDs: [],
            requiredConcepts: [],
            rejectedAssertions: [],
            verificationExpression: ""
        )

        XCTAssertThrowsError(
            try NFShortcutAuthoringValidator.validate(
                [leaked],
                for: request,
                modelIdentifier: "test.shortcuts"
            )
        ) { error in
            guard case let NFShortcutAuthoringValidationError.violations(notes) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(notes.contains { $0.contains("exposes its reference answer") })
        }
    }

    func testShortcutDraftNumericalAnswerRejectsUnverifiedAlternateAnswers() throws {
        let request = NFAuthoringRequest(
            capability: .contextualize,
            lab: .quantitative,
            field: .chemistry,
            customTopic: "solution dilution",
            learningObjective: "apply the dilution relation",
            style: .numerical,
            difficulty: 0.6,
            count: 1,
            seed: 8,
            aiMode: .automatic,
            allowsShortcutAuthoring: true
        )
        let alternate = NFShortcutQuestionDraft(
            prompt: "A solution uses 10 mL of stock to prepare 50 mL total. What decimal fraction of the final volume is stock?",
            context: "Chemistry · solution dilution",
            choices: [],
            correctAnswer: "0.2",
            acceptedAnswers: ["0.5"],
            explanation: "The stock fraction is the stock volume divided by the final volume, giving a decimal result.",
            hint: "Use a part-to-whole ratio.",
            decisiveStep: "Divide 10 by 50.",
            citationChunkIDs: [],
            requiredConcepts: [],
            rejectedAssertions: [],
            verificationExpression: "10 / 50"
        )

        XCTAssertThrowsError(
            try NFShortcutAuthoringValidator.validate(
                [alternate],
                for: request,
                modelIdentifier: "test.shortcuts"
            )
        ) { error in
            guard case let NFShortcutAuthoringValidationError.violations(notes) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(notes.contains { $0.contains("automatic-scoring metadata") })
        }
    }

}

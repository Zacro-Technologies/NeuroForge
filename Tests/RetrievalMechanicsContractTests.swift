import SwiftData
import XCTest
@testable import NeuroForge

final class RetrievalMechanicsContractTests: XCTestCase {
    @MainActor
    func testSelfCheckRequiresRecallThenReferenceThenRating() throws {
        let runtime = NFUniversalSessionRuntime(request: SessionRequest(
            lab: .retrieval,
            source: .focused,
            seed: 900,
            requestedItemCount: 1,
            mechanicID: "retrieval.fallback-variant-0"
        ))
        guard case .selfCheck = runtime.exercise.interaction else {
            return XCTFail("Expected the forced free-recall self-check mechanic")
        }

        runtime.selfCheckReflection = "My recalled explanation"
        XCTAssertTrue(runtime.canSubmit)
        XCTAssertFalse(runtime.selfCheckReferenceRevealed)
        runtime.submitResponse()
        XCTAssertEqual(runtime.stage, .confidence)
        XCTAssertFalse(runtime.selfCheckReferenceRevealed)

        let container = try ModelContainer(
            for: Schema(NFSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = AppStore(context: container.mainContext)
        runtime.commit(confidence: .fairlyConfident, store: store)
        XCTAssertEqual(runtime.stage, .selfCheckComparison)
        XCTAssertTrue(runtime.selfCheckReferenceRevealed)
        XCTAssertFalse(runtime.canSubmit, "Seeing the reference still requires an explicit comparison")
        XCTAssertTrue(store.attempts.isEmpty, "The attempt must not persist before the learner rates the match")
        runtime.selfCheckRating = .matched
        XCTAssertTrue(runtime.canSubmit)
        runtime.saveSelfCheck(store: store)
        XCTAssertEqual(store.attempts.count, 1)
    }

    func testAllEightRequiredRetrievalFormsAreTypedAndSourceGrounded() throws {
        let documentID = UUID().uuidString
        let chunkID = "chunk.retrieval.contract.1"
        let fact = NFExerciseGroundingFact(
            id: "fact.retrieval.contract",
            statement: "Increasing damping reduces oscillation amplitude under the stated linear model.",
            expectedAnswer: "Greater damping reduces oscillation amplitude.",
            acceptedAlternatives: ["More damping lowers the oscillation amplitude."],
            citationIDs: [chunkID]
        )
        let context = NFExerciseSourceContext(
            primaryField: .engineering,
            topic: "damped oscillation",
            materialTitle: "Dynamics notes",
            sourceDocumentIDs: [documentID],
            sourceChunkIDs: [chunkID],
            groundingFacts: [fact]
        )
        var observedTags = Set<String>()

        for variant in 0..<9 {
            let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
                seed: UInt64(900 + variant),
                index: variant,
                lab: .retrieval,
                purpose: .documentPractice,
                sourceContext: context,
                preferredAssessmentMechanicID: "retrieval.fallback-variant-\(variant)"
            ))

            XCTAssertNoThrow(try NFExerciseSchemaValidator.validate(exercise))
            XCTAssertEqual(exercise.citations.count, 1)
            XCTAssertEqual(exercise.citations.first?.documentID, documentID)
            XCTAssertEqual(exercise.citations.first?.sourceChunkID, chunkID)
            XCTAssertEqual(exercise.provenance.sourceDocumentIDs, [documentID])
            XCTAssertEqual(exercise.provenance.sourceChunkIDs, [chunkID])
            XCTAssertTrue(exercise.tags.contains("source-grounded"))
            observedTags.formUnion(exercise.tags)

            switch variant {
            case 0:
                guard case .selfCheck = exercise.interaction else { return XCTFail("Free recall must use typed self-check") }
            case 1, 2, 6, 7:
                guard case .shortText = exercise.interaction else { return XCTFail("Text reconstruction must use typed short text") }
            case 3:
                guard case .selfCheck = exercise.interaction else { return XCTFail("Concept explanation must use typed self-check") }
            case 4, 8:
                guard case .singleChoice = exercise.interaction else { return XCTFail("Recognition/code tracing must use typed choices") }
            case 5:
                guard case .orderedSteps = exercise.interaction else { return XCTFail("Derivation ordering must use typed ordered steps") }
            default:
                XCTFail("Unexpected retrieval variant")
            }
        }

        XCTAssertTrue([
            "free-recall", "cloze", "short-answer", "equation-reconstruction",
            "derivation-ordering", "explain-a-concept", "figure-interpretation", "code-tracing"
        ].allSatisfy(observedTags.contains))
    }

    func testEquationFigureAndCodeFormsProvideAccessibleRepresentationsWithoutLeakingKeys() throws {
        let chunkID = "chunk.retrieval.representation"
        let answer = "The invariant remains constant."
        let context = NFExerciseSourceContext(
            primaryField: .mathematics,
            sourceDocumentIDs: [UUID().uuidString],
            sourceChunkIDs: [chunkID],
            groundingFacts: [NFExerciseGroundingFact(
                id: "fact.representation",
                statement: "The transformation preserves the invariant.",
                expectedAnswer: answer,
                acceptedAlternatives: [],
                citationIDs: [chunkID]
            )]
        )

        for variant in [6, 7, 8] {
            let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
                seed: UInt64(1_000 + variant),
                index: variant,
                lab: .retrieval,
                purpose: .documentPractice,
                sourceContext: context,
                preferredAssessmentMechanicID: "retrieval.fallback-variant-\(variant)"
            ))
            let renderedRepresentation = exercise.representations.contains { representation in
                switch (variant, representation) {
                case (6, .equation), (7, .table), (8, .code): true
                default: false
                }
            }
            XCTAssertTrue(renderedRepresentation)
            let preAnswerSurface = ([exercise.prompt, exercise.instructions] + exercise.representations.compactMap {
                if case let .code(_, source, _) = $0 { return source }
                return nil
            }).joined(separator: " ")
            XCTAssertFalse(preAnswerSurface.contains(answer))
        }
    }
}

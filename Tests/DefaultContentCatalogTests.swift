import Foundation
import SwiftData
import XCTest

@testable import NeuroForge

final class DefaultContentCatalogTests: XCTestCase {
    func testCatalogExposesEveryDeterministicFamilyExactlyOnce() {
        XCTAssertEqual(NFDefaultContentCatalog.version, 1)
        XCTAssertEqual(NFDefaultContentCatalog.audit(), [])
        XCTAssertEqual(NFDefaultContentCatalog.activities.count, 58)
        XCTAssertEqual(
            NFDefaultContentCatalog.selectableFieldPairingCount,
            58 * STEMField.allCases.count
        )

        let expectedCounts: [TrainingLab: Int] = [
            .mentalMath: 10,
            .spatial: 6,
            .quantitative: 8,
            .scientificReasoning: 9,
            .logicDebugging: 9,
            .retrieval: 9,
            .transfer: 7
        ]
        for lab in TrainingLab.allCases {
            let activities = NFDefaultContentCatalog.activities(for: lab)
            XCTAssertEqual(activities.count, expectedCounts[lab], lab.rawValue)
            XCTAssertEqual(
                NFFallbackExerciseGenerator.variantCount(for: lab),
                expectedCounts[lab],
                lab.rawValue
            )
            XCTAssertEqual(
                Set(activities.map(\.variant)),
                Set(0..<(expectedCounts[lab] ?? 0)),
                lab.rawValue
            )
        }
    }

    func testEveryCatalogEntrySelectsARealDeterministicScorableFamily() throws {
        for (activityIndex, activity) in NFDefaultContentCatalog.activities.enumerated() {
            for (fieldIndex, field) in STEMField.allCases.enumerated() {
                let purpose = NFExercisePurpose.practice
                let request = NFExerciseGenerationRequest(
                    seed: UInt64(50_000 + activityIndex * 100 + fieldIndex),
                    index: 0,
                    lab: activity.lab,
                    purpose: purpose,
                    localeIdentifier: "en",
                    sourceContext: NFExerciseSourceContext(
                        primaryField: field,
                        topic: activity.title,
                        targetSkills: [activity.lab.skillID]
                    ),
                    targetDifficulty: activity.defaultDifficulty,
                    preferredAssessmentMechanicID: activity.mechanicID
                )

                let first = try NFFallbackExerciseGenerator.generate(request)
                let duplicate = try NFFallbackExerciseGenerator.generate(request)
                XCTAssertEqual(first, duplicate, activity.id)
                XCTAssertEqual(first.lab, activity.lab, activity.id)
                XCTAssertEqual(first.purpose, purpose, activity.id)
                XCTAssertEqual(first.evidenceClass, activity.defaultEvidenceClass, activity.id)
                XCTAssertTrue(
                    first.templateID.contains(activity.templateSlug),
                    "\(activity.id) produced \(first.templateID)"
                )
                XCTAssertEqual(first.sourceContext.primaryField, field, activity.id)
                let localizedField = field.localizedTitle(locale: Locale(identifier: "en"))
                XCTAssertTrue(
                    first.contextText?.contains(localizedField) == true,
                    "\(activity.id) did not visibly frame the selected \(localizedField) perspective"
                )
                XCTAssertNoThrow(try NFExerciseSchemaValidator.validate(first), activity.id)

                let score = NFExerciseScoringEngine.score(
                    correctResponse(for: first.interaction),
                    for: first
                )
                XCTAssertTrue(score.isCorrect, activity.id)
                XCTAssertEqual(score.credit, 1, accuracy: 0.000_001, activity.id)
            }
        }
    }

    func testSearchSupportsTaxonomyEnglishAndJapanese() throws {
        XCTAssertEqual(
            try XCTUnwrap(NFDefaultContentCatalog.search("cube folding").first).id,
            "nf.default.spatial.cube-net"
        )
        XCTAssertEqual(
            try XCTUnwrap(NFDefaultContentCatalog.search("base rate bayes").first).id,
            "nf.default.quantitative.bayes"
        )
        XCTAssertEqual(
            try XCTUnwrap(NFDefaultContentCatalog.search(
                "反例",
                locale: Locale(identifier: "ja")
            ).first).id,
            "nf.default.logic.counterexample"
        )
        let singleCJKCharacter = NFDefaultContentCatalog.search(
            "比",
            locale: Locale(identifier: "ja")
        )
        XCTAssertFalse(singleCJKCharacter.isEmpty)
        XCTAssertLessThan(singleCJKCharacter.count, NFDefaultContentCatalog.activities.count)
        XCTAssertTrue(singleCJKCharacter.contains {
            $0.id == "nf.default.transfer.interacting-variables"
        })

        let puzzles = NFDefaultContentCatalog.search(
            "boundary",
            lab: .logicDebugging,
            kind: .puzzle
        )
        XCTAssertTrue(puzzles.contains(where: { $0.id == "nf.default.logic.boundary-bug" }))
        XCTAssertTrue(puzzles.allSatisfy { $0.lab == .logicDebugging && $0.kind == .puzzle })
    }

    func testCatalogTitlesAndResearchBoundariesAreLocalized() {
        let japanese = Locale(identifier: "ja")
        let english = Locale(identifier: "en")
        let spatialIDs = [
            "nf.default.spatial.coordinate-rotation",
            "nf.default.spatial.object-rotation",
            "nf.default.spatial.cross-section",
            "nf.default.spatial.top-view",
            "nf.default.spatial.cube-net",
            "nf.default.spatial.vector-reflection"
        ]
        let retrievalIDs = [
            "nf.default.retrieval.free-recall",
            "nf.default.retrieval.precision-recall",
            "nf.default.retrieval.cloze",
            "nf.default.retrieval.teach-back",
            "nf.default.retrieval.equation"
        ]
        var expectedReferences = Dictionary(
            uniqueKeysWithValues: spatialIDs.map {
                ($0, Set([NFDefaultContentReference.uttal2013]))
            }
        )
        for id in retrievalIDs {
            expectedReferences[id] = [.roedigerKarpicke2006, .cepeda2006]
        }
        expectedReferences["nf.default.quantitative.bayes"] = [.mcdowellJacobs2017]
        expectedReferences["nf.default.transfer.causal-map"] = [.alfieri2013]

        for activity in NFDefaultContentCatalog.activities {
            XCTAssertNotEqual(
                activity.localizedTitle(locale: japanese),
                activity.localizedTitle(locale: english),
                activity.id
            )
            XCTAssertTrue(
                containsJapaneseScript(activity.localizedTitle(locale: japanese)),
                activity.id
            )
            XCTAssertNotEqual(
                activity.localizedSummary(locale: japanese),
                activity.localizedSummary(locale: english),
                activity.id
            )
            XCTAssertTrue(
                containsJapaneseScript(activity.localizedSummary(locale: japanese)),
                activity.id
            )
            XCTAssertEqual(
                Set(activity.researchBasis.references),
                expectedReferences[activity.id] ?? [],
                "Unexpected research mapping for \(activity.id)"
            )
            for reference in activity.researchBasis.references {
                XCTAssertTrue(NFDefaultContentReference.allCases.contains(reference), activity.id)
                XCTAssertEqual(reference.url.scheme, "https", activity.id)
                XCTAssertFalse(reference.shortCitation.isEmpty, activity.id)
            }
            XCTAssertFalse(activity.researchBasis.localizedNote(locale: english).isEmpty, activity.id)
            XCTAssertTrue(
                containsJapaneseScript(activity.researchBasis.localizedNote(locale: japanese)),
                activity.id
            )
        }
    }

    @MainActor
    func testCatalogLaunchCarriesFieldPracticeEvidenceAndExposureSeed() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let activity = try XCTUnwrap(
            NFDefaultContentCatalog.activity(id: "nf.default.transfer.rate")
        )
        let selection = NFDefaultContentSelection(activity: activity, field: .chemistry)

        XCTAssertTrue(store.beginDefaultCatalogSession(selection))
        let firstRequest = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(firstRequest.evidenceClass, .practice)
        XCTAssertEqual(firstRequest.field, .chemistry)
        XCTAssertEqual(firstRequest.mechanicID, activity.mechanicID)
        XCTAssertNil(firstRequest.transferBrief)

        let exercise = NFDeterministicSessionExerciseFactory.makeExercise(
            request: firstRequest,
            index: 0,
            assessmentDescriptor: nil
        )
        XCTAssertEqual(exercise.evidenceClass, .practice)
        XCTAssertEqual(exercise.purpose, .practice)
        XCTAssertEqual(exercise.sourceContext.primaryField, .chemistry)
        XCTAssertEqual(exercise.title, "Transfer practice")

        let response = correctResponse(for: exercise.interaction)
        let result = NFExerciseScoringEngine.score(response, for: exercise)
        try store.saveExerciseAttempt(
            attemptID: UUID(),
            sessionID: UUID(),
            exercise: exercise,
            response: response,
            result: result,
            confidence: .fairlyConfident,
            shownAt: Date(),
            activeDuration: 30,
            source: .focused
        )
        XCTAssertEqual(store.attempts.first?.assessmentMechanicID, activity.mechanicID)
        store.activeSessionRequest = nil

        XCTAssertTrue(store.beginDefaultCatalogSession(selection))
        let repeatedRequest = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertNotEqual(repeatedRequest.seed, firstRequest.seed)
        store.activeSessionRequest = nil

        XCTAssertTrue(store.beginDefaultCatalogSession(
            NFDefaultContentSelection(activity: activity, field: .physics)
        ))
        XCTAssertNotEqual(store.activeSessionRequest?.seed, repeatedRequest.seed)
    }

    func testPuzzleCatalogStaysBoundedToNamedMechanics() {
        let puzzles = NFDefaultContentCatalog.activities.filter { $0.kind == .puzzle }
        XCTAssertGreaterThanOrEqual(puzzles.count, 20)
        XCTAssertTrue(puzzles.contains(where: { $0.id == "nf.default.spatial.cube-net" }))
        XCTAssertTrue(puzzles.contains(where: { $0.id == "nf.default.logic.proof-builder" }))
        XCTAssertTrue(puzzles.contains(where: { $0.id == "nf.default.mental.calculation-chain" }))

        let prohibitedClaims = ["iq", "brain age", "intelligence boost", "sharper brain"]
        for activity in NFDefaultContentCatalog.activities {
            let text = [activity.title, activity.summary, activity.researchBasis.localizedNote]
                .joined(separator: " ")
                .lowercased()
            XCTAssertFalse(
                prohibitedClaims.contains(where: text.contains),
                activity.id
            )
        }
    }

    private func correctResponse(for interaction: NFExerciseInteraction) -> NFExerciseResponse {
        switch interaction {
        case let .numeric(schema):
            .numeric(
                NFNumericSubmission(
                    value: String(schema.answer.value),
                    unit: schema.answer.canonicalUnit
                )
            )
        case let .singleChoice(schema):
            .singleChoice(optionID: schema.correctOptionID)
        case let .multipleChoice(schema):
            .multipleChoice(optionIDs: schema.correctOptionIDs)
        case let .orderedSteps(schema):
            .orderedSteps(stepIDs: schema.correctOrder)
        case let .shortText(schema):
            .shortText(schema.expectedAnswer)
        case let .selfCheck(schema):
            .selfCheck(NFSelfCheckSubmission(
                rating: .matched,
                reflection: schema.asksForReflection ? "Matched the reference." : nil
            ))
        case let .claimEvidence(schema):
            .claimEvidence(NFClaimEvidenceSubmission(pairs: schema.correctPairs))
        case let .logicState(schema):
            .logicState(
                NFLogicStateSubmission(
                    finalState: schema.expectedFinalState,
                    violatedRuleID: schema.expectedViolatedRuleID
                )
            )
        }
    }

    private func containsJapaneseScript(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)
                || (0x3400...0x9FFF).contains(scalar.value)
        }
    }

    @MainActor
    private func makeStore() throws -> (store: AppStore, container: ModelContainer) {
        let schema = Schema([
            UserProfileRecord.self,
            InputCalibrationRecord.self,
            ProgressAnnotationRecord.self,
            AttemptRecord.self,
            AttemptReflectionRecord.self,
            SourceDocumentRecord.self,
            SourceChunkRecord.self,
            AIGenerationRecord.self,
            WeeklyTransferStateRecord.self,
            ReassessmentStateRecord.self,
            SessionCheckpointRecord.self,
            DailyPlanRecord.self,
            ItemReportRecord.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let documentRoot = FileManager.default.temporaryDirectory.appending(
            path: "NF-Default-Catalog-Documents-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        return (
            AppStore(
                context: container.mainContext,
                documentStorageRootURL: documentRoot
            ),
            container
        )
    }
}

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
                if case .selfCheck = first.interaction {
                    XCTAssertEqual(score.outcome, .selfReported, activity.id)
                } else {
                    XCTAssertTrue(score.isCorrect, activity.id)
                    XCTAssertEqual(score.credit, 1, accuracy: 0.000_001, activity.id)
                }
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
    func testCatalogCallerForwardsElapsedOnlyWithoutUnlockingLegacyFluency() throws {
        let (store, container) = try makeStore(); defer { _ = container }
        let activity = try XCTUnwrap(NFDefaultContentCatalog.activity(id: "nf.default.transfer.rate"))
        let selection = NFDefaultContentSelection(activity: activity, field: .chemistry)
        XCTAssertFalse(store.reviewedFluencyReadiness(lab: activity.lab, mechanicID: activity.mechanicID).timingEligible)
        XCTAssertTrue(store.beginDefaultCatalogSession(selection, requestedItemCount: 1,
            timingCondition: .init(.elapsedOnly)))
        let request = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(request.timingCondition?.mode, .elapsedOnly)
        XCTAssertEqual(request.mechanicID, activity.mechanicID)
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.showsTimer); XCTAssertFalse(runtime.usesTimedMode)
        XCTAssertEqual(runtime.workloadMode, .practice)
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
        XCTAssertEqual(exercise.title, "Choose a structure, then solve")
        let contract = try XCTUnwrap(NFTransferRelationshipContract.make(exercise: exercise))
        let runtime = NFUniversalSessionRuntime(request: firstRequest)
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        runtime.resume(); runtime.acknowledgePresented()
        XCTAssertEqual(runtime.exercise, exercise)
        runtime.setTransferRelationship(NFTransferRelationshipContract.productID)
        runtime.submitInline(store: store)
        XCTAssertFalse(runtime.awaitsTransferRelationship)
        XCTAssertTrue(store.attempts.isEmpty, "The relationship save alone is not an answer.")
        runtime.setTransferTotal(String(contract.targetTotal))
        runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback)
        XCTAssertEqual(runtime.lastResult?.credit, 1)
        XCTAssertEqual(store.attempts.count, 1)
        runtime.releaseWriter()
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


@MainActor
extension DefaultContentCatalogTests {
    private struct ReviewedFixture {
        let root: URL
        let store: AppStore
        let container: ModelContainer
        let activity: NFDefaultContentActivity
        let scope: NFEditorialCatalogScope
        let admissions: NFEditorialAdmissionContext
        let request: SessionRequest
        let family = NFEditorialFamilyScope(objectiveID: "QA.catalog.compensation", familyID: "QA.catalog.family")
    }
    private func reviewedFixture(perBand: Int = 6, prerequisiteBand: NFEditorialBand? = nil,
                                 activityID: String = "nf.default.mental.compensation",
                                 bands: [NFEditorialBand] = NFEditorialBand.allCases) throws -> ReviewedFixture {
        let (initial, container) = try makeStore()
        // A real completed-onboarding profile is part of commit provenance.
        // The fallback launch profile cannot authorize an independent observation.
        var onboarding = OnboardingDraft()
        onboarding.timingMode = .adaptive // Permit each test's explicit untimed/elapsed choice.
        container.mainContext.insert(UserProfileRecord(draft: onboarding))
        try container.mainContext.save()
        initial.reload()
        XCTAssertNotNil(initial.profile)
        let root = FileManager.default.temporaryDirectory.appending(path: "NF-Reviewed-Catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let activity = try XCTUnwrap(NFDefaultContentCatalog.activity(id: activityID))
        let request = initial.reviewedPracticeRequest(lab: activity.lab, activity: activity, field: .general,
            requestedItemCount: 3, timingCondition: .init(.untimed), targetDifficulty: activity.defaultDifficulty)
        let scope = NFEditorialCatalogScope(catalogVersion: NFDefaultContentCatalog.version, activityID: activity.id, field: .general)
        var entries: [NFEditorialAdmissionEntry] = [], seen: Set<String> = []
        var outsider: NFEditorialAdmissionEntry?
        for questionID in NFOfflineQuestionBank.rotationBank.questionIDs(for: activity.lab) {
            guard let ordinal = NFOfflineQuestionBank.ordinal(forQuestionID: questionID, lab: activity.lab) else { continue }
            let exercise = NFDeterministicSessionExerciseFactory.makeExercise(request: request.launchOnly(offlineQuestionOrdinals: [ordinal]), index: 0, assessmentDescriptor: nil)
            guard exercise.availabilityReason == nil, NFEditorialNativeProtocol.supports(exercise),
                  let metadata = exercise.contractMetadata, seen.insert(metadata.semanticFingerprint).inserted else { continue }
            let isTarget = scope.matches(exercise)
            if !isTarget && outsider != nil { continue }
            if isTarget && entries.count >= perBand * bands.count { continue }
            let band = isTarget ? bands[min(bands.count - 1, entries.count / perBand)] : .b2
            // Artificial policy fixtures bind actual native contracts. These
            // rows are not editorial review/signoff of the shipped content.
            let demand = NFEditorialDemandRecord(objectiveID: "QA.catalog.compensation", familyID: "QA.catalog.family",
                structureID: "QA.catalog.structure.\(entries.count % 2)", semanticFingerprint: metadata.semanticFingerprint,
                editorialBand: band, demandVector: .init(reasoningSteps: band.ordinal,
                    quantityDomain: ["basis": "synthetic admission fixture"], representationMappings: ["numeric"], misconceptionClasses: [],
                    abstraction: "concrete", relevantGivens: 2, irrelevantGivens: 0, missingGivens: 0,
                    scaffoldConditionID: "essential-only", prerequisiteConceptIDs: []),
                bandContractVersion: "QA.catalog.band.v1", calibrationStatus: .editorial, calibrationVersion: nil,
                independentEligible: true, protectedEligible: false, assistancePolicyID: NFEditorialNativeProtocol.toolConditionID,
                answerContractVersion: "QA.catalog.answer.v1", expectedDurationRange: .init(minimumSeconds: 10, maximumSeconds: 40),
                representationIDs: ["numeric"], prerequisiteObjectiveIDs: band == prerequisiteBand ? ["QA.not-yet-demonstrated"] : [])
            let entry = NFEditorialAdmissionEntry(id: isTarget ? "QA.catalog.entry.\(entries.count)" : "QA.catalog.outsider",
                bankQuestionID: questionID, exerciseDigest: try NFLocalItemCheckpoint.digest(exercise), scorerVersion: NFExerciseScoringEngine.scoringVersion,
                lab: activity.lab, contentLocale: request.localeIdentifier, demand: demand)
            if isTarget { entries.append(entry) } else { outsider = entry }
            if entries.count == perBand * bands.count && outsider != nil { break }
        }
        XCTAssertEqual(entries.count, perBand * bands.count)
        entries.append(try XCTUnwrap(outsider))
        let admissions = NFEditorialAdmissionContext(version: "QA.catalog.preview.v1", entries: entries)
        let repository = NFLocalSessionRepository(url: root.appending(path: "sessions-v1.json"), ownerDeviceID: UUID(), editorialAdmissions: admissions)
        let store = AppStore(context: container.mainContext,
            nextDayEnhancementCache: NFNextDayEnhancementCache(rootURL: root.appending(path: "cache")),
            documentStorageRootURL: root.appending(path: "documents"), localSessionRepository: repository,
            adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(fileURL: root.appending(path: "history.json")),
            offlineQuestionRotation: NFOfflineQuestionRotation(store: NFMemoryOfflineQuestionRotationStateStore()),
            temporaryArtifactsRootURL: root, allowsSharedWidgetPublishing: false)
        return .init(root: root, store: store, container: container, activity: activity, scope: scope, admissions: admissions, request: request)
    }
    private func launchReviewed(_ fixture: ReviewedFixture, band: NFEditorialBand? = .b2, count: Int = 3,
                                timing: NFSessionTimingCondition = .init(.untimed)) throws -> NFUniversalSessionRuntime {
        XCTAssertTrue(fixture.store.beginDefaultCatalogSession(.init(activity: fixture.activity, field: .general),
            requestedItemCount: count, timingCondition: timing, editorialStartingBand: band, editorialStartingFamilyScope: fixture.family), fixture.store.lastErrorMessage ?? "")
        let request = try XCTUnwrap(fixture.store.activeSessionRequest)
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: fixture.store)); runtime.resume(); runtime.acknowledgePresented()
        return runtime
    }
    private func answerReviewed(_ runtime: NFUniversalSessionRuntime, store: AppStore) throws {
        runtime.acknowledgePresented()
        switch runtime.exercise.interaction {
        case let .numeric(schema):
            runtime.numericValue = String(schema.answer.value); runtime.numericUnit = schema.answer.canonicalUnit ?? ""
        case let .singleChoice(schema): runtime.singleChoiceID = schema.correctOptionID
        default: return XCTFail("The fixture must use an actual supported native contract")
        }
        runtime.chooseConfidence(.fairlyConfident); runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertNil(runtime.saveError)
    }

    func testReviewedPreviewReadsAllBandsAndActualDemandsWithoutCreatingPlansOrReservations() async throws {
        let f = try reviewedFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let before = try NFDataArchiveRawSnapshot.canonicalEncode(NFDataArchiveRawCapture.capture(context: f.container.mainContext))
        let archiveURL = f.root.appending(path: "sessions-v1.json")
        let archiveBefore = FileManager.default.fileExists(atPath: archiveURL.path) ? try Data(contentsOf: archiveURL) : nil
        let revision = f.store.localSessions.archive.transactionRevision
        let request = f.store.reviewedPracticeRequest(lab: f.activity.lab, activity: f.activity, field: .general,
            requestedItemCount: 3, timingCondition: .init(.untimed), targetDifficulty: f.activity.defaultDifficulty)
        let preview = try await f.store.reviewedStartingPreview(request: request, catalogScope: f.scope)
        XCTAssertEqual(preview.state, .feasible)
        XCTAssertEqual(Set(preview.choices.map(\.band)), Set(NFEditorialBand.allCases))
        XCTAssertTrue(preview.choices.allSatisfy { $0.scope == f.family && $0.availableUniqueCount == 6 && $0.canStartRequestedCount })
        for choice in preview.choices {
            XCTAssertEqual(choice.minimumReasoningSteps, choice.band.ordinal)
            XCTAssertEqual(choice.maximumReasoningSteps, choice.band.ordinal)
        }
        XCTAssertNil(f.store.activeSessionRequest)
        XCTAssertNil(f.store.localSessions.archive.offlineRotationLedger)
        XCTAssertNil(f.store.localSessions.archive.adaptiveItemReceipts)
        XCTAssertEqual(f.store.localSessions.archive.transactionRevision, revision)
        let archiveAfter = FileManager.default.fileExists(atPath: archiveURL.path) ? try Data(contentsOf: archiveURL) : nil
        XCTAssertEqual(archiveAfter, archiveBefore, "Preview must preserve both an absent archive and any bytes created by AppStore bootstrap")
        XCTAssertEqual(try NFDataArchiveRawSnapshot.canonicalEncode(NFDataArchiveRawCapture.capture(context: f.container.mainContext)), before)
    }

    func testCatalogReviewedChoiceForwardsBandAndScopeAndNextCannotSelectAdmittedOtherMechanic() throws {
        let f = try reviewedFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let runtime = try launchReviewed(f); defer { runtime.releaseWriter() }
        XCTAssertNil(runtime.request.mechanicID, "This new exact-bank route must not reuse the legacy mechanic recipe")
        XCTAssertEqual(runtime.request.ordinaryDelivery?.editorialPolicy?.schemaVersion, 3)
        XCTAssertEqual(runtime.request.ordinaryDelivery?.editorialPolicy?.catalogScope, f.scope)
        XCTAssertEqual(runtime.request.ordinaryDelivery?.editorialPolicy?.initialUserBand, .b2)
        XCTAssertEqual(runtime.request.field, .general)
        for _ in 0..<3 {
            XCTAssertTrue(f.scope.matches(runtime.exercise))
            let id = try XCTUnwrap(f.store.localSessions.archive.sessions.first?.checkpoint.ordinaryReservationDecisionID)
            XCTAssertEqual(f.store.localSessions.archive.adaptiveItemReceipts?[id]?.editorialDecision?.selection.deliveredBand, .b2)
            try answerReviewed(runtime, store: f.store); runtime.next(store: f.store)
            XCTAssertNil(runtime.saveError)
        }
        XCTAssertEqual(f.store.attempts.count, 3)
        XCTAssertTrue(f.store.localSessions.archive.snapshots.allSatisfy { f.scope.matches($0.exercise) })
    }

    func testCatalogReviewedReplaceAndColdResumeRetainOriginalActivityFieldAndDraft() throws {
        let f = try reviewedFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let runtime = try launchReviewed(f)
        runtime.numericValue = "unfinished"; runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: f.store))
        let original = try XCTUnwrap(f.store.localSessions.archive.sessions.first)
        let prepared = try f.store.prepareAdaptiveReplacement(request: original.request, predecessor: original.checkpoint,
            command: try runtime.sessionWriterCommand())
        let accepted = try f.store.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint)
        XCTAssertTrue(f.scope.matches(try XCTUnwrap(accepted.checkpoint.exercise)))
        XCTAssertEqual(accepted.request.ordinaryDelivery?.editorialPolicy?.catalogScope, f.scope)
        XCTAssertEqual(f.store.localSessions.archive.retiredOrdinaryDrafts?[original.checkpoint.slotID.uuidString]?.checkpoint.response, original.checkpoint.response)
        runtime.releaseWriter()
        let reopenedRepository = NFLocalSessionRepository(url: f.root.appending(path: "sessions-v1.json"),
            ownerDeviceID: f.store.localSessions.ownerDeviceID, editorialAdmissions: f.admissions)
        XCTAssertNil(reopenedRepository.loadError)
        let saved = try XCTUnwrap(reopenedRepository.archive.sessions.first)
        XCTAssertEqual(saved.checkpoint, accepted.checkpoint)
        XCTAssertEqual(saved.request.ordinaryDelivery?.editorialPolicy?.catalogScope, f.scope)
        var request = saved.request; request.localCheckpoint = saved.checkpoint; request.localSessionID = saved.id
        let restored = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(f.scope.matches(restored.exercise))
        XCTAssertEqual(restored.exercise, accepted.checkpoint.exercise)
        let nextStore = AppStore(context: f.container.mainContext, localSessionRepository: reopenedRepository,
            temporaryArtifactsRootURL: f.root, allowsSharedWidgetPublishing: false)
        defer { restored.releaseWriter() }
        XCTAssertTrue(restored.checkpointDraft(store: nextStore)); restored.resume(); restored.acknowledgePresented()
        try answerReviewed(restored, store: nextStore); restored.next(store: nextStore)
        XCTAssertNil(restored.saveError); XCTAssertTrue(f.scope.matches(restored.exercise))
    }

    func testPrelaunchFieldMismatchAndMissingPrerequisitesCannotOfferOrLaunchHigherBand() async throws {
        let f = try reviewedFixture(prerequisiteBand: .b3); defer { try? FileManager.default.removeItem(at: f.root) }
        let preview = try await f.store.reviewedStartingPreview(request: f.request, catalogScope: f.scope)
        let unavailableB3 = try XCTUnwrap(preview.choices.first { $0.band == .b3 })
        XCTAssertEqual(unavailableB3.availableUniqueCount, 0)
        XCTAssertEqual(unavailableB3.unavailabilityReasons, [.prerequisites])
        XCTAssertFalse(unavailableB3.canStartRequestedCount)
        XCTAssertTrue(preview.choices.contains { $0.band == .b4 }, "Explicitly reviewed independent B4 need not borrow B3's prerequisite")
        XCTAssertFalse(f.store.beginDefaultCatalogSession(.init(activity: f.activity, field: .general), requestedItemCount: 3,
            timingCondition: .init(.untimed), editorialStartingBand: .b3, editorialStartingFamilyScope: f.family))
        XCTAssertNil(f.store.localSessions.archive.offlineRotationLedger)
        let other = f.store.reviewedPracticeRequest(lab: f.activity.lab, activity: f.activity, field: .chemistry,
            requestedItemCount: 3, timingCondition: .init(.untimed), targetDifficulty: f.activity.defaultDifficulty)
        let otherScope = NFEditorialCatalogScope(catalogVersion: NFDefaultContentCatalog.version, activityID: f.activity.id, field: .chemistry)
        let otherPreview = try await f.store.reviewedStartingPreview(request: other, catalogScope: otherScope)
        XCTAssertEqual(otherPreview.state, .activityUnavailable)
        XCTAssertFalse(f.store.beginDefaultCatalogSession(.init(activity: f.activity, field: .chemistry), requestedItemCount: 3,
            timingCondition: .init(.untimed), editorialStartingBand: .b2, editorialStartingFamilyScope: f.family))
        XCTAssertNil(f.store.activeSessionRequest); XCTAssertTrue(f.store.attempts.isEmpty)
    }

    func testReviewedPrelaunchShortageRequiresExplicitSmallerCountAndRechecksAtAcceptance() async throws {
        let f = try reviewedFixture(perBand: 2); defer { try? FileManager.default.removeItem(at: f.root) }
        let preview = try await f.store.reviewedStartingPreview(request: f.request, catalogScope: f.scope)
        let choice = try XCTUnwrap(preview.choices.first { $0.band == .b2 })
        XCTAssertEqual(choice.availableUniqueCount, 2); XCTAssertFalse(choice.canStartRequestedCount)
        XCTAssertFalse(f.store.beginDefaultCatalogSession(.init(activity: f.activity, field: .general), requestedItemCount: 3,
            timingCondition: .init(.untimed), editorialStartingBand: choice.band, editorialStartingFamilyScope: choice.scope))
        XCTAssertNil(f.store.localSessions.archive.offlineRotationLedger)
        let runtime = try launchReviewed(f, count: choice.availableUniqueCount); defer { runtime.releaseWriter() }
        XCTAssertEqual(runtime.request.requestedItemCount, 2)
        XCTAssertEqual(f.store.localSessions.archive.selectionLedger?.slots.count, 1)
    }

    func testReviewedPreviewUsesCurrentQuarantineAndUntimedElapsedDoNotChangeDemand() async throws {
        let f = try reviewedFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let baseline = try await f.store.reviewedStartingPreview(request: f.request, catalogScope: f.scope)
        let elapsed = f.store.reviewedPracticeRequest(lab: f.activity.lab, activity: f.activity, field: .general,
            requestedItemCount: 3, timingCondition: .init(.elapsedOnly), targetDifficulty: f.activity.defaultDifficulty)
        XCTAssertEqual(elapsed.timingCondition?.mode, .elapsedOnly)
        let displayOnly = try await f.store.reviewedStartingPreview(request: elapsed, catalogScope: f.scope)
        XCTAssertEqual(baseline.choices, displayOnly.choices)
        let entry = try XCTUnwrap(f.admissions.entries.first { $0.demand.editorialBand == .b2 && $0.id != "QA.catalog.outsider" })
        let ordinal = try XCTUnwrap(NFOfflineQuestionBank.ordinal(forQuestionID: entry.bankQuestionID, lab: f.activity.lab))
        let exercise = NFDeterministicSessionExerciseFactory.makeExercise(request: f.request.launchOnly(offlineQuestionOrdinals: [ordinal]), index: 0, assessmentDescriptor: nil)
        try f.store.saveItemReport(exercise: exercise, reason: "incorrect", note: "Synthetic quarantine between preview and acceptance")
        let after = try await f.store.reviewedStartingPreview(request: f.store.reviewedPracticeRequest(lab: f.activity.lab,
            activity: f.activity, field: .general, requestedItemCount: 3, timingCondition: .init(.untimed), targetDifficulty: f.activity.defaultDifficulty), catalogScope: f.scope)
        XCTAssertEqual(after.choices.first { $0.band == .b2 }?.availableUniqueCount, 5)
        XCTAssertEqual(after.choices.first { $0.band == .b1 }?.availableUniqueCount, 6)
        XCTAssertNil(f.store.localSessions.archive.offlineRotationLedger)
    }

    func testReleasedRegistryOffersNoReviewedBandAndPreservesLegacyCatalogLaunch() async throws {
        let (store, container) = try makeStore(); defer { _ = container }
        let activity = try XCTUnwrap(NFDefaultContentCatalog.activity(id: "nf.default.mental.compensation"))
        let request = store.reviewedPracticeRequest(lab: activity.lab, activity: activity, field: .general,
            requestedItemCount: 1, timingCondition: .init(.untimed), targetDifficulty: activity.defaultDifficulty)
        let scope = NFEditorialCatalogScope(catalogVersion: NFDefaultContentCatalog.version, activityID: activity.id, field: .general)
        let preview = try await store.reviewedStartingPreview(request: request, catalogScope: scope)
        XCTAssertEqual(preview.state, .registryUnavailable); XCTAssertTrue(preview.choices.isEmpty)
        XCTAssertFalse(store.beginDefaultCatalogSession(.init(activity: activity, field: .general), requestedItemCount: 1,
            editorialStartingBand: .b2, editorialStartingFamilyScope: .init(objectiveID: "forged", familyID: "forged")))
        XCTAssertNil(store.activeSessionRequest); XCTAssertNil(store.localSessions.archive.offlineRotationLedger)
        XCTAssertTrue(store.beginDefaultCatalogSession(.init(activity: activity, field: .general), requestedItemCount: 1,
            targetDifficulty: 0.62))
        XCTAssertEqual(store.activeSessionRequest?.mechanicID, activity.mechanicID)
        XCTAssertEqual(store.activeSessionRequest?.targetDifficulty, 0.62)
        XCTAssertNil(store.activeSessionRequest?.ordinaryDelivery?.editorialPolicy)
    }
    func testAutomaticCatalogStartKeepsColdAndRecentReasonsDistinctFromExplicitPreference() async throws {
        let f = try reviewedFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let cold = try await f.store.reviewedStartingPreview(request: f.request, catalogScope: f.scope)
        let automatic = try XCTUnwrap(cold.choices.first { $0.isAutomatic })
        XCTAssertEqual(automatic.band, .b1); XCTAssertNil(automatic.requestedBand)
        XCTAssertEqual(automatic.automaticReason, .coldStartDefault)
        let initial = try launchReviewed(f, band: nil, count: 1)
        let coldID = try XCTUnwrap(f.store.localSessions.archive.sessions.first?.checkpoint.ordinaryReservationDecisionID)
        XCTAssertEqual(f.store.localSessions.archive.adaptiveItemReceipts?[coldID]?.editorialDecision?.initialReason, .coldStartDefault)
        XCTAssertNil(initial.request.ordinaryDelivery?.editorialPolicy?.initialUserBand)
        try answerReviewed(initial, store: f.store); initial.next(store: f.store); initial.releaseWriter()
        XCTAssertEqual(initial.stage, .summary); f.store.activeSessionRequest = nil
        let explicit = try launchReviewed(f, band: .b2, count: 1)
        let explicitID = try XCTUnwrap(f.store.localSessions.archive.sessions.first { $0.id == explicit.request.id }?.checkpoint.ordinaryReservationDecisionID)
        XCTAssertEqual(f.store.localSessions.archive.adaptiveItemReceipts?[explicitID]?.editorialDecision?.initialReason, .userRequested)
        try answerReviewed(explicit, store: f.store); explicit.next(store: f.store); explicit.releaseWriter()
        XCTAssertEqual(explicit.stage, .summary); f.store.activeSessionRequest = nil
        let committed = try XCTUnwrap(f.store.attempts.first { $0.sessionID == explicit.request.id })
        XCTAssertTrue(committed.isCorrect)
        let capture = try XCTUnwrap(f.store.localSessions.editorialSnapshot(for: committed.id)?.editorialCapture)
        XCTAssertEqual(capture.profileID, f.store.profile?.id)
        XCTAssertEqual(capture.authorityAtCommit, "admitted")
        let observation = try XCTUnwrap(f.store.effectiveAttemptDTO(committed).editorialObservation)
        XCTAssertEqual(observation.item?.editorialBand, .b2)
        let evidence = EditorialBandEvidenceV1.reduce([observation], decisionDayOrdinal: capture.day.ordinal)
        XCTAssertEqual(evidence.independentObservationIDs, [committed.id.uuidString])
        let recent = try await f.store.reviewedStartingPreview(request: f.store.reviewedPracticeRequest(lab: f.activity.lab,
            activity: f.activity, field: .general, requestedItemCount: 3, timingCondition: .init(.untimed),
            targetDifficulty: f.activity.defaultDifficulty), catalogScope: f.scope)
        let suggested = try XCTUnwrap(recent.choices.first { $0.isAutomatic })
        XCTAssertEqual(suggested.band, .b2); XCTAssertEqual(suggested.automaticReason, .recentPracticeTarget)
        let continued = try launchReviewed(f, band: nil, count: 3); defer { continued.releaseWriter() }
        let nextID = try XCTUnwrap(f.store.localSessions.archive.sessions.first { $0.id == continued.request.id }?.checkpoint.ordinaryReservationDecisionID)
        let nextDecision = f.store.localSessions.archive.adaptiveItemReceipts?[nextID]?.editorialDecision
        XCTAssertEqual(nextDecision?.initialReason, .recentPracticeTarget)
        XCTAssertEqual(nextDecision?.selection.deliveredBand, .b2)
    }

    func testReviewedLaunchRechecksQuarantineAfterReadOnlyInventoryPreview() async throws {
        let f = try reviewedFixture(perBand: 3); defer { try? FileManager.default.removeItem(at: f.root) }
        let preview = try await f.store.reviewedStartingPreview(request: f.request, catalogScope: f.scope)
        XCTAssertTrue(try XCTUnwrap(preview.choices.first { $0.band == .b2 }).canStartRequestedCount)
        let entry = try XCTUnwrap(f.admissions.entries.first { $0.demand.editorialBand == .b2 && $0.id != "QA.catalog.outsider" })
        let ordinal = try XCTUnwrap(NFOfflineQuestionBank.ordinal(forQuestionID: entry.bankQuestionID, lab: f.activity.lab))
        let exercise = NFDeterministicSessionExerciseFactory.makeExercise(request: f.request.launchOnly(offlineQuestionOrdinals: [ordinal]), index: 0, assessmentDescriptor: nil)
        try f.store.saveItemReport(exercise: exercise, reason: "incorrect", note: "Quarantine after an advisory preview")
        XCTAssertFalse(f.store.beginDefaultCatalogSession(.init(activity: f.activity, field: .general), requestedItemCount: 3,
            timingCondition: .init(.untimed), editorialStartingBand: .b2, editorialStartingFamilyScope: f.family))
        XCTAssertNil(f.store.activeSessionRequest); XCTAssertNil(f.store.localSessions.archive.offlineRotationLedger)
        XCTAssertNil(f.store.localSessions.archive.adaptiveItemReceipts)
        let shorter = try launchReviewed(f, count: 2); defer { shorter.releaseWriter() }
        XCTAssertNotEqual(shorter.exercise.id, exercise.id)
        XCTAssertEqual(shorter.request.requestedItemCount, 2)
    }

    func testFutureCatalogScopePreservesCheckpointButRefusesWritableColdContinuation() throws {
        let f = try reviewedFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let runtime = try launchReviewed(f); runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: f.store)); runtime.releaseWriter()
        var archive = f.store.localSessions.archive
        let index = try XCTUnwrap(archive.sessions.firstIndex { $0.id == runtime.request.id })
        archive.sessions[index].request.ordinaryDelivery?.editorialPolicy?.catalogScope?.schemaVersion = 99
        let checkpoint = archive.sessions[index].checkpoint
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(archive)
        let url = f.root.appending(path: "sessions-v1.json")
        try bytes.write(to: url, options: .atomic)
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: f.store.localSessions.ownerDeviceID, editorialAdmissions: f.admissions)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.archive.sessions[index].status, .migrationRecovery)
        XCTAssertEqual(reopened.archive.sessions[index].checkpoint, checkpoint)
        XCTAssertEqual(try Data(contentsOf: url), bytes, "Unsupported accepted scope cannot be rewritten or regenerated on read")
    }

    func testTypedSpatialActivityPreviewAndNextUseValidatedRenamedContract() async throws {
        let f = try reviewedFixture(perBand: 2, activityID: "nf.default.spatial.object-rotation", bands: [.b1])
        defer { try? FileManager.default.removeItem(at: f.root) }
        XCTAssertEqual(f.request.spatialStructurePolicyVersion, 1)
        let preview = try await f.store.reviewedStartingPreview(request: f.request, catalogScope: f.scope)
        XCTAssertEqual(preview.choices.first?.availableUniqueCount, 2)
        let runtime = try launchReviewed(f, band: .b1, count: 2); defer { runtime.releaseWriter() }
        for _ in 0..<2 {
            let contract = try XCTUnwrap(NFSpatialStructureContract.make(exercise: runtime.exercise))
            XCTAssertEqual(contract.familyID, f.activity.id); XCTAssertTrue(f.scope.matches(runtime.exercise))
            XCTAssertNotEqual(runtime.exercise.templateID, runtime.exercise.templateFamily + "." + f.activity.templateSlug)
            let wrong = NFEditorialCatalogScope(catalogVersion: NFDefaultContentCatalog.version, activityID: "nf.default.spatial.top-view", field: .general)
            XCTAssertFalse(wrong.matches(runtime.exercise))
            var bad = runtime.exercise; bad.contractMetadata?.spatialStructure?.policyVersion = 999
            XCTAssertFalse(f.scope.matches(bad), "Unknown typed contract cannot fall back to a legacy slug")
            try answerReviewed(runtime, store: f.store); runtime.next(store: f.store)
            XCTAssertNil(runtime.saveError)
        }
        XCTAssertEqual(f.store.attempts.count, 2)
    }

    func testTypedRetrievalAssetPreviewAndNextRemainInEquationActivity() async throws {
        let f = try reviewedFixture(perBand: 2, activityID: "nf.default.retrieval.equation", bands: [.b1])
        defer { try? FileManager.default.removeItem(at: f.root) }
        XCTAssertEqual(f.request.retrievalAuthorityPolicyVersion, 1); XCTAssertEqual(f.request.retrievalAssetPolicyVersion, 1)
        let preview = try await f.store.reviewedStartingPreview(request: f.request, catalogScope: f.scope)
        XCTAssertEqual(preview.choices.first?.availableUniqueCount, 2)
        let runtime = try launchReviewed(f, band: .b1, count: 2); defer { runtime.releaseWriter() }
        for _ in 0..<2 {
            let asset = try XCTUnwrap(NFRetrievalAssetContract.make(exercise: runtime.exercise))
            XCTAssertEqual(asset.form, .equation); XCTAssertTrue(f.scope.matches(runtime.exercise))
            let other = NFEditorialCatalogScope(catalogVersion: NFDefaultContentCatalog.version, activityID: "nf.default.retrieval.figure", field: .general)
            XCTAssertFalse(other.matches(runtime.exercise))
            var bad = runtime.exercise; bad.contractMetadata?.retrievalAsset?.policyVersion = 999
            XCTAssertFalse(f.scope.matches(bad), "A supported-looking slug cannot bypass typed recipe validation")
            try answerReviewed(runtime, store: f.store); runtime.next(store: f.store)
            XCTAssertNil(runtime.saveError)
        }
        XCTAssertEqual(f.store.attempts.count, 2)
    }

    func testEnumeratedLegacySubvariantsKeepActivityScopeWithoutPrefixWidening() throws {
        let (store, container) = try makeStore(); defer { _ = container }
        for (activityID, expected) in [
            ("nf.default.spatial.cross-section", Set(["cross-section.cube", "cross-section.cylinder", "cross-section.sphere"])),
            ("nf.default.quantitative.scaling", Set(["scaling.direct", "scaling.inverse", "scaling.power-law"])),
            ("nf.default.mental.representation-relay", Set(["unit-conversion.metric"]))
        ] {
            let activity = try XCTUnwrap(NFDefaultContentCatalog.activity(id: activityID))
            let field: STEMField = activity.lab == .mentalMath ? .physics : .general
            let scope = NFEditorialCatalogScope(catalogVersion: NFDefaultContentCatalog.version, activityID: activityID, field: field)
            var request = store.reviewedPracticeRequest(lab: activity.lab, activity: activity, field: field,
                requestedItemCount: 1, timingCondition: .init(.untimed), targetDifficulty: activity.defaultDifficulty)
            // This regression verifies retained legacy subvariants. Fresh
            // cross-section launches opt into a separately tested recipe.
            request.solidSectionPolicyVersion = nil
            var seen: Set<String> = []
            for questionID in NFOfflineQuestionBank.rotationBank.questionIDs(for: activity.lab) {
                let ordinal = try XCTUnwrap(NFOfflineQuestionBank.ordinal(forQuestionID: questionID, lab: activity.lab))
                let exercise = NFDeterministicSessionExerciseFactory.makeExercise(request: request.launchOnly(offlineQuestionOrdinals: [ordinal]), index: 0, assessmentDescriptor: nil)
                guard let slug = expected.first(where: { exercise.templateID == exercise.templateFamily + "." + $0 }) else { continue }
                XCTAssertTrue(scope.matches(exercise)); seen.insert(slug)
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(exercise)) as? [String: Any])
                object["templateID"] = exercise.templateID + ".future-unsigned-subtype"
                let future = try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: object))
                XCTAssertFalse(scope.matches(future))
                if seen == expected { break }
            }
            XCTAssertEqual(seen, expected)
        }
    }

}

@MainActor
extension DefaultContentCatalogTests {
    func testReviewedSelectionKeepsExactBandAcrossCountChangesQuarantineAndRecovery() async throws {
        let f = try reviewedFixture(perBand: 4); defer { try? FileManager.default.removeItem(at: f.root) }
        let initial = try await f.store.reviewedStartingPreview(request: f.request, catalogScope: f.scope)
        let chosen = try XCTUnwrap(initial.choices.first { $0.band == .b2 && !$0.isAutomatic })
        var selection = NFEditorialPrelaunchSelection(); selection.choose(chosen)
        let larger = f.store.reviewedPracticeRequest(lab: f.activity.lab, activity: f.activity, field: .general,
            requestedItemCount: 5, timingCondition: .init(.untimed), targetDifficulty: f.activity.defaultDifficulty)
        let tooMany = try await f.store.reviewedStartingPreview(request: larger, catalogScope: f.scope)
        selection.refresh(tooMany, selectAutomatic: true)
        let stillSelected = try XCTUnwrap(selection.resolved(in: tooMany, requestedCount: 5))
        XCTAssertEqual(stillSelected.id, chosen.id); XCTAssertEqual(stillSelected.band, .b2)
        XCTAssertFalse(stillSelected.isAutomatic); XCTAssertFalse(stillSelected.canStartRequestedCount)
        XCTAssertTrue(stillSelected.canStart(count: 4)); XCTAssertFalse(stillSelected.canStart(count: 0))
        XCTAssertTrue(tooMany.canStartAutomaticMixed,
            "A family cannot promise five questions, but its first eligible mixed item is still available")
        for entry in f.admissions.entries where entry.demand.editorialBand == .b2 && entry.id != "QA.catalog.outsider" {
            let ordinal = try XCTUnwrap(NFOfflineQuestionBank.ordinal(forQuestionID: entry.bankQuestionID, lab: f.activity.lab))
            let exercise = NFDeterministicSessionExerciseFactory.makeExercise(
                request: f.request.launchOnly(offlineQuestionOrdinals: [ordinal]), index: 0, assessmentDescriptor: nil)
            try f.store.saveItemReport(exercise: exercise, reason: "incorrect", note: "Synthetic prelaunch availability fixture")
        }
        let request = f.store.reviewedPracticeRequest(lab: f.activity.lab, activity: f.activity, field: .general,
            requestedItemCount: 3, timingCondition: .init(.untimed), targetDifficulty: f.activity.defaultDifficulty)
        XCTAssertFalse(request.quarantinedItemIDs.isEmpty)
        let unchangedRequest = try NFEditorialCanonicalData.encode(request)
        let blocked = try await f.store.reviewedStartingPreview(request: request, catalogScope: f.scope)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(request), unchangedRequest)
        selection.refresh(blocked, selectAutomatic: true)
        let retained = try XCTUnwrap(selection.resolved(in: blocked, requestedCount: 3))
        XCTAssertEqual(retained.id, chosen.id); XCTAssertEqual(retained.availableUniqueCount, 0)
        XCTAssertEqual(retained.launchScope, chosen.launchScope, "Quarantine changes eligibility, not catalog identity")
        XCTAssertEqual(retained.unavailabilityReasons, [.quarantined]); XCTAssertTrue(retained.isReviewedInCurrentScope)
        XCTAssertFalse(retained.canStartRequestedCount); XCTAssertFalse(retained.canStart(count: 1))
        let bytes = try Data(contentsOf: f.root.appending(path: "sessions-v1.json"))
        XCTAssertFalse(f.store.beginDefaultCatalogSession(.init(activity: f.activity, field: .general), requestedItemCount: 3,
            timingCondition: .init(.untimed), editorialStartingBand: retained.requestedBand, editorialStartingFamilyScope: retained.scope))
        XCTAssertEqual(try Data(contentsOf: f.root.appending(path: "sessions-v1.json")), bytes)
        for report in f.store.itemReports { report.status = "resolved" }
        try f.store.context.save(); f.store.reload()
        let restoredRequest = f.store.reviewedPracticeRequest(lab: f.activity.lab, activity: f.activity, field: .general,
            requestedItemCount: 3, timingCondition: .init(.untimed), targetDifficulty: f.activity.defaultDifficulty)
        let restored = try await f.store.reviewedStartingPreview(request: restoredRequest, catalogScope: f.scope)
        selection.refresh(restored, selectAutomatic: true)
        let available = try XCTUnwrap(selection.resolved(in: restored, requestedCount: 3))
        XCTAssertEqual(available.id, chosen.id); XCTAssertTrue(available.canStartRequestedCount)
        XCTAssertTrue(available.unavailabilityReasons.isEmpty)
    }

    func testReviewedChoiceRetainsIdentityWhenRegistryScopeOrPreviewIsUnavailable() async throws {
        let f = try reviewedFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let initial = try await f.store.reviewedStartingPreview(request: f.request, catalogScope: f.scope)
        let chosen = try XCTUnwrap(initial.choices.first { $0.band == .b2 && !$0.isAutomatic })
        var selection = NFEditorialPrelaunchSelection(); selection.choose(chosen)
        let empty = NFEditorialPrelaunchPreview(state: .registryUnavailable, choices: [], catalogScope: f.scope, archiveRevision: initial.archiveRevision)
        selection.refresh(empty, selectAutomatic: true)
        let unavailable = try XCTUnwrap(selection.resolved(in: empty, requestedCount: 3))
        XCTAssertEqual(unavailable.id, chosen.id); XCTAssertEqual(unavailable.band, chosen.band)
        XCTAssertFalse(unavailable.isReviewedInCurrentScope); XCTAssertFalse(unavailable.availabilityKnown)
        XCTAssertEqual(unavailable.unavailabilityReasons, [.registryUnavailable]); XCTAssertFalse(unavailable.canStartRequestedCount)
        let failed = try XCTUnwrap(selection.resolved(in: nil, requestedCount: 3))
        XCTAssertEqual(failed.id, chosen.id); XCTAssertEqual(failed.unavailabilityReasons, [.notVerified])
        let changed = f.store.reviewedPracticeRequest(lab: f.activity.lab, activity: f.activity, field: .chemistry,
            requestedItemCount: 3, timingCondition: .init(.untimed), targetDifficulty: f.activity.defaultDifficulty)
        let otherScope = NFEditorialCatalogScope(catalogVersion: NFDefaultContentCatalog.version, activityID: f.activity.id, field: .chemistry)
        let other = try await f.store.reviewedStartingPreview(request: changed, catalogScope: otherScope)
        selection.refresh(other, selectAutomatic: true)
        XCTAssertEqual(selection.resolved(in: other, requestedCount: 3)?.unavailabilityReasons, [.scopeChanged])
        selection.refresh(initial, selectAutomatic: true)
        XCTAssertEqual(selection.resolved(in: initial, requestedCount: 3), chosen)
        selection.choose(nil); selection.refresh(initial, selectAutomatic: true)
        XCTAssertNil(selection.resolved(in: initial, requestedCount: 3), "Only an explicit alternative clears the selected reviewed identity")
    }

    func testPrelaunchDoesNotInventAutomaticFoundationOrUnsupportedHigherBands() async throws {
        let f = try reviewedFixture(bands: [.b2]); defer { try? FileManager.default.removeItem(at: f.root) }
        let preview = try await f.store.reviewedStartingPreview(request: f.request, catalogScope: f.scope)
        let automatic = try XCTUnwrap(preview.choices.first { $0.isAutomatic })
        XCTAssertEqual(automatic.band, .b1); XCTAssertEqual(automatic.automaticReason, .coldStartDefault)
        XCTAssertFalse(automatic.isReviewedInCurrentScope); XCTAssertFalse(automatic.canStartRequestedCount)
        XCTAssertEqual(automatic.minimumReasoningSteps, 0); XCTAssertEqual(automatic.maximumReasoningSteps, 0)
        XCTAssertEqual(automatic.unavailabilityReasons, [.bandNotReviewed])
        XCTAssertEqual(preview.unsupportedBands(in: f.family), [.b1, .b3, .b4])
        XCTAssertFalse(preview.choices.contains { $0.band == .b4 })
        var selection = NFEditorialPrelaunchSelection(); selection.refresh(preview, selectAutomatic: true)
        XCTAssertEqual(selection.resolved(in: preview, requestedCount: 3)?.id, automatic.id)
        let explicit = try XCTUnwrap(preview.choices.first { $0.band == .b2 && !$0.isAutomatic })
        selection.choose(explicit)
        XCTAssertTrue(selection.resolved(in: preview, requestedCount: 3)?.canStartRequestedCount == true)
        let runtime = try launchReviewed(f, band: explicit.requestedBand, count: 3); defer { runtime.releaseWriter() }
        XCTAssertEqual(runtime.request.ordinaryDelivery?.editorialPolicy?.initialUserBand, .b2)
    }

    func testCompletedReviewedInventoryStaysVisibleAsUnavailableAndDoesNotStartZeroQuestions() async throws {
        let f = try reviewedFixture(perBand: 2); defer { try? FileManager.default.removeItem(at: f.root) }
        let initial = try await f.store.reviewedStartingPreview(request: f.request, catalogScope: f.scope)
        let selected = try XCTUnwrap(initial.choices.first { $0.band == .b2 && !$0.isAutomatic })
        var choice = NFEditorialPrelaunchSelection(); choice.choose(selected)
        let runtime = try launchReviewed(f, count: 2)
        for _ in 0..<2 { try answerReviewed(runtime, store: f.store); runtime.next(store: f.store) }
        XCTAssertEqual(runtime.stage, .summary); runtime.releaseWriter(); f.store.activeSessionRequest = nil
        let request = f.store.reviewedPracticeRequest(lab: f.activity.lab, activity: f.activity, field: .general,
            requestedItemCount: 1, timingCondition: .init(.untimed), targetDifficulty: f.activity.defaultDifficulty)
        let after = try await f.store.reviewedStartingPreview(request: request, catalogScope: f.scope)
        choice.refresh(after, selectAutomatic: true)
        let unavailable = try XCTUnwrap(choice.resolved(in: after, requestedCount: 1))
        XCTAssertEqual(unavailable.id, selected.id); XCTAssertEqual(unavailable.availableUniqueCount, 0)
        XCTAssertTrue(unavailable.unavailabilityReasons.contains(.noUnusedQuestions))
        XCTAssertFalse(unavailable.canStart(count: 0)); XCTAssertFalse(unavailable.canStart(count: 1))
        let automatic = try XCTUnwrap(after.choices.first { $0.isAutomatic })
        XCTAssertEqual(automatic.band, .b2); XCTAssertEqual(automatic.automaticReason, .recentPracticeTarget)
        XCTAssertFalse(automatic.canStartRequestedCount, "An exhausted automatic target cannot silently become B1")
    }
}


@MainActor
extension DefaultContentCatalogTests {
    func testSameBandIDCannotReattachAcrossNonemptyReviewedActivityFieldOrLocale() async throws {
        let first = try reviewedFixture(); defer { try? FileManager.default.removeItem(at: first.root) }
        let second = try reviewedFixture(activityID: "nf.default.mental.rapid-recall")
        defer { try? FileManager.default.removeItem(at: second.root) }
        let oldPreview = try await first.store.reviewedStartingPreview(request: first.request, catalogScope: first.scope)
        let otherPreview = try await second.store.reviewedStartingPreview(request: second.request, catalogScope: second.scope)
        let old = try XCTUnwrap(oldPreview.choices.first { $0.band == .b2 && !$0.isAutomatic })
        let other = try XCTUnwrap(otherPreview.choices.first { $0.band == .b2 && !$0.isAutomatic })
        XCTAssertEqual(old.id, other.id, "Both actual catalogs deliberately reuse the objective/family/band identity")
        XCTAssertTrue(old.canStartRequestedCount); XCTAssertTrue(other.canStartRequestedCount)
        var selection = NFEditorialPrelaunchSelection(); selection.choose(old)
        selection.refresh(otherPreview, selectAutomatic: true)
        let unavailable = try XCTUnwrap(selection.resolved(in: otherPreview, requestedCount: 3))
        XCTAssertEqual(unavailable.launchScope, old.launchScope)
        XCTAssertFalse(unavailable.canStartRequestedCount); XCTAssertEqual(unavailable.unavailabilityReasons, [.scopeChanged])
        // Isolate each contextual component: even a populated same-ID preview
        // cannot silently reattach the previous preference to a new field/locale.
        for change in ["field", "locale"] {
            var altered = old
            if change == "field" { altered.launchScope.field = .chemistry }
            else { altered.launchScope.contentLocale = "ja" }
            let nonempty = NFEditorialPrelaunchPreview(state: .feasible, choices: [altered], catalogScope: first.scope, archiveRevision: oldPreview.archiveRevision)
            selection.refresh(nonempty, selectAutomatic: true)
            XCTAssertEqual(selection.resolved(in: nonempty, requestedCount: 3)?.unavailabilityReasons, [.scopeChanged], change)
            XCTAssertFalse(selection.resolved(in: nonempty, requestedCount: 3)?.canStartRequestedCount == true, change)
        }
        selection.choose(other)
        XCTAssertEqual(selection.resolved(in: otherPreview, requestedCount: 3), other,
            "An explicit new selection is the only route to the changed valid scope")
    }
}

@MainActor
extension DefaultContentCatalogTests {
    func testEveryCatalogActivityHasAnExplicitLocalizedPlaceholderExample() throws {
        XCTAssertEqual(Set(NFActivityTaskExamples.examples.keys), Set(NFDefaultContentCatalog.activities.map(\.id)))
        for activity in NFDefaultContentCatalog.activities {
            let key = try XCTUnwrap(NFActivityTaskExamples.exampleKey(activityID: activity.id))
            XCTAssertFalse(key.isEmpty); XCTAssertNotEqual(key, activity.summary)
            XCTAssertTrue(key.contains("→") || key.contains("□"), activity.id)
            let english = NFAppLocalization.localizedCatalogValue(key, locale: Locale(identifier: "en"))
            let japanese = NFAppLocalization.localizedCatalogValue(key, locale: Locale(identifier: "ja"))
            XCTAssertEqual(english, key); XCTAssertNotEqual(japanese, key, activity.id)
        }
        XCTAssertNil(NFActivityTaskExamples.exampleKey(activityID: "future.unknown.activity"))
    }

    func testActualReviewedTaskPreviewUsesDemandAndDurationWithoutConsumingOrCopyingAQuestion() async throws {
        let f = try reviewedFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let archive = try NFEditorialCanonicalData.encode(f.store.localSessions.archive)
        let before = try NFDataArchiveRawSnapshot.canonicalEncode(NFDataArchiveRawCapture.capture(context: f.container.mainContext))
        let result = try await f.store.reviewedStartingPreview(request: f.request, catalogScope: f.scope)
        let choice = try XCTUnwrap(result.choices.first { !$0.isAutomatic && $0.band == .b2 })
        let preview = try XCTUnwrap(choice.taskPreview)
        XCTAssertEqual(preview.activityID, f.activity.id)
        XCTAssertEqual(preview.relevantGivens, 2...2); XCTAssertEqual(preview.extraDetails, 0...0)
        XCTAssertEqual(preview.missingGivens, 0...0)
        XCTAssertEqual(preview.responseSeconds, NFExpectedDurationRange(minimumSeconds: 10, maximumSeconds: 40))
        XCTAssertEqual(preview.planningSeconds(questionCount: 3, timing: .untimed), 54...144)
        XCTAssertEqual(preview.planningSeconds(questionCount: 3, timing: .untimed),
            preview.planningSeconds(questionCount: 3, timing: .elapsedOnly))
        XCTAssertEqual(try NFEditorialCanonicalData.encode(f.store.localSessions.archive), archive)
        XCTAssertEqual(try NFDataArchiveRawSnapshot.canonicalEncode(NFDataArchiveRawCapture.capture(context: f.container.mainContext)), before)
        XCTAssertTrue(f.store.attempts.isEmpty)
        let shown = try XCTUnwrap(NFActivityTaskExamples.exampleKey(activityID: f.activity.id))
        for entry in f.admissions.entries {
            XCTAssertFalse(shown.contains(entry.exerciseDigest)); XCTAssertFalse(shown.contains(entry.demand.semanticFingerprint))
            let ordinal = try XCTUnwrap(NFOfflineQuestionBank.ordinal(forQuestionID: entry.bankQuestionID, lab: f.activity.lab))
            let exact = NFDeterministicSessionExerciseFactory.makeExercise(request: f.request.launchOnly(offlineQuestionOrdinals: [ordinal]), index: 0, assessmentDescriptor: nil)
            XCTAssertNotEqual(shown, exact.prompt)
        }
    }

    func testPreviewNeverCopiesDemandProseAndRefusesMissingOrUnsafeDuration() throws {
        let f = try reviewedFixture(perBand: 1); defer { try? FileManager.default.removeItem(at: f.root) }
        let original = try XCTUnwrap(f.admissions.entries.first?.demand)
        func changed(_ edits: (inout [String: Any]) -> Void) throws -> NFEditorialDemandRecord {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
            edits(&object)
            return try JSONDecoder().decode(NFEditorialDemandRecord.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let canary = "UNUSED_EVALUATOR_MUST_NOT_APPEAR_IN_PREVIEW"
        let prose = try changed { object in
            var demand = object["demandVector"] as! [String: Any]
            demand["quantityDomain"] = ["answer": canary]
            demand["misconceptionClasses"] = [canary]; demand["abstraction"] = canary
            object["demandVector"] = demand
        }
        let safe = try XCTUnwrap(NFEditorialTaskPreview.make(activityID: canary, records: [prose]))
        XCTAssertNil(safe.activityID); XCTAssertFalse(String(reflecting: safe).contains(canary))
        let missing = try changed { $0.removeValue(forKey: "expectedDurationRange") }
        XCTAssertNil(NFEditorialTaskPreview.make(activityID: f.activity.id, records: [original, missing])?.responseSeconds)
        let huge = try changed { $0["expectedDurationRange"] = ["minimumSeconds": 1e299, "maximumSeconds": 1e300] }
        XCTAssertNil(NFEditorialTaskPreview.make(activityID: f.activity.id, records: [huge])?.responseSeconds)
        let nearBoundary = NFEditorialTaskPreview(activityID: f.activity.id, relevantGivens: 2...2, extraDetails: 0...0,
            missingGivens: 0...0, responseSeconds: .init(minimumSeconds: NFSessionDurationPolicy.maximumSeconds,
                maximumSeconds: NFSessionDurationPolicy.maximumSeconds))
        XCTAssertNil(nearBoundary.planningSeconds(questionCount: 50, timing: .untimed))
        XCTAssertNil(safe.planningSeconds(questionCount: 0, timing: .untimed))
        XCTAssertNil(safe.planningSeconds(questionCount: 51, timing: .untimed))
    }

    func testUnreviewedCatalogExamplesDoNotBecomeDemandOrDurationAuthority() async throws {
        let (store, container) = try makeStore(); defer { _ = container }
        let activity = try XCTUnwrap(NFDefaultContentCatalog.activity(id: "nf.default.mental.compensation"))
        XCTAssertNotNil(NFActivityTaskExamples.exampleKey(activityID: activity.id))
        let request = store.reviewedPracticeRequest(lab: activity.lab, activity: activity, field: .general,
            requestedItemCount: 5, timingCondition: .init(.untimed), targetDifficulty: activity.defaultDifficulty)
        let result = try await store.reviewedStartingPreview(request: request,
            catalogScope: .init(catalogVersion: NFDefaultContentCatalog.version, activityID: activity.id, field: .general))
        XCTAssertEqual(result.state, .registryUnavailable); XCTAssertTrue(result.choices.isEmpty)
        XCTAssertFalse(result.hasReviewedChoices)
        XCTAssertTrue(store.attempts.isEmpty)
    }
}

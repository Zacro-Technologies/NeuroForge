import Foundation
import SwiftData
import XCTest

@testable import NeuroForge

final class AdaptiveEngineTests: XCTestCase {
    func testImprovementClaimRequiresSeparatedComparableWindowsAndAlternateTransferForms() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let early = (0..<6).map { index in
            AttemptDTO(
                id: UUID(),
                itemID: "early-item-\(index)",
                alternateFormID: "early-form-\(index)",
                skillID: TrainingLab.logicDebugging.skillID,
                lab: .logicDebugging,
                correct: false,
                credit: 0,
                confidence: .uncertain,
                submittedAt: base.addingTimeInterval(Double(index)),
                evidenceClass: .nearTransfer,
                evidenceWeight: 1
            )
        }
        let late = (0..<6).map { index in
            AttemptDTO(
                id: UUID(),
                itemID: "late-item-\(index)",
                alternateFormID: "late-form-\(index)",
                skillID: TrainingLab.logicDebugging.skillID,
                lab: .logicDebugging,
                correct: true,
                credit: 1,
                confidence: .fairlyConfident,
                submittedAt: base.addingTimeInterval(14 * 86_400 + Double(index)),
                evidenceClass: .nearTransfer,
                evidenceWeight: 1
            )
        }

        let claim = NFImprovementClaimEngine.claim(
            for: .logicDebugging,
            evidenceClass: .nearTransfer,
            attempts: early + late
        )
        XCTAssertEqual(claim?.code, .nearTransferImproved)
        XCTAssertEqual(claim?.evidence.earlierCount, 6)
        XCTAssertEqual(claim?.evidence.laterCount, 6)

        let repeatedForms = late.map {
            AttemptDTO(
                id: $0.id,
                itemID: $0.itemID,
                alternateFormID: "early-form-0",
                skillID: $0.skillID,
                lab: $0.lab,
                correct: $0.correct,
                credit: $0.credit,
                confidence: $0.confidence,
                submittedAt: $0.submittedAt,
                evidenceClass: $0.evidenceClass,
                evidenceWeight: $0.evidenceWeight
            )
        }
        XCTAssertNil(NFImprovementClaimEngine.claim(
            for: .logicDebugging,
            evidenceClass: .nearTransfer,
            attempts: early + repeatedForms
        ))
    }

    func testImprovementClaimRejectsSingleWindowPracticeOnlyAndConfoundedEvidence() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let practice = (0..<12).map { index in
            AttemptDTO(
                id: UUID(),
                itemID: "practice-\(index)",
                skillID: TrainingLab.mentalMath.skillID,
                lab: .mentalMath,
                correct: index >= 6,
                credit: index >= 6 ? 1 : 0,
                confidence: nil,
                submittedAt: base.addingTimeInterval(Double(index)),
                evidenceClass: .practice,
                evidenceWeight: 1
            )
        }
        XCTAssertNil(NFImprovementClaimEngine.claim(
            for: .mentalMath,
            evidenceClass: .nearTransfer,
            attempts: practice
        ))
        XCTAssertNil(NFImprovementClaimEngine.claim(
            for: .mentalMath,
            evidenceClass: .practice,
            attempts: practice
        ))

        var confounded: [AttemptDTO] = []
        for index in 0..<12 {
            let isLaterWindow = index >= 6
            let submittedAt = base.addingTimeInterval(
                (isLaterWindow ? 14 * 86_400 : 0) + Double(index)
            )
            confounded.append(AttemptDTO(
                id: UUID(),
                itemID: "transfer-\(index)",
                alternateFormID: "form-\(index)",
                skillID: TrainingLab.mentalMath.skillID,
                lab: .mentalMath,
                correct: isLaterWindow,
                credit: isLaterWindow ? 1 : 0,
                confidence: nil,
                submittedAt: submittedAt,
                evidenceClass: .appliedTransfer,
                evidenceWeight: 1,
                interruptionCount: index == 8 ? 1 : 0
            ))
        }
        XCTAssertNil(NFImprovementClaimEngine.claim(
            for: .mentalMath,
            evidenceClass: .appliedTransfer,
            attempts: confounded
        ))
    }

    func testDailyPlanIsDeterministicForIdenticalProfileAndDate() {
        let calendar = makeCalendar()
        let date = makeDate(in: calendar)
        let profile = makeProfile(dailyDuration: 10)

        let first = AdaptiveEngine.makeDailyPlan(
            profile: profile,
            date: date,
            readiness: .normal,
            calendar: calendar
        )
        let second = AdaptiveEngine.makeDailyPlan(
            profile: profile,
            date: date,
            readiness: .normal,
            calendar: calendar
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.localDayKey, second.localDayKey)
        XCTAssertEqual(first.seed, second.seed)
        XCTAssertEqual(first.policyVersion, second.policyVersion)
        XCTAssertEqual(first.minutes, second.minutes)
        XCTAssertEqual(first.blocks, second.blocks)
    }

    func testReadinessDoesNotChangePlanOrBlockIdentity() {
        let calendar = makeCalendar()
        let date = makeDate(in: calendar)
        let profile = makeProfile(dailyDuration: 20)
        let plans = Readiness.allCases.map { readiness in
            AdaptiveEngine.makeDailyPlan(
                profile: profile,
                date: date,
                readiness: readiness,
                calendar: calendar
            )
        }
        let canonical = plans[0]

        for plan in plans.dropFirst() {
            XCTAssertEqual(plan.id, canonical.id)
            XCTAssertEqual(plan.localDayKey, canonical.localDayKey)
            XCTAssertEqual(plan.seed, canonical.seed)
            XCTAssertEqual(plan.policyVersion, canonical.policyVersion)
            XCTAssertEqual(plan.blocks.map(\.id), canonical.blocks.map(\.id))
        }
    }

    func testPlansRespectSupportedDurationBudgets() {
        let calendar = makeCalendar()
        let date = makeDate(in: calendar)

        for budget in [5, 10, 15, 20] {
            let profile = makeProfile(dailyDuration: budget)
            let normalPlan = AdaptiveEngine.makeDailyPlan(
                profile: profile,
                date: date,
                readiness: .normal,
                calendar: calendar
            )

            XCTAssertEqual(normalPlan.minutes, budget)

            for readiness in Readiness.allCases {
                let plan = AdaptiveEngine.makeDailyPlan(
                    profile: profile,
                    date: date,
                    readiness: readiness,
                    calendar: calendar
                )

                XCTAssertEqual(plan.minutes, plan.blocks.reduce(0) { $0 + $1.minutes })
                XCTAssertLessThanOrEqual(plan.minutes, budget)
                XCTAssertTrue(plan.blocks.allSatisfy { $0.minutes > 0 })
                XCTAssertTrue(plan.blocks.allSatisfy(\.offlineReady))
                if readiness == .low {
                    XCTAssertLessThanOrEqual(plan.minutes, normalPlan.minutes)
                }
            }
        }
    }

    func testMentalMathGeneratorIsDeterministicAcrossSeedsAndIndices() {
        let seeds = (0..<64).map(UInt64.init) + [UInt64.max]
        let indices = [0, 1, 7]
        var itemIDs = Set<String>()
        var generatedKinds = Set<String>()

        for seed in seeds {
            for index in indices {
                let first = MentalMathGenerator.generate(
                    seed: seed,
                    index: index,
                    evidenceClass: .nearTransfer
                )
                let second = MentalMathGenerator.generate(
                    seed: seed,
                    index: index,
                    evidenceClass: .nearTransfer
                )

                assertItemsEqual(first, second)
                itemIDs.insert(first.id)
                generatedKinds.insert(first.kind.rawValue)
            }
        }

        XCTAssertEqual(itemIDs.count, seeds.count * indices.count)
        XCTAssertEqual(
            generatedKinds,
            Set(["multiplication", "percentage", "scientificNotation", "estimation"])
        )
    }

    func testMentalMathGeneratorHonorsShortcutSubskillPreference() {
        let kinds: [MentalMathKind] = [.multiplication, .percentage, .scientificNotation, .estimation]

        for kind in kinds {
            for index in 0..<8 {
                let item = MentalMathGenerator.generate(
                    seed: 42,
                    index: index,
                    preferredKind: kind
                )
                XCTAssertEqual(item.kind, kind)
            }
        }
    }

    func testScoringAcceptsExactNormalizedAnswersAndRejectsWrongAnswers() {
        let item = makeItem(kind: .multiplication, answer: 1_000, tolerance: 0)

        let correct = MentalMathGenerator.score(response: " 1,000 ", item: item)
        XCTAssertTrue(correct.isCorrect)
        XCTAssertEqual(correct.normalizedResponse, 1_000)
        XCTAssertNil(correct.errorCode)

        let incorrect = MentalMathGenerator.score(response: "999", item: item)
        XCTAssertFalse(incorrect.isCorrect)
        XCTAssertEqual(incorrect.normalizedResponse, 999)
        XCTAssertEqual(incorrect.errorCode, "operation_selection")
    }

    func testScoringIncludesToleranceBoundary() {
        let item = makeItem(kind: .estimation, answer: 100, tolerance: 12)

        let lowerBoundary = MentalMathGenerator.score(response: "88", item: item)
        let upperBoundary = MentalMathGenerator.score(response: "112", item: item)
        let outsideTolerance = MentalMathGenerator.score(response: "112.01", item: item)

        XCTAssertTrue(lowerBoundary.isCorrect)
        XCTAssertTrue(upperBoundary.isCorrect)
        XCTAssertFalse(outsideTolerance.isCorrect)
        XCTAssertEqual(outsideTolerance.errorCode, "operation_selection")
    }

    func testScoringReportsInputFailureForNonFiniteOrUnparseableResponses() {
        let item = makeItem(kind: .percentage, answer: 25, tolerance: 0.001)

        for response in ["", "not a number", "NaN", "infinity"] {
            let score = MentalMathGenerator.score(response: response, item: item)
            XCTAssertFalse(score.isCorrect, "Expected input failure for \(response)")
            XCTAssertNil(score.normalizedResponse)
            XCTAssertEqual(score.errorCode, "input_error")
        }
    }

    func testReducerUsesDocumentedEvidenceCountStatusThresholds() throws {
        let cases: [(count: Int, status: EstimateStatus)] = [
            (0, .unassessed),
            (1, .emergingEvidence),
            (5, .emergingEvidence),
            (6, .developing),
            (19, .developing),
            (20, .stable)
        ]

        for testCase in cases {
            let summaries = AdaptiveEngine.reduce(makeAttempts(count: testCase.count))
            XCTAssertEqual(summaries.count, TrainingLab.allCases.count)
            let summary = try XCTUnwrap(summaries.first { $0.lab == .mentalMath })

            XCTAssertEqual(summary.evidenceCount, testCase.count)
            XCTAssertEqual(summary.status.rawValue, testCase.status.rawValue)
            if testCase.count == 0 {
                XCTAssertNil(summary.accuracy)
                XCTAssertNil(summary.calibrationBias)
                XCTAssertNil(summary.lastTrained)
            }
        }
    }

    func testReducerCalculatesAccuracyAndCalibrationAndExcludesDocumentPractice() throws {
        let outcomes = [true, true, true, true, false, false]
        var attempts = outcomes.enumerated().map { index, correct in
            makeAttempt(
                index: index,
                correct: correct,
                confidence: .certain,
                evidenceClass: .practice
            )
        }
        attempts.append(
            makeAttempt(
                index: 99,
                correct: false,
                confidence: .certain,
                evidenceClass: .documentPractice
            )
        )

        let summary = try XCTUnwrap(
            AdaptiveEngine.reduce(attempts).first { $0.lab == .mentalMath }
        )
        let accuracy = try XCTUnwrap(summary.accuracy)
        let calibrationBias = try XCTUnwrap(summary.calibrationBias)
        let expectedBias = (6 * ConfidenceLevel.certain.probability - 4) / 6

        XCTAssertEqual(summary.evidenceCount, 6)
        XCTAssertEqual(summary.status, .developing)
        XCTAssertEqual(accuracy, 4.0 / 6.0, accuracy: 1e-12)
        XCTAssertEqual(calibrationBias, expectedBias, accuracy: 1e-12)
        XCTAssertEqual(summary.lastTrained, makeAttemptDate(index: 5))
    }

    func testReducerPreservesDeterministicPartialCredit() throws {
        let attempts = (0..<2).map { index in
            AttemptDTO(
                id: UUID(),
                skillID: TrainingLab.scientificReasoning.skillID,
                lab: .scientificReasoning,
                correct: false,
                credit: 0.5,
                confidence: .certain,
                submittedAt: makeAttemptDate(index: index),
                evidenceClass: .practice,
                evidenceWeight: 1
            )
        }

        let summary = try XCTUnwrap(
            AdaptiveEngine.reduce(attempts).first { $0.lab == .scientificReasoning }
        )

        XCTAssertEqual(try XCTUnwrap(summary.accuracy), 0.5, accuracy: 1e-12)
        XCTAssertEqual(summary.theta, 0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(summary.calibrationBias), ConfidenceLevel.certain.probability - 0.5, accuracy: 1e-12)
    }

    @MainActor
    func testAppStoreCentralizesStandardizedAndTodayEvidenceEligibility() throws {
        let (store, container) = try makeStore()
        defer { _ = container }

        try store.saveLabAttempt(
            lab: .retrieval,
            itemID: "document.test.opening",
            prompt: "Cited source recall",
            response: "Recall",
            correctAnswer: "",
            isCorrect: true,
            confidence: .certain,
            evidenceClass: .documentPractice,
            source: .today
        )
        try store.saveLabAttempt(
            lab: .transfer,
            itemID: "transfer.test",
            prompt: "Transfer prompt",
            response: "A",
            correctAnswer: "A",
            isCorrect: true,
            confidence: .fairlyConfident,
            evidenceClass: .appliedTransfer,
            source: .today
        )
        try store.saveLabAttempt(
            lab: .logicDebugging,
            itemID: "focused.test",
            prompt: "Focused prompt",
            response: "A",
            correctAnswer: "A",
            isCorrect: true,
            confidence: .fairlyConfident,
            evidenceClass: .practice,
            source: .focused
        )

        XCTAssertEqual(store.attempts.count, 3)
        XCTAssertEqual(store.standardizedAttempts.count, 2)
        XCTAssertEqual(store.todayAttemptCount, 1)
        XCTAssertEqual(store.attempts.first { $0.evidenceClassRaw == EvidenceClass.documentPractice.rawValue }?.evidenceWeight, 0)
        XCTAssertEqual(store.skillSummaries.first { $0.lab == .retrieval }?.evidenceCount, 0)
        XCTAssertEqual(store.skillSummaries.first { $0.lab == .transfer }?.evidenceCount, 1)
    }

    @MainActor
    func testDocumentDeletionRemovesManagedCopyAndAssociatedReviewHistory() async throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let sourceURL = FileManager.default.temporaryDirectory
            .appending(path: "neuroforge-delete-test-\(UUID().uuidString).txt")
        try "A test source".write(to: sourceURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        try await store.importDocumentAsync(from: sourceURL) { _ in }
        let document = try XCTUnwrap(store.documents.first)
        let managedPath = document.localPath
        try store.saveLabAttempt(
            lab: .retrieval,
            itemID: "document.\(document.id.uuidString).opening",
            prompt: "Recall [Citation: test, lines 1–1]",
            response: "A test source",
            correctAnswer: "",
            isCorrect: true,
            confidence: .certain,
            evidenceClass: .documentPractice
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: managedPath))
        try store.deleteDocument(document)

        XCTAssertFalse(FileManager.default.fileExists(atPath: managedPath))
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertTrue(store.attempts.isEmpty)
    }

    @MainActor
    func testActiveSessionIsNotReplacedAndDeleteAllCoversReports() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused))
        let activeID = try XCTUnwrap(store.activeSessionRequest?.id)
        XCTAssertFalse(store.beginSession(lab: .mentalMath, source: .focused))
        XCTAssertEqual(store.activeSessionRequest?.id, activeID)

        try store.saveItemReport(
            item: makeItem(kind: .multiplication, answer: 1_000, tolerance: 0),
            reason: "Prompt is ambiguous",
            note: "Local test report"
        )
        XCTAssertEqual(store.itemReports.count, 1)

        try store.deleteAllLocalData()
        XCTAssertTrue(store.itemReports.isEmpty)
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertNil(store.notice, "Store-only deletion must not announce whole-system cleanup success")
    }

    private func makeProfile(dailyDuration: Int) -> ProfileSnapshot {
        ProfileSnapshot(
            id: UUID(uuidString: "4B2C3A7B-930D-4B56-90A3-29E270095E6D")!,
            stage: .researcher,
            fields: [.mathematics, .dataScience],
            goals: [.mentalMath, .dataReasoning],
            dailyDuration: dailyDuration,
            timingMode: .adaptive,
            aiMode: .onDeviceOnly,
            iCloudEnabled: false
        )
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
            path: "NF-Adaptive-Engine-Documents-\(UUID().uuidString)",
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

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        return calendar
    }

    private func makeDate(in calendar: Calendar) -> Date {
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: 2026,
                month: 8,
                day: 5,
                hour: 12
            )
        )!
    }

    private func makeItem(
        kind: MentalMathKind,
        answer: Double,
        tolerance: Double
    ) -> MentalMathItem {
        MentalMathItem(
            id: "test.item",
            templateID: "test.template.v1",
            seed: 1,
            kind: kind,
            prompt: "Test prompt",
            context: "Test context",
            answer: answer,
            tolerance: tolerance,
            strategy: "Test strategy",
            decisiveStep: "Test decisive step",
            difficulty: 0.5,
            evidenceClass: .practice
        )
    }

    private func makeAttempts(count: Int) -> [AttemptDTO] {
        (0..<count).map { index in
            makeAttempt(
                index: index,
                correct: index.isMultiple(of: 2),
                confidence: nil,
                evidenceClass: .practice
            )
        }
    }

    private func makeAttempt(
        index: Int,
        correct: Bool,
        confidence: ConfidenceLevel?,
        evidenceClass: EvidenceClass
    ) -> AttemptDTO {
        let suffix = String(format: "%012d", index + 1)
        return AttemptDTO(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!,
            skillID: TrainingLab.mentalMath.skillID,
            lab: .mentalMath,
            correct: correct,
            confidence: confidence,
            submittedAt: makeAttemptDate(index: index),
            evidenceClass: evidenceClass,
            evidenceWeight: 1
        )
    }

    private func makeAttemptDate(index: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
    }

    private func assertItemsEqual(
        _ first: MentalMathItem,
        _ second: MentalMathItem,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(first.id, second.id, file: file, line: line)
        XCTAssertEqual(first.templateID, second.templateID, file: file, line: line)
        XCTAssertEqual(first.seed, second.seed, file: file, line: line)
        XCTAssertEqual(first.kind.rawValue, second.kind.rawValue, file: file, line: line)
        XCTAssertEqual(first.prompt, second.prompt, file: file, line: line)
        XCTAssertEqual(first.context, second.context, file: file, line: line)
        XCTAssertEqual(first.answer, second.answer, accuracy: 0, file: file, line: line)
        XCTAssertEqual(first.tolerance, second.tolerance, accuracy: 0, file: file, line: line)
        XCTAssertEqual(first.strategy, second.strategy, file: file, line: line)
        XCTAssertEqual(first.decisiveStep, second.decisiveStep, file: file, line: line)
        XCTAssertEqual(first.difficulty, second.difficulty, accuracy: 0, file: file, line: line)
        XCTAssertEqual(first.evidenceClass.rawValue, second.evidenceClass.rawValue, file: file, line: line)
    }
}

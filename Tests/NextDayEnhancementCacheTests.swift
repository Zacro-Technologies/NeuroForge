import SwiftData
import XCTest
@testable import NeuroForge

final class NextDayEnhancementCacheTests: XCTestCase {
    func testPresentationValidationAcceptsEveryDeterministicLabAndRejectsAnswerDisclosure() throws {
        let field = STEMField.engineering
        let exercises = try TrainingLab.allCases.enumerated().map { index, lab in
            try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
                seed: 9_000 + UInt64(index),
                index: index,
                lab: lab,
                purpose: .practice,
                sourceContext: NFExerciseSourceContext(primaryField: field)
            ))
        }
        let seeds = exercises.map { NFPresentationEnhancementSeed(exercise: $0, field: field) }
        let request = NFPresentationEnhancementGenerationRequest(
            compatibilityFingerprint: "all-labs",
            localeIdentifier: "en",
            aiMode: .onDeviceOnly,
            seeds: seeds
        )
        let generated = exercises.map {
            NFExercisePresentationEnhancement(
                deterministicExerciseID: $0.id,
                contextLabel: "Engineering systems lens",
                coachingHint: "Identify the invariant and choose a procedure before carrying it out.",
                transferLens: "The same reasoning pattern helps compare constraints in an engineering workflow.",
                generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                route: .onDevice,
                modelIdentifier: "test.on-device"
            )
        }
        XCTAssertEqual(
            try NFPresentationEnhancementValidator.validate(generated, for: request).count,
            TrainingLab.allCases.count
        )

        let numeric = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: 42,
            index: 0,
            lab: .mentalMath,
            purpose: .practice
        ))
        guard case let .numeric(schema) = numeric.interaction else {
            return XCTFail("Expected a numeric mental-math exercise")
        }
        let numericRequest = NFPresentationEnhancementGenerationRequest(
            compatibilityFingerprint: "leak",
            localeIdentifier: "en",
            aiMode: .onDeviceOnly,
            seeds: [NFPresentationEnhancementSeed(exercise: numeric, field: .mathematics)]
        )
        let leaked = NFExercisePresentationEnhancement(
            deterministicExerciseID: numeric.id,
            contextLabel: "Mathematics lens",
            coachingHint: "The final answer is \(schema.answer.authoritativeValue.canonicalString).",
            transferLens: "Use the same structure when checking a quantitative model.",
            generatedAt: Date(),
            route: .onDevice,
            modelIdentifier: "test.on-device"
        )
        XCTAssertThrowsError(try NFPresentationEnhancementValidator.validate([leaked], for: numericRequest)) {
            XCTAssertEqual(
                $0 as? NFNextDayEnhancementValidationError,
                .answerDisclosure(numeric.id)
            )
        }
    }

    @MainActor
    func testCompatibilityMismatchInvalidatesAndRemovesProtectedLocalCache() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = NFNextDayEnhancementCache(rootURL: root)
        let setup = makeCompatibility(localeIdentifier: "en")
        let payload = makePayload(compatibility: setup.compatibility, validFrom: setup.validFrom)
        try cache.persist(payload, validating: validationRequest(for: payload))

        let permissions = try FileManager.default.attributesOfItem(
            atPath: cache.cacheFileURL().path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual((permissions?.intValue ?? 0) & 0o777, 0o600)

        let changed = makeCompatibility(localeIdentifier: "ja").compatibility
        XCTAssertNil(cache.load(expected: changed, at: setup.validFrom.addingTimeInterval(60)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try cache.cacheFileURL().path))
    }

    @MainActor
    func testCacheRefusesUnvalidatedPresentationBeforeWriting() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = NFNextDayEnhancementCache(rootURL: root)
        let setup = makeCompatibility(localeIdentifier: "en")
        let valid = makePayload(compatibility: setup.compatibility, validFrom: setup.validFrom)
        let rejected = NFNextDayEnhancementPayload(
            compatibility: valid.compatibility,
            compatibilityFingerprint: valid.compatibilityFingerprint,
            validFrom: valid.validFrom,
            expiresAt: valid.expiresAt,
            enhancements: valid.enhancements.map {
                NFExercisePresentationEnhancement(
                    deterministicExerciseID: $0.deterministicExerciseID,
                    contextLabel: $0.contextLabel,
                    coachingHint: "The correct answer is already determined by this AI hint.",
                    transferLens: $0.transferLens,
                    generatedAt: $0.generatedAt,
                    route: .onDevice,
                    modelIdentifier: $0.modelIdentifier
                )
            }
        )

        XCTAssertThrowsError(try cache.persist(rejected, validating: validationRequest(for: rejected)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try cache.cacheFileURL().path))
    }

    @MainActor
    func testExpiryPurgesPayloadAndFuturePayloadCannotBeConsumedEarly() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = NFNextDayEnhancementCache(rootURL: root)
        let setup = makeCompatibility(localeIdentifier: "en")
        let payload = makePayload(compatibility: setup.compatibility, validFrom: setup.validFrom)
        try cache.persist(payload, validating: validationRequest(for: payload))

        XCTAssertNil(cache.load(expected: setup.compatibility, at: setup.validFrom.addingTimeInterval(-60)))
        XCTAssertNotNil(cache.preparedPayload(expected: setup.compatibility, at: setup.validFrom.addingTimeInterval(-60)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try cache.cacheFileURL().path))
        XCTAssertNil(cache.load(expected: setup.compatibility, at: payload.expiresAt.addingTimeInterval(1)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try cache.cacheFileURL().path))
    }

    @MainActor
    func testTodayLookupDoesNotEraseValidTomorrowPayload() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = NFNextDayEnhancementCache(rootURL: root)
        let tomorrow = makeCompatibility(localeIdentifier: "en", day: 6)
        let today = makeCompatibility(localeIdentifier: "en", day: 5)
        let payload = makePayload(
            compatibility: tomorrow.compatibility,
            validFrom: tomorrow.validFrom
        )
        try cache.persist(payload, validating: validationRequest(for: payload))

        XCTAssertNil(cache.load(
            expected: today.compatibility,
            at: date(year: 2026, month: 8, day: 5, hour: 15)
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try cache.cacheFileURL().path))
        XCTAssertNotNil(cache.preparedPayload(
            expected: tomorrow.compatibility,
            at: date(year: 2026, month: 8, day: 5, hour: 15)
        ))
    }

    @MainActor
    func testPreparationCreatesTomorrowPlanAndEnhancementsWithoutProgress() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = NFNextDayEnhancementCache(rootURL: root)
        let (store, container) = try makeStore(aiMode: .onDeviceOnly, cache: cache)
        defer { _ = container }
        let now = date(year: 2026, month: 8, day: 5, hour: 15)
        let generator = MockPresentationGenerator(generatedAt: now)
        let attemptCount = store.attempts.count
        let checkpointCount = store.sessionCheckpoints.count

        let receipt = try await NFNextDayPlanPreparationService.prepare(
            store: store,
            now: now,
            calendar: testCalendar(),
            generator: generator
        )

        XCTAssertEqual(receipt.outcome, .prepared)
        XCTAssertGreaterThan(receipt.deterministicExerciseCount, 0)
        XCTAssertEqual(receipt.enhancementCount, receipt.deterministicExerciseCount)
        XCTAssertEqual(store.attempts.count, attemptCount)
        XCTAssertEqual(store.sessionCheckpoints.count, checkpointCount)
        XCTAssertNil(store.activeSessionRequest)
        XCTAssertEqual(store.dailyPlans.filter { $0.id == receipt.planID }.count, 1)

        let nextDate = date(year: 2026, month: 8, day: 6, hour: 15)
        let consumed = store.compatiblePresentationEnhancements(
            forPlanID: receipt.planID,
            at: nextDate
        )
        XCTAssertEqual(consumed.count, receipt.enhancementCount)
        XCTAssertTrue(consumed.values.allSatisfy { $0.route == .onDevice })

        let canonical = try XCTUnwrap(store.dailyPlans.first(where: { $0.id == receipt.planID })?.snapshot)
        let plan = canonical.domainPlan
        let assignedFields = Set(store.presentationEnhancementSeeds(for: plan).map(\.field))
        XCTAssertEqual(assignedFields, store.profileSnapshot.fields)
        for block in plan.blocks {
            XCTAssertEqual(
                store.assignedField(forPlanID: plan.id, blockID: block.id),
                NFPlanFieldAssignment.field(forBlockID: block.id, in: plan, profile: store.profileSnapshot)
            )
        }

        let completedBlock = try XCTUnwrap(plan.blocks.first)
        let completionRequest = SessionRequest(
            lab: completedBlock.lab,
            source: .today,
            seed: plan.seed,
            requestedMinutes: completedBlock.minutes,
            evidenceClass: completedBlock.evidenceClass,
            field: store.assignedField(forPlanID: plan.id, blockID: completedBlock.id),
            planID: plan.id,
            planBlockID: completedBlock.id,
            mechanicID: completedBlock.mechanicID
        )
        try store.upsertCheckpoint(
            sessionID: UUID(),
            request: completionRequest,
            currentIndex: 1,
            itemCount: 1,
            response: "",
            scratchpad: "",
            results: [true],
            hasCommittedCurrentItem: true,
            isComplete: true
        )
        XCTAssertTrue(store.completedPlanBlockIDs(planID: plan.id).contains(completedBlock.id))
        let afterFirstBlock = store.compatiblePresentationEnhancements(
            forPlanID: plan.id,
            at: nextDate
        )
        XCTAssertEqual(afterFirstBlock.count, consumed.count)
    }

    @MainActor
    func testDisabledPolicyNeverConsultsGeneratorOrWritesPlanOrCache() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = NFNextDayEnhancementCache(rootURL: root)
        let (store, container) = try makeStore(aiMode: .disabled, cache: cache)
        defer { _ = container }
        let generator = MockPresentationGenerator(generatedAt: Date())

        let receipt = try await NFNextDayPlanPreparationService.prepare(
            store: store,
            now: date(year: 2026, month: 8, day: 5, hour: 15),
            calendar: testCalendar(),
            generator: generator
        )

        XCTAssertEqual(receipt.outcome, .policyForbidden)
        let counts = await generator.counts()
        XCTAssertEqual(counts.availability, 0)
        XCTAssertEqual(counts.generation, 0)
        XCTAssertTrue(store.dailyPlans.isEmpty)
        XCTAssertEqual(cache.payloadByteCount(), 0)
    }

    @MainActor
    func testBackgroundPrepareTaskRunsInjectedTomorrowPreparer() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, container) = try makeStore(
            aiMode: .onDeviceOnly,
            cache: NFNextDayEnhancementCache(rootURL: root)
        )
        defer { _ = container }
        let invocation = MainActorInvocation()
        let coordinator = NFSystemIntegrationCoordinator(nextDayPlanPreparer: { suppliedStore in
            invocation.count += 1
            return suppliedStore === store
        })

        let completed = await coordinator.performBackgroundTask(.prepareDailyPlan, store: store)
        XCTAssertTrue(completed)
        XCTAssertEqual(invocation.count, 1)
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertTrue(store.sessionCheckpoints.isEmpty)

        let disabledSnapshot = NFBackgroundWorkSnapshot(shouldPrepareNextPlan: false)
        XCTAssertFalse(NFBackgroundTaskPlanner.makeRequests(
            snapshot: disabledSnapshot,
            now: Date()
        ).contains { $0.kind == .prepareDailyPlan })
    }

    @MainActor
    private func makeStore(
        aiMode: AIMode,
        cache: NFNextDayEnhancementCache
    ) throws -> (AppStore, ModelContainer) {
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
        var draft = OnboardingDraft()
        draft.stage = .professional
        draft.fields = [.engineering, .mathematics]
        draft.goals = [.mentalMath, .dataReasoning]
        draft.aiMode = aiMode
        draft.preferredLanguageCode = "en"
        draft.claimsPolicyAcknowledgedVersion = NFClaimsPolicy.currentVersion
        draft.ageBandAcknowledged16Plus = true
        draft.keyboardLatencyMilliseconds = 80
        let profile = UserProfileRecord(draft: draft)
        container.mainContext.insert(profile)
        try container.mainContext.save()
        return (AppStore(context: container.mainContext, nextDayEnhancementCache: cache), container)
    }

    private func makeCompatibility(
        localeIdentifier: String,
        day: Int = 6
    ) -> (compatibility: NFNextDayEnhancementCompatibility, validFrom: Date) {
        let profile = ProfileSnapshot(
            id: UUID(uuidString: "CE4D8208-BE1D-45DD-8AB2-9AC5DFB5859B")!,
            stage: .professional,
            fields: [.engineering],
            goals: [.dataReasoning],
            dailyDuration: 10,
            timingMode: .adaptive,
            aiMode: .onDeviceOnly,
            iCloudEnabled: false,
            dayBoundaryHour: 4
        )
        let plan = AdaptiveEngine.makeDailyPlan(
            profile: profile,
            date: date(year: 2026, month: 8, day: day, hour: 15),
            readiness: .normal,
            calendar: testCalendar()
        )
        return (
            NFNextDayEnhancementCompatibility.make(
                profile: profile,
                plan: plan,
                readiness: .normal,
                localeIdentifier: localeIdentifier,
                quarantinedItemIDs: []
            ),
            date(year: 2026, month: 8, day: day, hour: 4)
        )
    }

    private func makePayload(
        compatibility: NFNextDayEnhancementCompatibility,
        validFrom: Date
    ) -> NFNextDayEnhancementPayload {
        NFNextDayEnhancementPayload(
            compatibility: compatibility,
            compatibilityFingerprint: compatibility.fingerprint,
            validFrom: validFrom,
            expiresAt: validFrom.addingTimeInterval(24 * 60 * 60),
            enhancements: [
                NFExercisePresentationEnhancement(
                    deterministicExerciseID: "deterministic.exercise.1",
                    contextLabel: "Engineering systems lens",
                    coachingHint: "Identify the changing quantity before choosing a general procedure.",
                    transferLens: "The same structure appears when comparing constraints in a system model.",
                    generatedAt: validFrom.addingTimeInterval(-60),
                    route: .onDevice,
                    modelIdentifier: "test.on-device"
                )
            ]
        )
    }

    private func validationRequest(
        for payload: NFNextDayEnhancementPayload
    ) -> NFPresentationEnhancementGenerationRequest {
        NFPresentationEnhancementGenerationRequest(
            compatibilityFingerprint: payload.compatibilityFingerprint,
            localeIdentifier: payload.compatibility.localeIdentifier,
            aiMode: AIMode(rawValue: payload.compatibility.aiModeRaw) ?? .disabled,
            seeds: payload.enhancements.map {
                NFPresentationEnhancementSeed(
                    deterministicExerciseID: $0.deterministicExerciseID,
                    lab: .logicDebugging,
                    field: .engineering,
                    title: "Deterministic validation exercise",
                    prompt: "Identify which invariant should be checked first.",
                    instructions: "Use the original deterministic response surface."
                )
            }
        )
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "NFNextDayEnhancementTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func testCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        testCalendar().date(from: DateComponents(
            calendar: testCalendar(),
            timeZone: testCalendar().timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}

private actor MockPresentationGenerator: NFPresentationEnhancementGenerating {
    let generatedAt: Date
    private(set) var availabilityCheckCount = 0
    private(set) var generationCount = 0

    init(generatedAt: Date) {
        self.generatedAt = generatedAt
    }

    func isAvailable(localeIdentifier: String) async -> Bool {
        _ = localeIdentifier
        availabilityCheckCount += 1
        return true
    }

    func generate(
        _ request: NFPresentationEnhancementGenerationRequest
    ) async throws -> [NFExercisePresentationEnhancement] {
        generationCount += 1
        return request.seeds.map {
            NFExercisePresentationEnhancement(
                deterministicExerciseID: $0.deterministicExerciseID,
                contextLabel: "\($0.field.title) reasoning lens",
                coachingHint: "Name the governing relationship, then choose a procedure without completing it yet.",
                transferLens: "This reasoning structure can be reused in a \($0.field.title.lowercased()) decision.",
                generatedAt: generatedAt,
                route: .onDevice,
                modelIdentifier: "test.on-device"
            )
        }
    }

    func counts() -> (availability: Int, generation: Int) {
        (availabilityCheckCount, generationCount)
    }
}

@MainActor
private final class MainActorInvocation {
    var count = 0
}

import CloudKit
import SwiftData
import SwiftUI

#if os(macOS)
import AppKit

enum NFNativeSessionExitDiagnostics {
    static func record(_ event: String) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing"),
              let id = NFUITestLaunchConfiguration.persistentRunID else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: "NeuroForge-UITests-\(id.uuidString)")
        let url = root.appending(path: "NativeExitEvents.log")
        let previous = (try? Data(contentsOf: url)) ?? Data()
        let retained = previous.suffix(16_384)
        var next = Data(retained)
        next.append(Data("\(event)\n".utf8))
        try? next.write(to: url, options: .atomic)
        #endif
    }
}

@MainActor
final class NFSessionTerminationDelegate: NSObject, NSApplicationDelegate {
    static func requestTermination() {
        NFSessionNativeCloseActions.shared.quit(windows: NFSessionWindowCloseRegistry.shared.registeredWindows) {
            NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        NFNativeSessionExitDiagnostics.record("quit.delegate")
        guard NFSessionCloseRegistry.shared.hasPresentations else { return .terminateNow }
        Self.requestTermination()
        return .terminateCancel
    }
}
#endif

#if DEBUG
enum NFUITestLaunchConfiguration {
    static let fixtureProfileID = UUID(uuidString: "78CC524D-21AD-4E09-B82C-F0D42A16F901")!
    static let shortTextFixtureSeed: UInt64 = 20260904
    static let isUnitTestHost = !ProcessInfo.processInfo.arguments.contains("-ui-testing")
        && (ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil)
    static let isEnabled = isUnitTestHost || ProcessInfo.processInfo.arguments.contains("-ui-testing")
    static let declinesExternalURLs = ProcessInfo.processInfo.arguments.contains(
        "-ui-test-decline-external-url"
    )
    static let startsWithVerifiedQuestionWriter = ProcessInfo.processInfo.arguments.contains(
        "-ui-test-verified-question-writer"
    )
    static var persistentRunID: UUID? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui-test-run-id"), arguments.indices.contains(index + 1) else { return nil }
        return UUID(uuidString: arguments[index + 1])
    }
    static var restoreFixtureSupportURL: URL? {
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing"),
              ProcessInfo.processInfo.arguments.contains("-ui-test-restore-fixture"), let id = persistentRunID else { return nil }
        return FileManager.default.temporaryDirectory.appending(path: "NeuroForge-UITests-\(id.uuidString)/RestoreApplicationSupport", directoryHint: .isDirectory)
    }
    static let resetsTestStore = ProcessInfo.processInfo.arguments.contains("-ui-test-reset-store")
    static let startsNumericSession = ProcessInfo.processInfo.arguments.contains("-ui-test-numeric-session")
    static let includesSourceDocument = ProcessInfo.processInfo.arguments.contains("-ui-test-source-document")
    enum CoordinateReasoningFixtureQuery: String {
        case inferAffine, orientationFixed
        var activityID: String {
            self == .inferAffine ? "nf.default.spatial.coordinate-rotation" : "nf.default.spatial.vector-reflection"
        }
        var query: NFCoordinateReasoningGeometry.Query {
            self == .inferAffine ? .inferAffine : .orientationFixed
        }
    }
    static var coordinateReasoningFixtureQuery: CoordinateReasoningFixtureQuery? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui-test-coordinate-reasoning-query") else { return nil }
        precondition(arguments.indices.contains(index + 1), "An explicit coordinate fixture query is required.")
        guard let query = CoordinateReasoningFixtureQuery(rawValue: arguments[index + 1]) else {
            preconditionFailure("Unsupported coordinate reasoning fixture query.")
        }
        precondition(persistentRunID != nil && resetsTestStore && focusedActivity?.id == query.activityID,
            "Coordinate query fixtures require a new isolated store and their exact ordinary catalog activity.")
        return query
    }

    /// Test-only task-kind selection. Reads the genuine fixed-plan proposal,
    /// then accepts that same ordinary launch; never supplies a response or key.
    @MainActor
    @inline(never)
    static func launchCoordinateReasoningFixture(_ query: CoordinateReasoningFixtureQuery,
                                                activity: NFDefaultContentActivity, store: AppStore, rotation: NFOfflineQuestionRotation) throws {
        precondition(isEnabled && persistentRunID != nil && resetsTestStore && activity.id == query.activityID)
        let commandID = UUID()
        let proposal = try store.localSessions.prepareFixedLaunch(commandID: commandID,
            rotation: rotation, profileID: store.profileSnapshot.id,
            lab: .spatial, laneID: activity.mechanicID, itemCount: 5, bank: NFOfflineQuestionBank.rotationBank)
        let originalRevision = store.localSessions.archive.transactionRevision
        var selected: (seed: UInt64, exercise: NFExercise)?
        for seed in UInt64(0)..<256 {
            let resolved = NFStableDeterminism.hash64("focused-launch|\(seed)|\(proposal.plan.id)|\(activity.mechanicID)")
            var request = SessionRequest(lab: .spatial, source: .focused, seed: resolved,
                localeIdentifier: "en_US", field: .general, requestedItemCount: 5, isTimed: false,
                timingCondition: .init(.untimed), mechanicID: activity.mechanicID)
            request.spatialStructurePolicyVersion = 1; request.coordinateTransformPolicyVersion = 1
            request.solidSectionPolicyVersion = 1; request.netFoldingPolicyVersion = 1
            request.coordinateReasoningPolicyVersion = 1
            let exercise = NFDeterministicSessionExerciseFactory.makeExercise(request: request, index: 0,
                assessmentDescriptor: nil)
            if NFCoordinateReasoningContract.make(exercise: exercise)?.task.query == query.query {
                selected = (seed, exercise); break
            }
        }
        precondition(store.localSessions.archive.transactionRevision == originalRevision,
            "Choosing a fixture task kind must not consume a question or mutate saved history.")
        guard let selected else { preconditionFailure("The bounded ordinary inventory must contain the requested fixture task kind.") }
        let accepted = store.beginSession(lab: .spatial, source: .focused, field: .general, requestedItemCount: 5,
            seedOverride: selected.seed, isTimed: false, timingCondition: .init(.untimed), mechanicID: activity.mechanicID,
            launchLocaleIdentifier: "en_US", launchCommandID: commandID, coordinateReasoningPolicyVersion: 1)
        precondition(accepted, "The actual ordinary launch boundary must accept the selected fixture task.")
        precondition(store.activeSessionRequest?.localCheckpoint?.exercise == selected.exercise,
            "The accepted immutable ordinary receipt must retain exactly the previewed task.")
        precondition(store.localSessions.archive.fixedLaunchReceipts?[commandID.uuidString] != nil,
            "A coordinate fixture cannot bypass the genuine fixed launch receipt.")
    }

    static var focusedActivity: NFDefaultContentActivity? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui-test-activity") else { return nil }
        let supported = Set([
            "nf.default.spatial.coordinate-rotation", "nf.default.spatial.vector-reflection", "nf.default.spatial.object-rotation", "nf.default.spatial.cross-section", "nf.default.spatial.cube-net", "nf.default.quantitative.proportion",
            "nf.default.science.confound", "nf.default.logic.conditions",
            "nf.default.retrieval.free-recall", "nf.default.retrieval.figure", "nf.default.transfer.conditions", "nf.default.transfer.rate",
            "nf.default.logic.proof-builder", "nf.default.retrieval.precision-recall",
            "nf.default.science.claim-evidence", "nf.default.logic.state-trace"
        ])
        precondition(arguments.indices.contains(index + 1), "A UI-test activity identifier is required.")
        let identifier = arguments[index + 1]
        precondition(supported.contains(identifier), "Unsupported UI-test activity identifier.")
        precondition(persistentRunID != nil && resetsTestStore, "Activity fixtures require a new isolated persistent UI-test store.")
        guard let activity = NFDefaultContentCatalog.activity(id: identifier),
              activity.defaultEvidenceClass == .practice else {
            preconditionFailure("The UI-test activity must resolve to ordinary catalog practice.")
        }
        precondition(!startsNumericSession, "Specify one UI-test session fixture.")
        return activity
    }
}
#endif

extension Notification.Name {
    static let neuroForgeTogglePause = Notification.Name("NeuroForge.TogglePause")
    static let neuroForgeAdvanceUniversalSession = Notification.Name("NeuroForge.AdvanceUniversalSession")
    static let neuroForgeShowScratchpad = Notification.Name("NeuroForge.ShowScratchpad")
}

/// NotificationCenter owns its opaque observer token. This small nonisolated
/// lifetime object unregisters it when the startup controller is released,
/// without accessing main-actor state from a nonisolated `deinit`.
private final class NFNotificationObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private let token: NSObjectProtocol

    init(
        center: NotificationCenter,
        name: Notification.Name,
        handler: @escaping @Sendable (Notification) -> Void
    ) {
        self.center = center
        token = center.addObserver(forName: name, object: nil, queue: .main, using: handler)
    }

    deinit {
        center.removeObserver(token)
    }
}

struct NFCompleteDeletionStartupBlock: Equatable, Sendable {
    let redactedCode: String
    let retryable: Bool
}

enum NFCompleteDeletionStartupGateResolution: Equatable, Sendable {
    case proceed
    case blocked(NFCompleteDeletionStartupBlock)
    case completed(NFPrivateCloudCompleteDeletionCompletion)

    var permitsModelContainerOpen: Bool {
        switch self {
        case .proceed, .completed: true
        case .blocked: false
        }
    }

    var completedPrivateCloudDeletion: Bool {
        if case .completed = self { return true }
        return false
    }
}

enum NFCompleteDeletionStartupGate {
    static func resolve(
        _ outcome: NFPrivateCloudDeletionStartupOutcome
    ) -> NFCompleteDeletionStartupGateResolution {
        switch outcome {
        case .noRequest:
            .proceed
        case let .completed(completion):
            .completed(completion)
        case let .unfinished(request):
            .blocked(NFCompleteDeletionStartupBlock(
                redactedCode: request.lastFailure?.redactedCode ?? "verification-incomplete",
                retryable: request.lastFailure?.retryable ?? true
            ))
        case .verified:
            .blocked(NFCompleteDeletionStartupBlock(
                redactedCode: "local-cleanup-incomplete",
                retryable: true
            ))
        case let .failed(redactedCode, retryable):
            .blocked(NFCompleteDeletionStartupBlock(
                redactedCode: redactedCode,
                retryable: retryable
            ))
        }
    }
}

@main
struct NeuroForgeApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(NFSessionTerminationDelegate.self) private var terminationDelegate
    #endif
    @State private var startup = NFAppStartupController()

    var body: some Scene {
        #if os(macOS)
        Window("NeuroForge", id: "main") {
            NFAppLaunchView(startup: startup)
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit NeuroForge") { NFSessionTerminationDelegate.requestTermination() }
                    .keyboardShortcut("q")
            }
            if let runtime = startup.runtime, startup.restoreCompletion == nil,
               startup.restoreRecoveryBlock == nil, runtime.restoreController?.requiresRestart != true,
               runtime.restoreController?.isStaging != true, runtime.restoreController?.isCleaningRestoreArtifacts != true {
                NeuroForgeCommands(
                    store: runtime.store,
                    sessionCommands: runtime.sessionCommands
                )
            }
        }
        #else
        WindowGroup {
            NFAppLaunchView(startup: startup)
        }
        .commands {
            if let runtime = startup.runtime, startup.restoreCompletion == nil,
               startup.restoreRecoveryBlock == nil, runtime.restoreController?.requiresRestart != true,
               runtime.restoreController?.isStaging != true, runtime.restoreController?.isCleaningRestoreArtifacts != true {
                NeuroForgeCommands(
                    store: runtime.store,
                    sessionCommands: runtime.sessionCommands
                )
            }
        }
        #endif
    }
}

@MainActor
final class NFAppRuntime {
    let modelContainer: ModelContainer
    let store: AppStore
    let systemIntegrations: NFSystemIntegrationCoordinator
    let startupTransition: NFPrivateCloudStartupTransition
    let sessionCommands = NFSessionCommandBridge()
    let restoreController: NFRestoreRuntimeController?

    init(
        modelContainer: ModelContainer,
        store: AppStore,
        systemIntegrations: NFSystemIntegrationCoordinator,
        startupTransition: NFPrivateCloudStartupTransition,
        restoreController: NFRestoreRuntimeController? = nil
    ) {
        self.modelContainer = modelContainer
        self.store = store
        self.systemIntegrations = systemIntegrations
        self.startupTransition = startupTransition
        self.restoreController = restoreController
    }
}

@MainActor
@Observable
final class NFAppStartupController {
    private(set) var runtime: NFAppRuntime?
    private(set) var localPurgeNeedsRetry = false
    private(set) var localPurgeCompletedAwaitingAcknowledgement = false
    private(set) var completedPurgeIncludedPrivateCloud = false
    private(set) var completeDeletionNeedsRetry: NFCompleteDeletionStartupBlock?
    private(set) var restoreRecoveryBlock: NFRestoreStartupBlock?
    private(set) var canCancelRestoreRequest = false
    private(set) var isRetryingRestoreCleanup = false
    private(set) var restoreCompletion: NFRestoreRequestReceipt?
    private(set) var isAcknowledgingRestoreCompletion = false
    private(set) var restoreAcknowledgementFailed = false
    private var restoreRecoverySelection: NFPrivateCloudStoreSelection?
    private(set) var storeAccessUnavailable = false
    private var applicationStoreLease: NFApplicationStoreLease?
    private var hasOpenedRuntime = false
    #if DEBUG
    private var restoreFixtureRootPrepared = false
    #endif
    private var completedCloudDeletionID: UUID?
    private var isStarting = false
    private var launchGeneration = 0
    private var accountChangeObservation: NFNotificationObservation?
    private var accountStopTask: Task<Void, Never>?
    private var accountRestartTask: Task<Void, Never>?
    private var lastIdentityProbeConfiguration: NFPrivateCloudRuntimeConfiguration?
    private var forcedIdentityProbeConfiguration: NFPrivateCloudRuntimeConfiguration?

    init(
        notificationCenter: NotificationCenter = .default,
        accountChangedNotificationName: Notification.Name = .CKAccountChanged
    ) {
        accountChangeObservation = NFNotificationObservation(
            center: notificationCenter,
            name: accountChangedNotificationName
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.accountIdentityDidChange()
            }
        }
    }

    func startIfNeeded() async {
        guard runtime == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        let generation = launchGeneration

        #if DEBUG
        if let fixture = NFUITestLaunchConfiguration.restoreFixtureSupportURL {
            await startRestoreUITestingRuntime(support: fixture)
            return
        }
        if NFUITestLaunchConfiguration.isEnabled {
            await startUITestingRuntime()
            return
        }
        #endif

        // Keep this lease across account transitions and recovery screens.
        // Only process termination can release every outstanding file worker.
        if applicationStoreLease == nil {
            do {
                applicationStoreLease = try NFApplicationStoreLease()
                storeAccessUnavailable = false
            } catch {
                storeAccessUnavailable = true
                return
            }
        }

        // A complete-cloud deletion is account-bound by the same installation
        // fingerprint, so it must run before a verified local purge is allowed
        // to clear that salt and registry. Both gates run before any SwiftData
        // or Core Data container can attach to a durable store.
        let completeDeletionOutcome = await NFPrivateCloudCompleteDeletionWorkflow
            .executePendingRequestBeforeModelContainer()
        guard generation == launchGeneration else {
            scheduleRestartAfterSupersededLaunch()
            return
        }
        switch NFCompleteDeletionStartupGate.resolve(completeDeletionOutcome) {
        case .proceed, .completed:
            completeDeletionNeedsRetry = nil
        case let .blocked(block):
            completeDeletionNeedsRetry = block
            return
        }
        let requiredPurgeRequestID: UUID? = switch completeDeletionOutcome {
        case let .completed(completion): completion.requestID
        case .noRequest: nil
        case .unfinished, .verified, .failed: nil
        }
        var pendingLocalPurgeResult: NFPrivateCloudPendingLocalPurgeResult
        switch completeDeletionOutcome {
        case .noRequest:
            pendingLocalPurgeResult = NFPrivateCloudStoreIdentityResolver
                .performPendingLocalPurgeBeforeOpeningContainer()
        case .completed:
            // The complete-deletion workflow already removed and verified all
            // local surfaces before returning this durable completion.
            pendingLocalPurgeResult = .completed
        case .unfinished, .verified, .failed:
            // Handled by the blocking switch above. This keeps exhaustiveness
            // explicit if the outcome model gains another transitional case.
            pendingLocalPurgeResult = .notRequested
        }
        if pendingLocalPurgeResult == .notRequested,
           NFPrivateCloudStoreIdentityResolver.hasVerifiedLocalPurgeReceipt(
               requestID: requiredPurgeRequestID
           ) {
            // Crash recovery: the store purge was already verified and its
            // durable receipt survived identity-registry removal.
            pendingLocalPurgeResult = .completed
        }
        switch pendingLocalPurgeResult {
        case .failed:
            localPurgeNeedsRetry = true
            return
        case .completed:
            localPurgeNeedsRetry = false
            localPurgeCompletedAwaitingAcknowledgement = true
            completedPurgeIncludedPrivateCloud = requiredPurgeRequestID != nil
            if case let .completed(completion) = completeDeletionOutcome {
                completedCloudDeletionID = completion.id
            }
        case .notRequested:
            localPurgeNeedsRetry = false
            localPurgeCompletedAwaitingAcknowledgement = false
            completedPurgeIncludedPrivateCloud = false
            completedCloudDeletionID = nil
        }

        // Shared local-derived and source surfaces must stay closed even when
        // an interrupted transaction belongs to another account. Inspect before
        // identity migration, ModelContainer attachment or AppStore.init writes.
        let restoreGate = await NFRestoreStartupGate.inspect()
        guard generation == launchGeneration else {
            scheduleRestartAfterSupersededLaunch()
            return
        }
        restoreRecoveryBlock = restoreGate.block
        if restoreGate.block?.reason == .unverified || restoreGate.block?.reason == .cleanupRequired { return }

        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let ordinaryRequestedConfiguration = completeDeletionOutcome.requiresLocalOnlyLaunch
            ? nil
            : NFPrivateCloudRuntimeConfiguration.current()
        if let ordinaryRequestedConfiguration {
            lastIdentityProbeConfiguration = ordinaryRequestedConfiguration
        }
        let forcedConfiguration = completeDeletionOutcome.requiresLocalOnlyLaunch
            ? nil
            : forcedIdentityProbeConfiguration
        let identityProbeConfiguration = forcedConfiguration ?? ordinaryRequestedConfiguration
        let accountProbe: NFPrivateCloudAccountProbeResult? = if let identityProbeConfiguration {
            await NFPrivateCloudAccountProbe.check(
                containerIdentifier: identityProbeConfiguration.containerIdentifier
            )
        } else {
            nil
        }
        guard generation == launchGeneration else {
            scheduleRestartAfterSupersededLaunch()
            return
        }
        let resolvedSelection = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: identityProbeConfiguration,
            accountProbe: accountProbe
        )
        forcedIdentityProbeConfiguration = nil
        // The carried configuration is authority to classify one account
        // transition, not authority to resume transport after its durable lock.
        // Resolver may attach only on an ordinary enabled launch; a forced
        // transition probe always opens the classified store locally.
        let selection = if forcedConfiguration != nil {
            NFPrivateCloudStoreSelection(
                durableStoreURL: resolvedSelection.durableStoreURL,
                privateCloudConfiguration: nil,
                transition: resolvedSelection.transition,
                claimedLegacyArtifacts: resolvedSelection.claimedLegacyArtifacts
            )
        } else {
            resolvedSelection
        }

        let restoredContainer: ModelContainer?
        do {
            guard let applicationStoreLease else { throw NFRestoreColdCoordinator.Failure.fullRestartRequired }
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            let owner = UserDefaults.standard.string(forKey: "NeuroForge.localSessionOwner.v1").flatMap(UUID.init(uuidString:))
            let recovery = try await NFRestoreColdCoordinator.recover(selection: selection, applicationSupportURL: support,
                lease: applicationStoreLease, installationOwnerID: owner, hasOpenedRuntime: hasOpenedRuntime,
                isCurrentLaunch: { generation == self.launchGeneration })
            guard generation == launchGeneration else { throw NFRestoreColdCoordinator.Failure.fullRestartRequired }
            restoredContainer = recovery.container
            restoreCompletion = recovery.completion
            canCancelRestoreRequest = false
            restoreRecoveryBlock = nil
        } catch {
            guard generation == launchGeneration else { scheduleRestartAfterSupersededLaunch(); return }
            restoreRecoverySelection = selection
            let reason: NFRestoreStartupBlock.Reason = switch error {
            case NFRestoreColdCoordinator.Failure.renewedReviewRequired: .reviewChanged
            case NFRestoreColdCoordinator.Failure.fullRestartRequired: .restartRequired
            case NFRestoreColdCoordinator.Failure.ownershipUnavailable: .wrongAccount
            default: .unfinished
            }
            restoreRecoveryBlock = .init(reason: reason)
            if !hasOpenedRuntime, let applicationStoreLease,
               let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                   appropriateFor: nil, create: false) {
                let owner = UserDefaults.standard.string(forKey: "NeuroForge.localSessionOwner.v1").flatMap(UUID.init(uuidString:))
                let pending = try? await NFRestoreColdCoordinator.pendingUnacceptedRequest(selection: selection,
                    applicationSupportURL: support, lease: applicationStoreLease, installationOwnerID: owner)
                canCancelRestoreRequest = pending != nil && generation == launchGeneration
            } else { canCancelRestoreRequest = false }
            return
        }

        let container: ModelContainer
        let launchPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration?
        let usedLocalCloudFallback: Bool
        var recoveryPackage: NFStoreRecoveryPackage?

        do {
            if let restoredContainer {
                container = restoredContainer
                launchPrivateCloudConfiguration = nil
                usedLocalCloudFallback = selection.privateCloudConfiguration != nil
            } else {
            let result = try NFCloudStoreBootstrap.open(
                requestedPrivateCloudConfiguration: selection.privateCloudConfiguration
            ) { privateCloudConfiguration in
                try ModelContainer(
                    for: schema,
                    migrationPlan: NFSchemaMigrationPlan.self,
                    configurations: try NFPersistentStoreLocation.configurations(
                        durableStoreURL: selection.durableStoreURL,
                        privateCloudConfiguration: privateCloudConfiguration
                    )
                )
            }
            container = result.store
            launchPrivateCloudConfiguration = result.activePrivateCloudConfiguration
            usedLocalCloudFallback = result.usedLocalFallback
                || (identityProbeConfiguration != nil && selection.privateCloudConfiguration == nil)
            }
        } catch {
            recoveryPackage = NFStoreRecoveryService.preparePackage(
                storeURL: selection.durableStoreURL,
                openingError: error
            )
            do {
                container = try ModelContainer(
                    for: schema,
                    migrationPlan: NFSchemaMigrationPlan.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } catch {
                preconditionFailure("Unable to initialize the protected recovery interface.")
            }
            launchPrivateCloudConfiguration = nil
            usedLocalCloudFallback = false
        }

        // Cold restore and account classification above must finish before a
        // local learning repository or AppStore can publish a writable cache.
        let localRepository: NFLocalSessionRepository
        if recoveryPackage == nil {
            do {
                localRepository = try await NFLocalSessionRepository.loadForDurableStore(at: selection.durableStoreURL,
                    isCurrentLaunch: { generation == self.launchGeneration })
                guard generation == launchGeneration else { scheduleRestartAfterSupersededLaunch(); return }
                storeAccessUnavailable = false
            } catch is CancellationError {
                if generation != launchGeneration { scheduleRestartAfterSupersededLaunch() }
                return
            } catch {
                guard generation == launchGeneration else { scheduleRestartAfterSupersededLaunch(); return }
                storeAccessUnavailable = true
                return
            }
        } else { localRepository = NFLocalSessionRepository() }
        let appStore = AppStore(context: container.mainContext, localSessionRepository: localRepository)
        if let recoveryPackage { appStore.enterPersistenceRecoveryMode(recoveryPackage) }
        let integrations = NFSystemIntegrationCoordinator(
            launchPrivateCloudConfiguration: launchPrivateCloudConfiguration,
            launchStructuredCloudFallbackUsed: usedLocalCloudFallback,
            launchDurableStoreURL: selection.durableStoreURL,
            launchPendingLocalPurgeResult: pendingLocalPurgeResult
        )
        if recoveryPackage == nil,
           (try? NFReleaseContentGate.requireVerified()) != nil {
            integrations.registerBackgroundTasks(store: appStore)
        }
        let restoreController: NFRestoreRuntimeController?
        if recoveryPackage == nil, let applicationStoreLease,
           let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
               appropriateFor: nil, create: true) {
            restoreController = try? NFRestoreRuntimeController(applicationSupportURL: support,
                durableStoreURL: selection.durableStoreURL, owner: appStore.localSessions.ownerDeviceID, lease: applicationStoreLease)
        } else { restoreController = nil }
        // Bind even nil: durable deletion remains fail-closed if cleanup setup
        // failed. A missing runtime controller is never deletion authorization.
        appStore.bindRestoreArtifactDeletionController(restoreController)
        integrations.willDeletePrivateData = { [weak restoreController] in await restoreController?.seal() }
        let preparedRuntime = NFAppRuntime(
            modelContainer: container,
            store: appStore,
            systemIntegrations: integrations,
            startupTransition: selection.transition,
            restoreController: restoreController
        )
        guard generation == launchGeneration else {
            await preparedRuntime.systemIntegrations.stopForAccountIdentityChange()
            scheduleRestartAfterSupersededLaunch()
            return
        }
        hasOpenedRuntime = true
        runtime = preparedRuntime
    }

    #if DEBUG
    /// Gives XCUITest a disposable launch boundary without opening a learner's
    /// database or consulting CloudKit. Release builds do not compile this path.
    private func startUITestingRuntime() async {
        let generation = launchGeneration
        let runID = NFUITestLaunchConfiguration.persistentRunID
        let testRoot = FileManager.default.temporaryDirectory
            .appending(path: "NeuroForge-UITests-\((runID ?? UUID()).uuidString)", directoryHint: .isDirectory)
        if NFUITestLaunchConfiguration.resetsTestStore { try? FileManager.default.removeItem(at: testRoot) }
        try? FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: NFSchemaMigrationPlan.self,
                configurations: runID == nil
                    ? ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                    : ModelConfiguration(url: testRoot.appending(path: "Fixture.store"), cloudKitDatabase: .none)
            )
        } catch {
            preconditionFailure("Unable to initialize the UI-testing store: \(error)")
        }

        guard let suiteName = NFAppPreferenceScope.testSuiteName else {
            preconditionFailure("UI fixtures require isolated test preferences.")
        }
        let defaults = NFAppPreferenceScope.defaults
        if runID == nil || NFUITestLaunchConfiguration.resetsTestStore {
            defaults.removePersistentDomain(forName: suiteName)
            if !NFUITestLaunchConfiguration.isUnitTestHost {
                defaults.removeObject(forKey: "nf.onboarding.step")
                defaults.removeObject(forKey: "nf.onboarding.draft")
                NFShortcutAuthoringConfiguration.clearSetupVerification(defaults: defaults)
                NFShortcutAuthoringConfiguration.clearInstallPageVisit(defaults: defaults)
                if NFUITestLaunchConfiguration.startsWithVerifiedQuestionWriter {
                    NFShortcutAuthoringConfiguration.markSetupVerified(defaults: defaults)
                }
            }
        }
        let fixtureRepository: NFLocalSessionRepository
        if let runID {
            do {
                let url = testRoot.appending(path: "Sessions.json")
                let prepared = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: runID)
                fixtureRepository = try NFLocalSessionRepository.adoptPreparedStartup(prepared, at: url,
                    ownerDeviceID: runID, isCurrentLaunch: { generation == self.launchGeneration })
            } catch is CancellationError { return }
            catch { storeAccessUnavailable = true; return }
        } else { fixtureRepository = NFLocalSessionRepository() }
        let appStore = AppStore(
            context: container.mainContext,
            nextDayEnhancementCache: NFNextDayEnhancementCache(rootURL: testRoot.appending(path: "PresentationCache", directoryHint: .isDirectory)),
            documentStorageRootURL: testRoot.appending(path: "Documents", directoryHint: .isDirectory),
            localSessionRepository: fixtureRepository,
            adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(
                fileURL: testRoot.appending(path: "AdaptivePlanHistory.json", directoryHint: .notDirectory)
            ),
            offlineQuestionRotation: NFOfflineQuestionRotation(
                store: NFUserDefaultsOfflineQuestionRotationStateStore(defaults: defaults)
            ),
            temporaryArtifactsRootURL: testRoot.appending(path: "Exports", directoryHint: .isDirectory),
            restoreArtifactDeletionPolicy: .isolatedNoRestoreArtifacts,
            allowsSharedWidgetPublishing: false
        )
        if NFUITestLaunchConfiguration.includesSourceDocument,
           !appStore.documents.contains(where: { $0.filename == "UI Study Source.txt" }) {
            let contents = Data("A triangle has three sides. This synthetic source is used only for navigation testing.".utf8)
            let folder = testRoot.appending(path: "Documents", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: "UI Study Source.txt")
            try? contents.write(to: url, options: .atomic)
            let document = SourceDocumentRecord(filename: "UI Study Source.txt", typeIdentifier: "public.plain-text",
                sizeBytes: Int64(contents.count), localPath: url.path)
            document.indexState = "ready"
            document.characterCount = contents.count
            container.mainContext.insert(document)
            if let extraction = try? NFSourceExtractor.extract(documentID: document.id, sourceName: document.filename, url: url) {
                for chunk in extraction.chunks { container.mainContext.insert(SourceChunkRecord(chunk: chunk)) }
                document.chunkCount = extraction.chunks.count
                document.extractionVersion = NFSourceExtractor.extractorVersion
            }
            try? container.mainContext.save()
            appStore.reload()
        }
        let focusedActivity = NFUITestLaunchConfiguration.focusedActivity
        if NFUITestLaunchConfiguration.startsNumericSession || focusedActivity != nil {
            if appStore.profile == nil {
                var draft = OnboardingDraft()
                draft.claimsPolicyAcknowledgedVersion = NFClaimsPolicy.currentVersion
                draft.ageBandAcknowledged16Plus = true
                let profile = UserProfileRecord(draft: draft)
                profile.id = NFUITestLaunchConfiguration.fixtureProfileID
                profile.onboardingVersion = 2
                container.mainContext.insert(profile)
                try? container.mainContext.save()
                appStore.reload()
            }
            let activity = focusedActivity ?? NFDefaultContentCatalog.activity(id: "nf.default.mental.rapid-recall")
            precondition(activity != nil, "The UI-test activity must exist in the current catalog.")
            let fixtureSeed = activity!.id == "nf.default.retrieval.precision-recall"
                ? NFUITestLaunchConfiguration.shortTextFixtureSeed : 20260904
            if let query = NFUITestLaunchConfiguration.coordinateReasoningFixtureQuery {
                do {
                    try NFUITestLaunchConfiguration.launchCoordinateReasoningFixture(query, activity: activity!, store: appStore,
                        rotation: NFOfflineQuestionRotation(store: NFUserDefaultsOfflineQuestionRotationStateStore(defaults: defaults)))
                } catch { preconditionFailure("The isolated coordinate fixture could not prepare its ordinary launch: \(error)") }
            } else {
                let accepted = appStore.beginSession(lab: activity!.lab, source: .focused, requestedItemCount: 5,
                    seedOverride: fixtureSeed, isTimed: false,
                    mechanicID: activity!.mechanicID)
                precondition(accepted, "The isolated UI-test session must be accepted by the ordinary launch boundary.")
            }
        }
        let integrations = NFSystemIntegrationCoordinator(defaults: defaults)
        runtime = NFAppRuntime(
            modelContainer: container,
            store: appStore,
            systemIntegrations: integrations,
            startupTransition: .none
        )
    }
    #endif

    #if DEBUG
    /// Exercises the production restore coordinator and UI against two private
    /// SQLite stores. The selected backup is synthetic; no account or learner
    /// application-support directory is consulted by this fixture.
    private func startRestoreUITestingRuntime(support: URL) async {
        guard let runID = NFUITestLaunchConfiguration.persistentRunID else { preconditionFailure("Restore fixture needs a UUID") }
        let generation = launchGeneration
        do {
            if !restoreFixtureRootPrepared {
                if NFUITestLaunchConfiguration.resetsTestStore {
                    try? FileManager.default.removeItem(at: support)
                    if let suite = NFAppPreferenceScope.testSuiteName {
                        NFAppPreferenceScope.defaults.removePersistentDomain(forName: suite)
                    }
                }
                try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
                restoreFixtureRootPrepared = true
            }
            if applicationStoreLease == nil { applicationStoreLease = try NFApplicationStoreLease(applicationSupportURL: support) }
            guard let applicationStoreLease else { throw NFApplicationStoreLease.Failure.unavailable }
            let gate = await NFRestoreStartupGate.inspect(applicationSupportURL: support)
            if gate.block?.reason == .unverified || gate.block?.reason == .cleanupRequired {
                restoreRecoveryBlock = gate.block
                return
            }
            let defaults = NFAppPreferenceScope.defaults
            if defaults.string(forKey: "NeuroForge.localSessionOwner.v1") == nil {
                defaults.set(runID.uuidString, forKey: "NeuroForge.localSessionOwner.v1")
            }
            let selection = NFPrivateCloudStoreSelection(durableStoreURL: support.appending(path: "Durable.store"),
                privateCloudConfiguration: nil, transition: .none, claimedLegacyArtifacts: false)
            restoreRecoverySelection = selection
            let makeContainer: () throws -> ModelContainer = {
                try ModelContainer(for: Schema(versionedSchema: NFSchemaV1.self), migrationPlan: NFSchemaMigrationPlan.self,
                    configurations: [
                        ModelConfiguration("RestoreFixtureDurable", schema: Schema(NFPersistentStoreLocation.durableModels),
                            url: selection.durableStoreURL, cloudKitDatabase: .none),
                        ModelConfiguration("RestoreFixtureLocal", schema: Schema(NFPersistentStoreLocation.localOnlyModels),
                            url: support.appending(path: "Local.store"), cloudKitDatabase: .none)
                    ])
            }
            let outcome: NFRestoreColdCoordinator.Outcome
            do {
                outcome = try await NFRestoreColdCoordinator.recover(selection: selection, applicationSupportURL: support,
                    lease: applicationStoreLease, installationOwnerID: runID, hasOpenedRuntime: hasOpenedRuntime,
                    isCurrentLaunch: { generation == self.launchGeneration }, makeContainer: makeContainer)
            } catch {
                let reason: NFRestoreStartupBlock.Reason = switch error {
                case NFRestoreColdCoordinator.Failure.renewedReviewRequired: .reviewChanged
                case NFRestoreColdCoordinator.Failure.fullRestartRequired: .restartRequired
                case NFRestoreColdCoordinator.Failure.ownershipUnavailable: .wrongAccount
                default: .unfinished
                }
                restoreRecoveryBlock = .init(reason: reason)
                let pending = try? await NFRestoreColdCoordinator.pendingUnacceptedRequest(selection: selection,
                    applicationSupportURL: support, lease: applicationStoreLease, installationOwnerID: runID)
                canCancelRestoreRequest = pending != nil
                return
            }
            let container = try outcome.container ?? makeContainer()
            let roots = try NFRestoreColdCoordinator.prepareSideFileRoots(applicationSupportURL: support,
                namespace: NFRestoreColdCoordinator.namespace(for: selection.durableStoreURL))
            let localURL = roots[.localLearning]!.appending(path: "sessions-v1.json")
            let prepared = try await NFLocalSessionRepository.prepareStartup(at: localURL, ownerDeviceID: runID)
            guard generation == launchGeneration else { prepared.discard(); return }
            let localRepository = try NFLocalSessionRepository.adoptPreparedStartup(prepared, at: localURL, ownerDeviceID: runID,
                isCurrentLaunch: { generation == self.launchGeneration })
            let store = AppStore(context: container.mainContext,
                nextDayEnhancementCache: NFNextDayEnhancementCache(rootURL: support.appending(path: "PresentationCache")),
                documentStorageRootURL: support.appending(path: "Documents"),
                localSessionRepository: localRepository,
                adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(fileURL: roots[.adaptiveHistory]!.appending(path: "AdaptivePlanHistory-v1.json")),
                offlineQuestionRotation: NFOfflineQuestionRotation(store: NFUserDefaultsOfflineQuestionRotationStateStore(defaults: defaults)),
                temporaryArtifactsRootURL: support.appending(path: "Exports"), restoreArtifactDeletionPolicy: .required,
                allowsSharedWidgetPublishing: false)
            if store.profile == nil {
                var draft = OnboardingDraft(); draft.aiMode = .disabled
                draft.claimsPolicyAcknowledgedVersion = NFClaimsPolicy.currentVersion; draft.ageBandAcknowledged16Plus = true
                let profile = UserProfileRecord(draft: draft); profile.id = runID; profile.onboardingVersion = 2
                container.mainContext.insert(profile); try container.mainContext.save(); store.reload()
            }
            let fixtureURL = support.appending(path: "SyntheticRestoreBackup.json")
            if !FileManager.default.fileExists(atPath: fixtureURL.path) {
                let date = Date(timeIntervalSince1970: 1_780_000_000)
                let archive = NFDataExportService.Archive(archiveVersion: NFDataExportService.archiveVersion,
                    exportedAt: date, appVersion: "isolated-ui-fixture", profile: nil, attempts: [], attemptReflections: [],
                    documents: [], sourceChunks: [], aiGenerations: [], sessionCheckpoints: [], dailyPlans: [], inputCalibrations: [],
                    progressAnnotations: [.init(id: UUID(), startDate: date, endDate: date, note: "Restored synthetic study note",
                        createdAt: date, modifiedAt: date)], excludedPrivateAnnotationCount: 0,
                    weeklyTransferState: nil, reassessmentState: nil, adaptivePlanHistory: [], quarantinedReports: [], localLearning: nil)
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
                try encoder.encode(archive).write(to: fixtureURL, options: .atomic)
            }
            let controller = try NFRestoreRuntimeController(applicationSupportURL: support,
                durableStoreURL: selection.durableStoreURL, owner: runID, lease: applicationStoreLease)
            store.bindRestoreArtifactDeletionController(controller)
            let integrations = NFSystemIntegrationCoordinator(defaults: defaults)
            integrations.willDeletePrivateData = { [weak controller] in await controller?.seal() }
            guard generation == launchGeneration else { await controller.seal(); return }
            restoreCompletion = outcome.completion; restoreRecoveryBlock = nil; canCancelRestoreRequest = false
            hasOpenedRuntime = true
            runtime = NFAppRuntime(modelContainer: container, store: store, systemIntegrations: integrations,
                startupTransition: .none, restoreController: controller)
        } catch {
            storeAccessUnavailable = true
        }
    }
    #endif

    private func restoreApplicationSupportURL(create: Bool = true) throws -> URL {
        #if DEBUG
        if let fixture = NFUITestLaunchConfiguration.restoreFixtureSupportURL { return fixture }
        #endif
        return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: create)
    }

    private func accountIdentityDidChange() {
        launchGeneration &+= 1
        forcedIdentityProbeConfiguration = lastIdentityProbeConfiguration
            ?? NFPrivateCloudRuntimeConfiguration.current()
        let supersededIntegrations = runtime?.systemIntegrations
        let supersededRestore = runtime?.restoreController
        let precedingStop = accountStopTask
        // Dropping the only app-level owner immediately releases the loaded
        // view/container graph. The replacement is debounced because CloudKit
        // can post a short wave while account state settles.
        runtime = nil
        restoreCompletion = nil
        restoreAcknowledgementFailed = false
        restoreRecoveryBlock = nil
        restoreRecoverySelection = nil
        canCancelRestoreRequest = false
        localPurgeNeedsRetry = false
        localPurgeCompletedAwaitingAcknowledgement = false
        completedPurgeIncludedPrivateCloud = false
        completedCloudDeletionID = nil
        completeDeletionNeedsRetry = nil
        accountStopTask = Task { @MainActor in
            _ = await precedingStop?.value
            await supersededRestore?.seal()
            await supersededIntegrations?.stopForAccountIdentityChange()
        }
        let stopBeforeRestart = accountStopTask
        accountRestartTask?.cancel()
        accountRestartTask = Task { @MainActor [weak self] in
            _ = await stopBeforeRestart?.value
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            await self?.startIfNeeded()
        }
    }

    private func startAfterSupersededLaunch() async {
        // Yield once so `startIfNeeded`'s defer releases the single-flight lock.
        await Task.yield()
        await startIfNeeded()
    }

    private func scheduleRestartAfterSupersededLaunch() {
        Task { @MainActor [weak self] in
            await self?.startAfterSupersededLaunch()
        }
    }

    func acknowledgeCompletedLocalPurge() {
        // Complete-cloud deletion consumes its request-bound receipt only when
        // its overall workflow is finalized. A local-only receipt has no cloud
        // transaction owner and is safe to consume on this acknowledgement.
        if let completedCloudDeletionID {
            _ = NFPrivateCloudCompleteDeletionWorkflow.acknowledgeCompletion(
                id: completedCloudDeletionID
            )
        } else {
            _ = NFPrivateCloudStoreIdentityResolver.consumeVerifiedLocalPurgeReceipt()
        }
        localPurgeCompletedAwaitingAcknowledgement = false
        completedPurgeIncludedPrivateCloud = false
        completedCloudDeletionID = nil
    }

    func retryCompleteDeletion() {
        completeDeletionNeedsRetry = nil
        Task { @MainActor [weak self] in
            await self?.startIfNeeded()
        }
    }

    func retryRestoreArtifactCleanup() async {
        guard restoreRecoveryBlock?.reason == .cleanupRequired, !isStarting,
              !isRetryingRestoreCleanup, let applicationStoreLease else { return }
        guard !hasOpenedRuntime else { restoreRecoveryBlock = .init(reason: .restartRequired); return }
        isRetryingRestoreCleanup = true
        let generation = launchGeneration
        do {
            let support = try restoreApplicationSupportURL(create: false)
            let owner = NFAppPreferenceScope.defaults.string(forKey: "NeuroForge.localSessionOwner.v1").flatMap(UUID.init(uuidString:))
            try await NFRestoreColdCoordinator.retryInvalidatedCleanup(applicationSupportURL: support,
                lease: applicationStoreLease, installationOwnerID: owner, hasOpenedRuntime: hasOpenedRuntime,
                isCurrentLaunch: { generation == self.launchGeneration })
            guard generation == launchGeneration else { isRetryingRestoreCleanup = false; return }
            restoreRecoveryBlock = nil
        } catch {
            guard generation == launchGeneration else { isRetryingRestoreCleanup = false; return }
            restoreRecoveryBlock = .init(reason: .cleanupRequired)
        }
        isRetryingRestoreCleanup = false
        if restoreRecoveryBlock == nil { await startIfNeeded() }
    }

    func cancelRestoreRequest() async {
        guard canCancelRestoreRequest, !isStarting, !hasOpenedRuntime,
              let selection = restoreRecoverySelection, let applicationStoreLease else { return }
        isStarting = true
        let generation = launchGeneration
        do {
            let support = try restoreApplicationSupportURL(create: false)
            let owner = NFAppPreferenceScope.defaults.string(forKey: "NeuroForge.localSessionOwner.v1").flatMap(UUID.init(uuidString:))
            try await NFRestoreColdCoordinator.cancelUnacceptedRequest(selection: selection,
                applicationSupportURL: support, lease: applicationStoreLease, installationOwnerID: owner,
                isCurrentLaunch: { generation == self.launchGeneration })
            canCancelRestoreRequest = false
            restoreRecoveryBlock = nil
        } catch { restoreRecoveryBlock = .init(reason: .unfinished) }
        isStarting = false
        if restoreRecoveryBlock == nil { await startIfNeeded() }
    }

    func acknowledgeRestoreCompletion() async {
        guard let receipt = restoreCompletion, let applicationStoreLease,
              !isAcknowledgingRestoreCompletion else { return }
        isAcknowledgingRestoreCompletion = true
        defer { isAcknowledgingRestoreCompletion = false }
        let generation = launchGeneration
        do {
            let support = try restoreApplicationSupportURL(create: false)
            let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: support), lease: applicationStoreLease)
            try await requests.acknowledgeCompletion(receipt)
            let remaining = try await requests.inspectAll()
            guard generation == launchGeneration else { return }
            restoreAcknowledgementFailed = false
            restoreCompletion = remaining.first {
                !$0.completionAcknowledged && $0.receipt?.resolution == .completed
                    && $0.namespace == receipt.namespace && $0.installationOwnerID == receipt.installationOwnerID
            }?.receipt
        } catch {
            guard generation == launchGeneration else { return }
            restoreAcknowledgementFailed = true
        }
    }
}

private struct NFAppLaunchView: View {
    let startup: NFAppStartupController

    var body: some View {
        Group {
            if startup.storeAccessUnavailable {
                NFStoreAccessUnavailableView {
                    Task { await startup.startIfNeeded() }
                }
            } else if let block = startup.completeDeletionNeedsRetry {
                NFCompleteDeletionRetryView(block: block) {
                    startup.retryCompleteDeletion()
                }
            } else if startup.localPurgeCompletedAwaitingAcknowledgement {
                NFLocalPurgeCompletedView(
                    includedPrivateCloud: startup.completedPurgeIncludedPrivateCloud
                ) {
                    startup.acknowledgeCompletedLocalPurge()
                }
            } else if let block = startup.restoreRecoveryBlock {
                NFRestoreStartupRecoveryView(block: block, canCancel: startup.canCancelRestoreRequest,
                    isRetryingCleanup: startup.isRetryingRestoreCleanup,
                    retryCleanup: { Task { await startup.retryRestoreArtifactCleanup() } }, cancel: {
                    Task { await startup.cancelRestoreRequest() }
                }) {
                    Task { await startup.startIfNeeded() }
                }
            } else if let completion = startup.restoreCompletion {
                NFRestoreCompletedView(receipt: completion,
                    isAcknowledging: startup.isAcknowledgingRestoreCompletion,
                    acknowledgementFailed: startup.restoreAcknowledgementFailed) {
                    Task { await startup.acknowledgeRestoreCompletion() }
                }
            } else if let runtime = startup.runtime {
                NFLoadedAppView(runtime: runtime)
            } else if startup.localPurgeNeedsRetry {
                NFLocalPurgeRetryView {
                    Task { await startup.startIfNeeded() }
                }
            } else {
                NFAppStartupProgressView()
            }
        }
        .environment(\.locale, NFAppLocalization.preferredLocale)
        .task { await startup.startIfNeeded() }
    }
}

private struct NFStoreAccessUnavailableView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(NFTheme.amberForeground)
            Text("Study stores are unavailable")
                .font(.headline)
            Text("Another NeuroForge instance may be using these study stores, or access could not be verified. Close the other instance and try again.")
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackground)
    }
}

private struct NFRestoreStartupRecoveryView: View {
    let block: NFRestoreStartupBlock
    let canCancel: Bool
    let isRetryingCleanup: Bool
    let retryCleanup: () -> Void
    let cancel: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(NFTheme.amberForeground)
            Text("Restore needs attention")
                .font(.headline)
            if block.reason == .cleanupRequired {
                Text("Recovery file cleanup is unfinished. Your study stores will stay closed until cleanup is verified.")
                    .multilineTextAlignment(.center)
            } else if block.reason == .reviewChanged {
                Text("Saved data changed after the preview. Cancel this request, then choose the backup again to review the updated counts. No restore changes have begun.")
                    .multilineTextAlignment(.center)
            } else if block.reason == .restartRequired {
                Text("Quit every NeuroForge window and reopen the app to continue this restore before study tools start.")
                    .multilineTextAlignment(.center)
            } else if block.reason == .wrongAccount {
                Text("This restore belongs to a different account or installation. Return to its original account before continuing.")
                    .multilineTextAlignment(.center)
            } else {
                Text("A saved restore could not be verified. Your backup and recovery files are preserved. Your study stores will stay closed until recovery is verified.")
                    .multilineTextAlignment(.center)
            }
            if block.reason == .cleanupRequired {
                Button("Retry restore cleanup", action: retryCleanup)
                    .buttonStyle(.borderedProminent).frame(minHeight: 44)
                    .disabled(isRetryingCleanup)
                Text("This only finishes removal of invalidated restore files. Retry your original deletion after the app reopens.")
                    .font(.footnote).multilineTextAlignment(.center)
            } else {
                Button("Check recovery again", action: retry)
                    .buttonStyle(.borderedProminent).frame(minHeight: 44)
            }
            if canCancel {
                Button("Cancel restore request", action: cancel)
                    .buttonStyle(.bordered).frame(minHeight: 44)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackground)
    }
}

private struct NFRestoreCompletedView: View {
    let receipt: NFRestoreRequestReceipt
    let isAcknowledging: Bool
    let acknowledgementFailed: Bool
    let continueAction: () -> Void
    private var restored: Int { receipt.counts.filter { $0.key.hasPrefix("restored.") }.values.reduce(0, +) }
    private var skipped: Int { receipt.counts.filter { $0.key.hasPrefix("skipped.") }.values.reduce(0, +) }
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(NFTheme.mintForeground)
            Text("Backup restored").font(.title2.bold())
            Text("Records and saved details restored: \(restored); skipped: \(skipped).")
                .multilineTextAlignment(.center)
            Text("Original imported files are not included in the JSON backup. Saved source text and citations remain available where the backup contains them.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if acknowledgementFailed {
                Text("Your restored data is saved. The completion acknowledgement could not be saved. Try Continue again.")
                    .font(.subheadline).foregroundStyle(NFTheme.amberForeground)
            }
            Button("Continue", action: continueAction).buttonStyle(.borderedProminent).frame(minHeight: 44)
                .disabled(isAcknowledging)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.windowBackground).accessibilityIdentifier("restore-completed")
    }
}

private struct NFCompleteDeletionRetryView: View {
    let block: NFCompleteDeletionStartupBlock
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(NFTheme.amberForeground)
            Text("Deletion needs retry")
                .font(.headline)
            Text("The saved private iCloud deletion could not finish safely. No database will open at this boundary. Retry after iCloud is available.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackground)
    }
}

private struct NFLocalPurgeCompletedView: View {
    let includedPrivateCloud: Bool
    let continueAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(NFTheme.mintForeground)
            if includedPrivateCloud {
                Text("Private iCloud data deleted")
                    .font(.headline)
                Text("NeuroForge verified both private iCloud zones are absent and removed this device’s study stores, imported copies, caches, and sync state.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Local data deleted")
                    .font(.headline)
                Text("NeuroForge verified this device’s study stores, imported copies, caches, and private-sync state are removed. Private iCloud copies were not deleted.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Continue", action: continueAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackground)
    }
}

private struct NFLocalPurgeRetryView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(NFTheme.amberForeground)
            Text("Deletion needs retry")
                .font(.headline)
            Text("Database deletion succeeded, but file cleanup could not be fully verified. Restart and retry local cleanup before uninstalling.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackground)
    }
}

private struct NFLoadedAppView: View {
    let runtime: NFAppRuntime
    @State private var todaySessionSequence = NFTodaySessionSequence()

    var body: some View {
        AppRootView()
            .defaultAppStorage(NFAppPreferenceScope.defaults)
            .environment(runtime.store)
            .environment(runtime.systemIntegrations)
            .environment(todaySessionSequence)
            .environment(runtime.sessionCommands)
            .environment(\.archiveRestoreController, runtime.restoreController)
            .environment(
                \.locale,
                Locale(identifier: runtime.store.profile?.preferredLanguageCode ?? Locale.current.identifier)
            )
            .modelContainer(runtime.modelContainer)
            .disabled(runtime.restoreController?.requiresRestart == true || runtime.restoreController?.isStaging == true || runtime.restoreController?.isCleaningRestoreArtifacts == true)
            .accessibilityHidden(runtime.restoreController?.requiresRestart == true)
            .allowsHitTesting(runtime.restoreController?.requiresRestart != true)
            .overlay {
                if runtime.restoreController?.requiresRestart == true {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.clockwise.circle").font(.largeTitle)
                        Text("Restart to restore your backup").font(.title2.bold())
                        Text("Your restore request is saved. Quit and reopen NeuroForge to verify the reviewed data and apply the backup before study tools start.")
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.windowBackground)
                    .accessibilityIdentifier("restore-restart-required")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if runtime.startupTransition.requiresUserAttention {
                    NFPrivateCloudTransitionBanner(
                        transition: runtime.startupTransition,
                        store: runtime.store
                    )
                }
            }
    }
}

private struct NFAppStartupProgressView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(NFTheme.cyanForeground)
            ProgressView()
            Text("Opening NeuroForge…")
                .font(.headline)
            Text("Checking private sync before opening your study history.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackground)
        .accessibilityElement(children: .combine)
    }
}

private struct NFPrivateCloudTransitionBanner: View {
    let transition: NFPrivateCloudStartupTransition
    let store: AppStore
    @State private var isConfirmingFreshAccount = false
    @State private var freshAccountIsScheduled = false
    @State private var freshAccountPreparationFailed = false
    @State private var isDismissed = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if !isDismissed {
                Group {
                    if horizontalSizeClass == .compact {
                        VStack(alignment: .leading, spacing: 10) {
                            messageLine
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) { actionButtons }
                                VStack(alignment: .leading, spacing: 8) { actionButtons }
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            messageLine
                            actionButtons
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Divider() }
            }
        }
        .confirmationDialog(
            "Start fresh with this iCloud account?",
            isPresented: $isConfirmingFreshAccount,
            titleVisibility: .visible
        ) {
            Button("Start Fresh After Reopening") {
                do {
                    try store.prepareDocumentsForFreshCloudAccount()
                    freshAccountIsScheduled = NFPrivateCloudStoreIdentityResolver
                        .acceptPendingAccountChange()
                    freshAccountPreparationFailed = !freshAccountIsScheduled
                } catch {
                    freshAccountPreparationFailed = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A separate empty study history will be created for this iCloud account. Your current history stays preserved and is not merged or deleted. Imported documents remain local and each original needs a fresh per-document iCloud opt-in.")
        }
    }

    private var messageLine: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(NFTheme.amberForeground)
            message
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button("Stay Local") {
            isDismissed = true
        }
        .buttonStyle(.bordered)
        Button("Settings") {
            store.selectedDestination = .settings
        }
        .buttonStyle(.bordered)
        if transition == .accountChanged, !freshAccountIsScheduled {
            Button("Start Fresh…") {
                isConfirmingFreshAccount = true
            }
            .buttonStyle(.borderedProminent)
            .tint(NFTheme.controlTint(for: "orange"))
            .foregroundStyle(NFTheme.controlForeground(for: "orange"))
        }
    }

    @ViewBuilder
    private var message: some View {
        switch transition {
        case .accountChanged:
            if freshAccountPreparationFailed {
                Text("The fresh account could not be prepared. Nothing was switched or deleted; retry when local saving is available.")
            } else if freshAccountIsScheduled {
                Text("A fresh private store is ready for this iCloud account. Quit and reopen NeuroForge to switch; your current history remains preserved.")
            } else {
                Text("iCloud account changed. You are viewing the previous local history with sync off. Export it or start a separate fresh history.")
            }
        case .legacyClaimFailed:
            Text("iCloud setup paused. Your existing local study history is unchanged.")
        case .identityStateUnavailable:
            Text("iCloud setup paused because the private store identity could not be verified.")
        case .none, .noAccount, .restricted, .temporarilyUnavailable, .accountStatusUnavailable:
            Text("Private sync is using local storage.")
        }
    }
}

struct NeuroForgeCommands: Commands {
    let store: AppStore
    let sessionCommands: NFSessionCommandBridge

    var body: some Commands {
        CommandMenu("Training") {
            Button("Start Today") {
                store.requestTodayPlan()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(store.activeSessionRequest != nil)

            Button("Practice Mental Math") {
                store.requestFocusedMentalMathPractice()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(store.activeSessionRequest != nil)

            Divider()

            Button("Submit or Next") {
                sessionCommands.send(.advance)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!sessionCommands.capabilities.canAdvance)

            Button("Pause or Resume") {
                sessionCommands.send(.togglePause)
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!sessionCommands.capabilities.canTogglePause)

            #if os(macOS)
            if NFSessionCloseRegistry.shared.hasPresentations {
                Button("Save and close session") {
                    NFSessionNativeCloseActions.shared.closeWindow(NSApp.keyWindow)
                }.keyboardShortcut("w")
            }
            #endif

            Button("Show Scratchpad") {
                sessionCommands.send(.showScratchpad)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!sessionCommands.capabilities.canShowScratchpad)

            Divider()

            Button("Import Study Material") {
                store.requestDocumentImport()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Open Data Export") {
                store.requestSettingsSubroute(.export)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Open Methodology") {
                store.requestSettingsSubroute(.methodology)
            }

            Divider()

            Button("Show Today") {
                store.selectedDestination = .today
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Show Practice") {
                store.selectedDestination = .train
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Show Progress") {
                store.selectedDestination = .progress
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("Show Sources") {
                store.selectedDestination = .library
            }
            .keyboardShortcut("4", modifiers: .command)

            Button("Show Settings") {
                store.selectedDestination = .settings
            }
            .keyboardShortcut("5", modifiers: .command)
        }
    }

}

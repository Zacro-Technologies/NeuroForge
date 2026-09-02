import CloudKit
import SwiftData
import SwiftUI

#if DEBUG
enum NFUITestLaunchConfiguration {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    static let declinesExternalURLs = ProcessInfo.processInfo.arguments.contains(
        "-ui-test-decline-external-url"
    )
    static let startsWithVerifiedQuestionWriter = ProcessInfo.processInfo.arguments.contains(
        "-ui-test-verified-question-writer"
    )
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
    @State private var startup = NFAppStartupController()

    var body: some Scene {
        #if os(macOS)
        Window("NeuroForge", id: "main") {
            NFAppLaunchView(startup: startup)
        }
        .commands {
            if let runtime = startup.runtime {
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
            if let runtime = startup.runtime {
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

    init(
        modelContainer: ModelContainer,
        store: AppStore,
        systemIntegrations: NFSystemIntegrationCoordinator,
        startupTransition: NFPrivateCloudStartupTransition
    ) {
        self.modelContainer = modelContainer
        self.store = store
        self.systemIntegrations = systemIntegrations
        self.startupTransition = startupTransition
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
        if NFUITestLaunchConfiguration.isEnabled {
            startUITestingRuntime()
            return
        }
        #endif

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

        let container: ModelContainer
        let launchPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration?
        let usedLocalCloudFallback: Bool
        var recoveryPackage: NFStoreRecoveryPackage?

        do {
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

        let appStore = AppStore(context: container.mainContext)
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
        let preparedRuntime = NFAppRuntime(
            modelContainer: container,
            store: appStore,
            systemIntegrations: integrations,
            startupTransition: selection.transition
        )
        guard generation == launchGeneration else {
            await preparedRuntime.systemIntegrations.stopForAccountIdentityChange()
            scheduleRestartAfterSupersededLaunch()
            return
        }
        runtime = preparedRuntime
    }

    #if DEBUG
    /// Gives XCUITest a disposable launch boundary without opening a learner's
    /// database or consulting CloudKit. Release builds do not compile this path.
    private func startUITestingRuntime() {
        UserDefaults.standard.removeObject(forKey: "nf.onboarding.step")
        UserDefaults.standard.removeObject(forKey: "nf.onboarding.draft")
        NFShortcutAuthoringConfiguration.clearSetupVerification()
        NFShortcutAuthoringConfiguration.clearInstallPageVisit()
        if NFUITestLaunchConfiguration.startsWithVerifiedQuestionWriter {
            NFShortcutAuthoringConfiguration.markSetupVerified()
        }

        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: NFSchemaMigrationPlan.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } catch {
            preconditionFailure("Unable to initialize the UI-testing store: \(error)")
        }

        let suiteName = "com.zacrotech.NeuroForge.ui-testing"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to initialize the UI-testing preferences.")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let testRoot = FileManager.default.temporaryDirectory
            .appending(path: "NeuroForge-UITests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let standardDefaults = UserDefaults.standard
        let languageKey = NFAppLocalization.preferredLanguageDefaultsKey
        let applicationDomainName = Bundle.main.bundleIdentifier ?? "com.zacrotech.NeuroForge"
        let savedLanguagePreference = standardDefaults
            .persistentDomain(forName: applicationDomainName)?[languageKey]
        defer {
            if let savedLanguagePreference {
                standardDefaults.set(savedLanguagePreference, forKey: languageKey)
            } else {
                standardDefaults.removeObject(forKey: languageKey)
            }
        }
        let appStore = AppStore(
            context: container.mainContext,
            documentStorageRootURL: testRoot.appending(path: "Documents", directoryHint: .isDirectory),
            adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(
                fileURL: testRoot.appending(path: "AdaptivePlanHistory.json", directoryHint: .notDirectory)
            ),
            offlineQuestionRotation: NFOfflineQuestionRotation(
                store: NFUserDefaultsOfflineQuestionRotationStateStore(defaults: defaults)
            )
        )
        let integrations = NFSystemIntegrationCoordinator(defaults: defaults)
        runtime = NFAppRuntime(
            modelContainer: container,
            store: appStore,
            systemIntegrations: integrations,
            startupTransition: .none
        )
    }
    #endif

    private func accountIdentityDidChange() {
        launchGeneration &+= 1
        forcedIdentityProbeConfiguration = lastIdentityProbeConfiguration
            ?? NFPrivateCloudRuntimeConfiguration.current()
        let supersededIntegrations = runtime?.systemIntegrations
        let precedingStop = accountStopTask
        // Dropping the only app-level owner immediately releases the loaded
        // view/container graph. The replacement is debounced because CloudKit
        // can post a short wave while account state settles.
        runtime = nil
        localPurgeNeedsRetry = false
        localPurgeCompletedAwaitingAcknowledgement = false
        completedPurgeIncludedPrivateCloud = false
        completedCloudDeletionID = nil
        completeDeletionNeedsRetry = nil
        accountStopTask = Task { @MainActor in
            _ = await precedingStop?.value
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
}

private struct NFAppLaunchView: View {
    let startup: NFAppStartupController

    var body: some View {
        Group {
            if let block = startup.completeDeletionNeedsRetry {
                NFCompleteDeletionRetryView(block: block) {
                    startup.retryCompleteDeletion()
                }
            } else if startup.localPurgeCompletedAwaitingAcknowledgement {
                NFLocalPurgeCompletedView(
                    includedPrivateCloud: startup.completedPurgeIncludedPrivateCloud
                ) {
                    startup.acknowledgeCompletedLocalPurge()
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
            .environment(runtime.store)
            .environment(runtime.systemIntegrations)
            .environment(todaySessionSequence)
            .environment(runtime.sessionCommands)
            .environment(
                \.locale,
                Locale(identifier: runtime.store.profile?.preferredLanguageCode ?? Locale.current.identifier)
            )
            .modelContainer(runtime.modelContainer)
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

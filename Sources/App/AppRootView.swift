import SwiftUI
#if canImport(CoreSpotlight)
import CoreSpotlight
#endif

struct AppRootView: View {
    @Environment(AppStore.self) private var store
    @Environment(NFSystemIntegrationCoordinator.self) private var systemIntegrations
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    @State private var visitedDestinations: Set<AppDestination> = [.today]
    @State private var navigation = NFNavigationState()
    @State private var pendingRootReset: AppDestination?

    var body: some View {
        @Bindable var store = store

        if let recoveryPackage = store.persistenceRecoveryPackage {
            PersistenceRecoveryView(package: recoveryPackage)
        } else if (try? NFReleaseContentGate.requireVerified()) == nil {
            ReleaseContentIntegrityFailureView()
        } else {
        #if os(iOS)
        rootContent(selection: destinationSelection)
            .environment(navigation)
            .transaction { transaction in
                if store.profile?.reducedMotion == true { transaction.animation = nil }
            }
            .fullScreenCover(item: $store.activeSessionRequest) { request in
                UniversalSessionView(request: request)
                    .id(request.id)
                    .environment(store)
            }
            .onChange(of: store.activeDirtyEditor?.id) { _, editorID in
                if editorID == nil, let destination = pendingRootReset {
                    navigation.returnToRoot(destination)
                    pendingRootReset = nil
                }
            }
            .onAppear(perform: consumePendingShortcutIfPossible)
            .onOpenURL(perform: handleDeepLink)
            #if canImport(CoreSpotlight)
            .onContinueUserActivity(CSSearchableItemActionType, perform: handleSpotlightActivity)
            #endif
            .onReceive(NotificationCenter.default.publisher(for: .neuroForgeExternalRouteRequested)) {
                if let url = $0.object as? URL { handleDeepLink(url) }
            }
            .task { await activateSystemIntegrationsIfAppropriate() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    store.retryPendingWrites()
                    consumePendingShortcutIfPossible()
                    Task { await activateSystemIntegrationsIfAppropriate() }
                } else if phase == .background {
                    prepareSystemIntegrationsForBackgroundIfAppropriate()
                }
            }
            .onChange(of: spotlightSourceFingerprint) { _, _ in
                navigation.prune(documentIDs: Set(store.documents.map(\.id)), attemptIDs: Set(store.attempts.map(\.id)))
                Task { await refreshSpotlightIfAppropriate() }
            }
            .onChange(of: store.isOnboardingComplete) { _, isComplete in
                if isComplete { consumePendingShortcutIfPossible() }
            }
            .onChange(of: preferredLanguageCode) { _, _ in
                store.publishWidgetSnapshot()
                Task { await refreshNotificationLanguageIfAppropriate() }
            }
            .onChange(of: reviewDeferralSignature) { _, _ in
                Task { await refreshNotificationLanguageIfAppropriate() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .neuroForgeShortcutQueued)) { _ in
                consumePendingShortcutIfPossible()
            }
            .alert(item: $store.notice) { notice in
                Alert(
                    title: Text(LocalizedStringKey(notice.title)),
                    message: Text(LocalizedStringKey(notice.message)),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert("Leave unsaved work?", isPresented: dirtyNavigationAlertBinding) {
                Button("Keep editing", role: .cancel) {
                    pendingRootReset = nil
                    store.cancelPendingDestinationChange()
                }
                Button("Discard and navigate", role: .destructive) {
                    store.discardDirtyEditorAndNavigate()
                }
            } message: {
                Text("\(store.activeDirtyEditor?.title ?? NFAppLocalization.localized("This editor", comment: "Fallback editor name in the global unsaved-navigation warning.")) has unsaved changes. Keep editing or explicitly discard them before changing sections.")
            }
        #else
        rootContent(selection: destinationSelection)
            .environment(navigation)
            .transaction { transaction in
                if store.profile?.reducedMotion == true { transaction.animation = nil }
            }
            .sheet(item: $store.activeSessionRequest) { request in
                UniversalSessionView(request: request)
                    .id(request.id)
                    .environment(store)
            }
            .onChange(of: store.activeDirtyEditor?.id) { _, editorID in
                if editorID == nil, let destination = pendingRootReset {
                    navigation.returnToRoot(destination)
                    pendingRootReset = nil
                }
            }
            .onAppear(perform: consumePendingShortcutIfPossible)
            .onOpenURL(perform: handleDeepLink)
            #if canImport(CoreSpotlight)
            .onContinueUserActivity(CSSearchableItemActionType, perform: handleSpotlightActivity)
            #endif
            .onReceive(NotificationCenter.default.publisher(for: .neuroForgeExternalRouteRequested)) {
                if let url = $0.object as? URL { handleDeepLink(url) }
            }
            .task { await activateSystemIntegrationsIfAppropriate() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    store.retryPendingWrites()
                    consumePendingShortcutIfPossible()
                    Task { await activateSystemIntegrationsIfAppropriate() }
                } else if phase == .background {
                    prepareSystemIntegrationsForBackgroundIfAppropriate()
                }
            }
            .onChange(of: spotlightSourceFingerprint) { _, _ in
                navigation.prune(documentIDs: Set(store.documents.map(\.id)), attemptIDs: Set(store.attempts.map(\.id)))
                Task { await refreshSpotlightIfAppropriate() }
            }
            .onChange(of: store.isOnboardingComplete) { _, isComplete in
                if isComplete { consumePendingShortcutIfPossible() }
            }
            .onChange(of: preferredLanguageCode) { _, _ in
                store.publishWidgetSnapshot()
                Task { await refreshNotificationLanguageIfAppropriate() }
            }
            .onChange(of: reviewDeferralSignature) { _, _ in
                Task { await refreshNotificationLanguageIfAppropriate() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .neuroForgeShortcutQueued)) { _ in
                consumePendingShortcutIfPossible()
            }
            .alert(item: $store.notice) { notice in
                Alert(
                    title: Text(LocalizedStringKey(notice.title)),
                    message: Text(LocalizedStringKey(notice.message)),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert("Leave unsaved work?", isPresented: dirtyNavigationAlertBinding) {
                Button("Keep editing", role: .cancel) {
                    pendingRootReset = nil
                    store.cancelPendingDestinationChange()
                }
                Button("Discard and navigate", role: .destructive) {
                    store.discardDirtyEditorAndNavigate()
                }
            } message: {
                Text("\(store.activeDirtyEditor?.title ?? NFAppLocalization.localized("This editor", comment: "Fallback editor name in the global unsaved-navigation warning.")) has unsaved changes. Keep editing or explicitly discard them before changing sections.")
            }
        #endif
        }
    }

    private var destinationSelection: Binding<AppDestination> {
        Binding(get: { store.selectedDestination }, set: { destination in
            if destination == store.selectedDestination {
                guard store.activeDirtyEditor == nil else {
                    pendingRootReset = destination
                    store.deferRootReselection(to: destination)
                    return
                }
                navigation.returnToRoot(destination)
            } else {
                store.selectedDestination = destination
            }
        })
    }

    private var dirtyNavigationAlertBinding: Binding<Bool> {
        Binding(
            get: {
                store.activeDirtyEditor != nil
                    && store.pendingDestinationAfterDirtyEditor != nil
            },
            set: { isPresented in
                if !isPresented { pendingRootReset = nil; store.cancelPendingDestinationChange() }
            }
        )
    }

    private func activateSystemIntegrationsIfAppropriate() async {
        #if DEBUG
        guard !NFUITestLaunchConfiguration.isEnabled else { return }
        #endif
        await systemIntegrations.activate(store: store)
    }

    private func prepareSystemIntegrationsForBackgroundIfAppropriate() {
        #if DEBUG
        guard !NFUITestLaunchConfiguration.isEnabled else { return }
        #endif
        systemIntegrations.prepareForBackground(store: store)
    }

    /// The metadata getter observes local revision, but only a changed saved
    /// deferral signature reschedules. Ordinary per-keystroke checkpoints do not.
    private var reviewDeferralSignature: [NFReviewDeferral] {
        store.privateStudyMetadata.reviewDeferrals ?? []
    }

    private func refreshNotificationLanguageIfAppropriate() async {
        #if DEBUG
        guard !NFUITestLaunchConfiguration.isEnabled else { return }
        #endif
        await systemIntegrations.refreshNotificationLanguage(store: store)
    }

    private func refreshSpotlightIfAppropriate() async {
        #if DEBUG
        guard !NFUITestLaunchConfiguration.isEnabled else { return }
        #endif
        await systemIntegrations.refreshSpotlightIndex(store: store)
    }

    private func consumePendingShortcutIfPossible() {
        #if DEBUG
        guard !NFUITestLaunchConfiguration.isEnabled else { return }
        #endif
        let canEnterApp = store.isOnboardingComplete || ProcessInfo.processInfo.arguments.contains("-skip-onboarding")
        guard canEnterApp else { return }
        NeuroForgeShortcutHandoff.consume(into: store)
        routePendingAuthoringCallbackIfNeeded()
    }

    private func handleDeepLink(_ url: URL) {
        if url.scheme?.lowercased() == NFShortcutAuthoringConfiguration.callbackScheme {
            guard let callback = NFShortcutAuthoringCallback.parse(url) else { return }
            Task { @MainActor in
                guard await NFShortcutAuthoringRequestStore.shared.callbackIsExpected(callback) else { return }
                guard NFShortcutAuthoringCallbackCenter.acceptVerified(callback) else { return }
                routePendingAuthoringCallbackIfNeeded()
            }
            return
        }
        guard let route = NFExternalRoute.parse(url) else { return }
        NFExternalRouteRouter.apply(route, to: store)
    }

    #if canImport(CoreSpotlight)
    private func handleSpotlightActivity(_ activity: NSUserActivity) {
        if let url = activity.webpageURL {
            handleDeepLink(url)
            return
        }
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              identifier.hasPrefix("nf-source-chunk:") else { return }
        let chunkID = String(identifier.dropFirst("nf-source-chunk:".count))
        NFExternalRouteRouter.apply(
            .source(NFSourceDeepLinkDestination(
                documentID: store.sourceChunks.first(where: { $0.id == chunkID })?.documentID,
                chunkID: chunkID
            )),
            to: store
        )
    }
    #endif

    private func routePendingAuthoringCallbackIfNeeded() {
        guard NFShortcutAuthoringCallbackCenter.hasPending() else { return }
        store.requestAIStudioForPendingShortcutCallback()
    }

    private var spotlightSourceFingerprint: String {
        store.sourceChunks.map(\.id).sorted().joined(separator: "|")
    }

    private var preferredLanguageCode: String {
        store.profile?.preferredLanguageCode ?? NFAppLocalization.preferredLanguageCode
    }

    @ViewBuilder
    private func rootContent(selection: Binding<AppDestination>) -> some View {
        if store.isOnboardingComplete || ProcessInfo.processInfo.arguments.contains("-skip-onboarding") {
            rootNavigation(selection: selection)
        } else {
            OnboardingView { draft in
                let didSave = store.completeOnboarding(draft, startPractice: true)
                if didSave { store.selectedDestination = .today }
                return didSave
            }
        }
    }

    @ViewBuilder
    private func rootNavigation(selection: Binding<AppDestination>) -> some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            TabView(selection: selection) {
                ForEach(AppDestination.allCases) { destination in
                    destinationView(destination)
                        // The floating compact tab bar overlaps scroll content on
                        // short phones unless each destination reserves its full
                        // visual height. This inset also gives accessibility-size
                        // controls room to scroll completely above the bar.
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            Color.clear
                                .frame(height: 68)
                                .accessibilityHidden(true)
                        }
                        .tag(destination)
                        .tabItem {
                            Label(destination.title, systemImage: destination.symbol)
                        }
                }
            }
            .tint(NFTheme.indigoForeground)
        } else {
            splitNavigation(selection: selection)
        }
        #else
        splitNavigation(selection: selection)
        #endif
    }

    private func splitNavigation(selection: Binding<AppDestination>) -> some View {
        NavigationSplitView {
            List {
                ForEach(AppDestination.allCases) { destination in
                    Button {
                        selection.wrappedValue = destination
                    } label: {
                        HStack {
                            Label(destination.title, systemImage: destination.symbol)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .listRowBackground(
                        selection.wrappedValue == destination
                        ? NFTheme.indigo.opacity(0.12)
                        : Color.clear
                    )
                    .accessibilityIdentifier("primary-navigation-\(destination.rawValue)")
                    .accessibilityAddTraits(selection.wrappedValue == destination ? .isSelected : [])
                }
            }
            .navigationTitle("NeuroForge")
        } detail: {
            // Keep each destination's own navigation host alive for this app run.
            // A shared detail stack lets stale children cover an unrelated root.
            ZStack {
                ForEach(AppDestination.allCases) { destination in
                    if visitedDestinations.contains(destination) || destination == selection.wrappedValue {
                        destinationView(destination)
                                .opacity(destination == selection.wrappedValue ? 1 : 0)
                            .allowsHitTesting(destination == selection.wrappedValue)
                            .accessibilityHidden(destination != selection.wrappedValue)
                            .zIndex(destination == selection.wrappedValue ? 1 : 0)
                    }
                }
            }
            .onChange(of: selection.wrappedValue, initial: true) { _, destination in
                visitedDestinations.insert(destination)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func destinationView(_ destination: AppDestination) -> some View {
        switch destination {
        case .today:
            TodayView()
                .accessibilityIdentifier("destination-today")
        case .train:
            TrainCatalogView()
                .accessibilityIdentifier("destination-train")
        case .progress:
            ProgressDashboardView()
                .accessibilityIdentifier("destination-progress")
        case .library:
            LibraryView()
                .accessibilityIdentifier("destination-library")
        case .settings:
            NavigationStack(path: Binding(get: { navigation.settings }, set: { navigation.settings = $0 })) {
                SettingsView()
                    .navigationDestination(for: NFSettingsRoute.self) { route in
                        switch route { case .methodology: MethodologyLibraryView() }
                    }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("destination-settings")
        }
    }
}

private struct ReleaseContentIntegrityFailureView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(alignment: .leading, spacing: 20) {
                    NFSectionHeader(
                        "Training content could not be verified",
                        eyebrow: "Protected content mode",
                        subtitle: "NeuroForge will not generate or score exercises when its signed release inventory is missing, altered, or incompatible."
                    )
                    Label(
                        "Your local learning history and imported documents are unchanged.",
                        systemImage: "lock.shield.fill"
                    )
                    .font(.headline)
                    Text("Install a complete, correctly signed NeuroForge build to resume training. You can still open Settings to export or delete your local data.")
                        .foregroundStyle(.secondary)
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Open Settings and data export", systemImage: "gearshape.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NFTheme.controlTint(for: "indigo"))
                    .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                }
                .padding(24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Content verification")
        }
    }
}

private struct PersistenceRecoveryView: View {
    let package: NFStoreRecoveryPackage

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NFSectionHeader(
                        "Local store needs recovery",
                        eyebrow: "Protected recovery mode",
                        subtitle: package.failureSummary
                    )
                    Label(
                        "Training and settings edits are disabled so the inaccessible database is never replaced by an empty store.",
                        systemImage: "lock.shield.fill"
                    )
                    .font(.headline)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Export recovery artifacts").font(.title2.bold())
                        Text("Keep every database file together. These files can contain prompts, answers, and imported source text; review the destination before sharing.")
                            .foregroundStyle(.secondary)
                        if package.artifactURLs.isEmpty {
                            Text("No readable store artifact could be copied. Preserve the app container and retry with a migration-capable build.")
                                .foregroundStyle(NFTheme.amberForeground)
                        } else {
                            ForEach(package.artifactURLs, id: \.path) { url in
                                ShareLink(item: url) {
                                    Label("Share \(url.lastPathComponent)", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .nfCard()

                    Text("After preserving the artifacts, quit NeuroForge and install a build with the required migration. This screen does not delete or repair the original store in place.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

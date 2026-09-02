import SwiftUI
import UniformTypeIdentifiers

private enum NFSettingsSectionAnchor: Hashable {
    case export
    case methodology
}

enum NFItemReportStatusCopy {
    static func title(
        for status: String,
        locale: Locale = NFAppLocalization.preferredLocale
    ) -> String {
        if status == "quarantined" {
            return NFAppLocalization.localized(
                "Excluded from future practice",
                locale: locale,
                comment: "Status for a reported question that is excluded from future practice."
            )
        }
        return NFAppLocalization.localized(
            "Allowed in future practice",
            locale: locale,
            comment: "Status for a reported question that remains eligible for future practice."
        )
    }

    static func exportLine(
        for status: String,
        locale: Locale = NFAppLocalization.preferredLocale
    ) -> String {
        let statusTitle = title(for: status, locale: locale)
        return NFAppLocalization.localized(
            "Status: \(statusTitle)",
            locale: locale,
            comment: "Status in a user-exported individual question report."
        )
    }
}

enum NFItemReportHistoryQuery {
    static func matches(
        prompt: String,
        reason: String,
        note: String,
        createdAt: Date,
        query: String,
        locale: Locale = NFAppLocalization.preferredLocale
    ) -> Bool {
        let needle = normalized(query)
        guard !needle.isEmpty else { return true }
        return normalized([
            prompt,
            reason,
            note,
            dateSearchText(for: createdAt, locale: locale)
        ].joined(separator: " ")).contains(needle)
    }

    static func dateSearchText(
        for date: Date,
        locale: Locale = NFAppLocalization.preferredLocale
    ) -> String {
        [
            NFAppLocalization.formattedDate(date, date: .abbreviated, time: .shortened, locale: locale),
            NFAppLocalization.formattedDate(date, date: .complete, time: .omitted, locale: locale)
        ].joined(separator: " ")
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(NFSystemIntegrationCoordinator.self) private var systemIntegrations
    @Environment(\.openURL) private var openURL

    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingCloudDeleteConfirmation = false
    @State private var isShowingPrivacyPolicy = false
    @State private var exportURLs: [URL] = []
    @State private var exportError: String?
    @State private var isShowingRestoreImporter = false
    @State private var isShowingRestorePreview = false
    @State private var restoreArchiveURL: URL?
    @State private var restorePreview: NFDataArchiveRestorePreview?
    @State private var isShowingProfileEditor = false
    @State private var isShowingInputCalibration = false
    @State private var isShowingMethodologyLibrary = false
    @State private var isShowingOnboardingRestartConfirmation = false
    @State private var showsAllReports = false
    @State private var reportSearchText = ""
    @State private var reportVisibleLimit = 20
    @State private var reportPendingDeletion: ItemReportRecord?
    @State private var reportedItemsError: String?

    private let sessionDurations = [5, 10, 15, 20]

    var body: some View {
        ZStack {
            AppBackground()

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 18, alignment: .top)],
                            alignment: .leading,
                            spacing: 18
                        ) {
                            profileAndTrainingCard
                            aiCard
                            syncCard
                            SystemControlsCard()
                            exportCard
                                .id(NFSettingsSectionAnchor.export)
                            if !store.itemReports.isEmpty {
                                reportedItemsCard
                            }
                            methodologyCard
                                .id(NFSettingsSectionAnchor.methodology)
                        }

                        deleteCard
                    }
                    .frame(maxWidth: 960, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
                .onAppear { resolvePendingSubroute(using: scrollProxy) }
                .onChange(of: store.pendingSettingsSubroute) { _, _ in
                    resolvePendingSubroute(using: scrollProxy)
                }
            }
        }
        .navigationTitle("Settings")
        .alert("Delete all local data?", isPresented: $isShowingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete all local data", role: .destructive) {
                Task {
                    do {
                        try await systemIntegrations.deleteAllLocalData(store: store)
                    } catch {
                        // The coordinator surfaces the failed component and
                        // leaves this action available for an idempotent retry.
                    }
                }
            }
        } message: {
            Text("This removes this device’s profile, practice and calibration history, imported app-managed copies, prepared exports, generated-question cache, private-sync queue, Spotlight entries, managed notifications, and widget snapshot. Private iCloud copies are not deleted.")
        }
        .alert("Delete private iCloud data and this device?", isPresented: $isShowingCloudDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Request complete deletion", role: .destructive) {
                Task {
                    do {
                        try await systemIntegrations.deleteAllData(
                            scope: .privateCloudAndThisDevice,
                            store: store
                        )
                    } catch let deletionError as NFPrivateSyncDeletionError {
                        if case .restartRequiredForCompleteDeletion = deletionError {
                            // The coordinator already published the expected
                            // two-launch restart boundary.
                            return
                        }
                        let message = deletionError.errorDescription
                            ?? NFAppLocalization.localized("Complete deletion could not be verified. Local data was kept at the unfinished destructive boundary; retry from Settings.", locale: NFAppLocalization.preferredLocale, comment: "Fallback error for scoped local-and-cloud deletion.")
                        store.lastErrorMessage = message
                        store.notice = AppNotice(
                            title: NFAppLocalization.localized("Deletion needs retry", locale: NFAppLocalization.preferredLocale, comment: "Title for a scoped data-deletion failure."),
                            message: message
                        )
                    } catch {
                        let message = NFAppLocalization.localized("Complete deletion could not be verified. Local data was kept at the unfinished destructive boundary; retry from Settings.", locale: NFAppLocalization.preferredLocale, comment: "Fallback error for scoped local-and-cloud deletion.")
                        store.lastErrorMessage = message
                        store.notice = AppNotice(
                            title: NFAppLocalization.localized("Deletion needs retry", locale: NFAppLocalization.preferredLocale, comment: "Title for a scoped data-deletion failure."),
                            message: message
                        )
                    }
                }
            }
        } message: {
            Text("This requests verified deletion of NeuroForge’s private iCloud records and synced originals, then removes this device’s profile, practice and calibration history, imported copies, exports, caches, search entries, reminders, widget snapshot, and sync queue. You may need to reopen the app twice to finish verification.")
        }
        .sheet(isPresented: $isShowingPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $isShowingProfileEditor) {
            ProfileEditorView(draft: editableDraft) { updated in
                try store.updateProfile(from: updated)
                Task { await systemIntegrations.activate(store: store) }
            }
        }
        .sheet(isPresented: $isShowingInputCalibration) {
            InputCalibrationSettingsView(draft: calibrationDraft)
                .environment(store)
        }
        .sheet(isPresented: $isShowingMethodologyLibrary) {
            MethodologyLibraryView(showsDismissButton: true)
        }
        .sheet(isPresented: $isShowingRestorePreview, onDismiss: discardStagedRestoreArchive) {
            if let restoreArchiveURL, let restorePreview {
                NFArchiveRestorePreviewView(
                    archiveURL: restoreArchiveURL,
                    preview: restorePreview
                )
                .environment(store)
            }
        }
        .fileImporter(
            isPresented: $isShowingRestoreImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: prepareRestorePreview
        )
        .alert("Restart setup preferences?", isPresented: $isShowingOnboardingRestartConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restart setup") {
                store.restartOnboardingPreferences()
            }
        } message: {
            Text("This returns you to onboarding but keeps your answers, skill checks, imported materials, notes, and history. Deleting history is a separate action below.")
        }
        .alert("Export could not be prepared", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(LocalizedStringKey(exportError ?? "Try again after freeing local storage.")) }
        .alert("Delete this saved report?", isPresented: Binding(
            get: { reportPendingDeletion != nil },
            set: { if !$0 { reportPendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) { reportPendingDeletion = nil }
            Button("Delete report", role: .destructive) { deletePendingReport() }
        } message: {
            Text("This removes the report from NeuroForge and from future exports. If the question is currently excluded, deleting its report allows that question to appear again.")
        }
    }

    private var header: some View {
        NFSectionHeader(
            "Settings",
            subtitle: "Adjust your practice, question sets, sync, reminders, and accessibility.",
            headingLevel: .h1
        )
    }

    private var profileAndTrainingCard: some View {
        SettingsCard(
            symbol: "person.crop.circle.fill",
            color: NFTheme.indigo,
            title: "Profile & training",
            subtitle: "Update what you study and how practice feels."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fields")
                        .font(.subheadline.weight(.semibold))
                    FlowLayout(spacing: 7) {
                        ForEach(sortedFields) { field in
                            SettingsChip(text: field.title, color: NFTheme.cyan)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Goals")
                        .font(.subheadline.weight(.semibold))
                    FlowLayout(spacing: 7) {
                        ForEach(sortedGoals) { goal in
                            SettingsChip(text: goal.title, color: NFTheme.indigo)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Text("Daily session")
                        .font(.subheadline.weight(.semibold))
                    Picker("Daily session length", selection: dailyDurationBinding) {
                        ForEach(sessionDurations, id: \.self) { minutes in
                            Text(NFAppLocalization.formattedMinutes(minutes, style: .compact)).tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Picker("Timing preference", selection: timingModeBinding) {
                    ForEach(TimingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Training day starts") {
                    Text(dayBoundaryDescription)
                        .foregroundStyle(.secondary)
                }

                Toggle("Haptic reinforcement", isOn: reinforcementHapticsBinding)
                    .font(.subheadline.weight(.semibold))
                Toggle("Sound reinforcement", isOn: reinforcementSoundBinding)
                    .font(.subheadline.weight(.semibold))

                Button { isShowingProfileEditor = true } label: {
                    Label("More practice & accessibility settings", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderedProminent)
                .tint(NFTheme.controlTint)
                .foregroundStyle(NFTheme.controlForeground)

                if let calibration = store.latestInputCalibration {
                    LabeledContent("Last input calibration") {
                        Text(calibrationDate(calibration.completedAt))
                            .foregroundStyle(.secondary)
                    }
                }

                Button { isShowingInputCalibration = true } label: {
                    Label("Recalibrate keyboard, touch, or pointer", systemImage: "gauge.with.dots.needle.50percent")
                }
                .buttonStyle(.bordered)

                Button("Reset preferences & restart setup…") {
                    isShowingOnboardingRestartConfirmation = true
                }
                .buttonStyle(.bordered)

                if !store.isOnboardingComplete {
                    Label("Complete onboarding to save training preferences.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!store.isOnboardingComplete)
        }
    }

    private var aiCard: some View {
        SettingsCard(
            symbol: "wand.and.stars",
            color: NFTheme.rose,
            title: "Question Writer",
            subtitle: "Use a Shortcut you control. ChatGPT is recommended."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Use Question Writer Shortcut", isOn: shortcutAuthoringBinding)
                    .font(.subheadline.weight(.semibold))
                    .disabled(!store.isOnboardingComplete)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: aiStatusSymbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(aiStatusColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(aiStatusTitle))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(LocalizedStringKey(aiModeExplanation))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if store.profileSnapshot.aiMode == .automatic,
                   let installURL = NFShortcutAuthoringConfiguration.installURL() {
                    Button {
                        openURL(installURL) { accepted in
                            Task { @MainActor in
                                guard accepted else { return }
                                NFShortcutAuthoringConfiguration.markInstallPageVisited()
                            }
                        }
                    } label: {
                        Label("Add or reinstall Question Writer", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NFTheme.roseControlTint)
                    .foregroundStyle(NFTheme.roseControlForeground)

                    Text("Shortcuts lists it as NeuroForge Private Authoring. After adding it, choose ChatGPT in its Use Model action. You can choose another available model; NeuroForge cannot verify which provider you select.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var syncCard: some View {
        SettingsCard(
            symbol: "arrow.triangle.2.circlepath.icloud.fill",
            color: NFTheme.cyan,
            title: "Storage & sync",
            subtitle: "Keep progress available across your Apple devices."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Sync with iCloud", isOn: privateSyncBinding)
                    .font(.subheadline.weight(.semibold))
                    .disabled(!store.isOnboardingComplete)

                LabeledContent("Training data") {
                    Text(structuredSyncStatusTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                LabeledContent("Original files") {
                    Text(syncStatusTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                if systemIntegrations.structuredSyncStatus.configurationChangeRequiresRestart {
                    Label("Reopen NeuroForge to apply the iCloud sync change.", systemImage: "arrow.clockwise")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if systemIntegrations.structuredSyncStatus.displayState == .error
                    || systemIntegrations.syncStatus.displayState == .error {
                    Button {
                        Task {
                            await systemIntegrations.reconcilePrivateDocumentSync(
                                store: store,
                                synchronize: true
                            )
                        }
                    } label: {
                        Label("Retry sync", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!systemIntegrations.syncCapability.supportsPrivateSyncAttempt)
                }
            }
        }
    }

    private var exportCard: some View {
        SettingsCard(
            symbol: "square.and.arrow.up.fill",
            color: NFTheme.amber,
            title: "Export",
            subtitle: "Download a copy of your NeuroForge data."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    do {
                        exportURLs = try NFDataExportService.makeExports(from: store)
                        exportError = nil
                    } catch {
                        exportError = NFDiagnosticRedactor.userMessage(for: error, context: .dataExport)
                    }
                } label: {
                    Label(exportURLs.isEmpty ? "Prepare full export" : "Refresh full export", systemImage: "archivebox.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(NFTheme.controlTint(for: "indigo"))
                .foregroundStyle(NFTheme.controlForeground(for: "indigo"))

                ForEach(exportURLs, id: \.path) { url in
                    ShareLink(item: url) {
                        Label(url.lastPathComponent, systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                Button {
                    isShowingRestoreImporter = true
                } label: {
                    Label("Restore full JSON backup", systemImage: "arrow.uturn.backward.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("NeuroForge validates the entire backup and shows its version, record counts, warnings, and conflicts before changing local data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ShareLink(item: shareSummary) {
                    Label("Share redacted text summary", systemImage: "doc.plaintext")
                }

                DisclosureGroup {
                    Text("The export includes your profile, practice history, question sets, imported material, notes you marked for export, and reported items. It is created on this device and shared only when you choose a destination.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                } label: {
                    Label("What the export includes", systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(NFTheme.amberForeground)
            }
        }
    }

    private func prepareRestorePreview(_ result: Result<[URL], Error>) {
        do {
            let selectedURL = try result.get().first
            guard let selectedURL else { return }
            discardStagedRestoreArchive()

            let accessed = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { selectedURL.stopAccessingSecurityScopedResource() }
            }

            let stagedURL = FileManager.default.temporaryDirectory
                .appending(path: "NeuroForge-Restore-\(UUID().uuidString)")
                .appendingPathExtension("json")
            try FileManager.default.copyItem(at: selectedURL, to: stagedURL)
            let preview = try NFDataArchiveRestoreService.preview(archiveAt: stagedURL, into: store)
            restoreArchiveURL = stagedURL
            restorePreview = preview
            exportError = nil
            isShowingRestorePreview = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func discardStagedRestoreArchive() {
        if let restoreArchiveURL {
            try? FileManager.default.removeItem(at: restoreArchiveURL)
        }
        restoreArchiveURL = nil
        restorePreview = nil
    }

    private var methodologyCard: some View {
        SettingsCard(
            symbol: "text.book.closed.fill",
            color: NFTheme.indigo,
            title: "About NeuroForge",
            subtitle: "Methodology, privacy, and app information."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Evidence, not a single score")
                        .font(.subheadline.weight(.semibold))
                    Text("Progress keeps practiced performance, unfamiliar transfer, delayed retention, and confidence calibration separate. Estimates include uncertainty and become more stable as evidence grows.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    isShowingMethodologyLibrary = true
                } label: {
                    Label("How progress is measured", systemImage: "chart.bar.doc.horizontal")
                }
                .buttonStyle(.borderedProminent)
                .tint(NFTheme.controlTint(for: "indigo"))
                .foregroundStyle(NFTheme.controlForeground(for: "indigo"))

                Button {
                    isShowingPrivacyPolicy = true
                } label: {
                    Label("Privacy policy", systemImage: "hand.raised.fill")
                }
                .buttonStyle(.bordered)

                DisclosureGroup("Educational use") {
                    Text("NeuroForge is a learning and practice tool, not a medical or diagnostic service.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }

                Text("Version \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var reportedItemsCard: some View {
        SettingsCard(
            symbol: "exclamationmark.bubble.fill",
            color: NFTheme.rose,
            title: "Saved question reports",
            subtitle: "Search, export, or delete every retained report."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if showsAllReports {
                    TextField("Search saved reports", text: $reportSearchText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityHint("Searches report dates, question prompts, reasons, and optional notes")
                }

                if visibleReports.isEmpty {
                    ContentUnavailableView.search(text: reportSearchText)
                        .frame(minHeight: 120)
                } else {
                    ForEach(visibleReports) { report in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(NFAppLocalization.formattedDate(
                                report.createdAt,
                                date: .abbreviated,
                                time: .shortened
                            ))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            Text(report.prompt)
                                .font(.subheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(report.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !report.note.isEmpty {
                                Text(verbatim: report.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Label(
                                NFItemReportStatusCopy.title(for: report.status),
                                systemImage: report.status == "quarantined" ? "nosign" : "checkmark.circle"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(report.status == "quarantined" ? NFTheme.roseForeground : NFTheme.mintForeground)

                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) { reportActions(report) }
                                VStack(alignment: .leading, spacing: 8) { reportActions(report) }
                            }
                        }
                        if report.id != visibleReports.last?.id { Divider() }
                    }

                    if store.itemReports.count > 4 {
                        Button {
                            showsAllReports.toggle()
                            if !showsAllReports {
                                reportSearchText = ""
                                reportVisibleLimit = 20
                            }
                        } label: {
                            Label(
                                showsAllReports ? "Show recent reports" : "See all saved reports",
                                systemImage: showsAllReports ? "chevron.up" : "clock.arrow.circlepath"
                            )
                        }
                        .buttonStyle(.bordered)
                    }

                    if showsAllReports, filteredReports.count > reportVisibleLimit {
                        Button("Load more reports") { reportVisibleLimit += 20 }
                            .buttonStyle(.bordered)
                            .accessibilityValue(NFAppLocalization.localized(
                                "\(NFAppLocalization.formattedReportCount(visibleReports.count)) of \(NFAppLocalization.formattedReportCount(filteredReports.count)) shown",
                                locale: NFAppLocalization.preferredLocale,
                                comment: "Reported-item paging status with localized visible and total report counts."
                            ))
                    }
                }

                if let reportedItemsError {
                    Label(reportedItemsError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(NFTheme.roseForeground)
                }

                Text("Reports remain on this device until you delete them and are included in the full JSON export. Allowing a question again preserves its original report for your history.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deleteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                NFIconTile(symbol: "trash.fill", color: NFTheme.rose)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Delete local data")
                        .font(.headline)
                    Text("Remove every NeuroForge-managed local privacy surface from this device. Private iCloud data is a separate action.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if systemIntegrations.localDataDeletionIsRunning {
                        Label {
                            Text("Verifying every local privacy surface…")
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "hourglass")
                                .foregroundStyle(NFTheme.amberForeground)
                                .accessibilityHidden(true)
                        }
                        .font(.footnote.weight(.semibold))
                    } else if let deletionError = systemIntegrations.localDataDeletionError {
                        Text(deletionError)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                        Text("Retry checks every cleanup surface again, including exports, generated cache, Spotlight, notifications, widgets, sync state, database records, imported files, and structured-store files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { deleteActionButtons }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .trailing, spacing: 8) { deleteActionButtons }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .disabled(
                systemIntegrations.localDataDeletionIsRunning
                    || !hasAnyLocalCleanupScope
            )
        }
        .nfCard()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var deleteActionButtons: some View {
        Button(
            systemIntegrations.localDataDeletionError == nil
                ? "Delete this device…"
                : "Retry local delete…",
            role: .destructive
        ) {
            isShowingDeleteConfirmation = true
        }
        .buttonStyle(.bordered)

        Button("Delete iCloud & this device…", role: .destructive) {
            isShowingCloudDeleteConfirmation = true
        }
        .buttonStyle(.borderedProminent)
        .tint(NFTheme.roseControlTint)
        .foregroundStyle(NFTheme.roseControlForeground)
        .disabled(!systemIntegrations.syncCapability.supportsPrivateSyncAttempt)
    }

    private var dailyDurationBinding: Binding<Int> {
        Binding(
            get: { store.profileSnapshot.dailyDuration },
            set: { store.updateDailyDuration($0) }
        )
    }

    private var timingModeBinding: Binding<TimingMode> {
        Binding(
            get: { store.profileSnapshot.timingMode },
            set: { store.updateTimingMode($0) }
        )
    }

    private var reinforcementHapticsBinding: Binding<Bool> {
        Binding(
            get: { store.profile?.reinforcementHapticsEnabled ?? false },
            set: { store.updateReinforcementPreferences(hapticsEnabled: $0) }
        )
    }

    private var reinforcementSoundBinding: Binding<Bool> {
        Binding(
            get: { store.profile?.reinforcementSoundEnabled ?? false },
            set: { store.updateReinforcementPreferences(soundEnabled: $0) }
        )
    }

    private var shortcutAuthoringBinding: Binding<Bool> {
        Binding(
            get: { store.profileSnapshot.aiMode == .automatic },
            set: { store.updateAIMode($0 ? .automatic : .disabled) }
        )
    }

    private var privateSyncBinding: Binding<Bool> {
        Binding(
            get: { store.profileSnapshot.iCloudEnabled },
            set: { enabled in
                store.updatePrivateSyncEnabled(enabled)
                Task { await systemIntegrations.activate(store: store) }
            }
        )
    }

    private var structuredSyncStatusTitle: String {
        switch systemIntegrations.structuredSyncStatus.displayState {
        case .localOnly: NFAppLocalization.localized("Local only", locale: NFAppLocalization.preferredLocale, comment: "Structured private-iCloud status title.")
        case .queued: NFAppLocalization.localized("Queued", locale: NFAppLocalization.preferredLocale, comment: "Structured private-iCloud status title.")
        case .syncing: NFAppLocalization.localized("Syncing", locale: NFAppLocalization.preferredLocale, comment: "Structured private-iCloud status title.")
        case .synced: NFAppLocalization.localized("Synced", locale: NFAppLocalization.preferredLocale, comment: "Structured private-iCloud status title after a successful framework event and no observed local writes.")
        case .paused: NFAppLocalization.localized("Paused", locale: NFAppLocalization.preferredLocale, comment: "Structured private-iCloud status title.")
        case .error: NFAppLocalization.localized("Needs attention", locale: NFAppLocalization.preferredLocale, comment: "Structured private-iCloud status title.")
        }
    }

    private func syncColor(_ state: NFSyncDisplayState) -> Color {
        switch state {
        case .synced: NFTheme.mint
        case .queued, .syncing, .paused: NFTheme.amber
        case .error: NFTheme.rose
        case .localOnly: .secondary
        }
    }

    private var syncStatusTitle: String {
        switch systemIntegrations.syncStatus.displayState {
        case .localOnly: NFAppLocalization.localized("Local only", locale: NFAppLocalization.preferredLocale, comment: "Private iCloud status title.")
        case .queued: NFAppLocalization.localized("Queued", locale: NFAppLocalization.preferredLocale, comment: "Private iCloud status title.")
        case .syncing: NFAppLocalization.localized("Syncing", locale: NFAppLocalization.preferredLocale, comment: "Private iCloud status title.")
        case .synced: NFAppLocalization.localized("Synced", locale: NFAppLocalization.preferredLocale, comment: "Private iCloud status title.")
        case .paused: NFAppLocalization.localized("Paused", locale: NFAppLocalization.preferredLocale, comment: "Private iCloud status title.")
        case .error: NFAppLocalization.localized("Needs attention", locale: NFAppLocalization.preferredLocale, comment: "Private iCloud status title.")
        }
    }

    private var sortedFields: [STEMField] {
        store.profileSnapshot.fields.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var sortedGoals: [TrainingGoal] {
        store.profileSnapshot.goals.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var filteredReports: [ItemReportRecord] {
        let query = reportSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let reports = store.itemReports.sorted {
            if $0.createdAt == $1.createdAt { return $0.id.uuidString > $1.id.uuidString }
            return $0.createdAt > $1.createdAt
        }
        guard !query.isEmpty else { return reports }
        return reports.filter { report in
            NFItemReportHistoryQuery.matches(
                prompt: report.prompt,
                reason: report.reason,
                note: report.note,
                createdAt: report.createdAt,
                query: query
            )
        }
    }

    private var visibleReports: [ItemReportRecord] {
        Array(filteredReports.prefix(showsAllReports ? reportVisibleLimit : 4))
    }

    @ViewBuilder
    private func reportActions(_ report: ItemReportRecord) -> some View {
        if report.status == "quarantined" {
            Button("Allow question again") {
                store.allowReportedItemAgain(report)
            }
            .buttonStyle(.bordered)
        }

        ShareLink(item: reportExportText(report)) {
            Label("Export report", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)

        Button(role: .destructive) {
            reportPendingDeletion = report
        } label: {
            Label("Delete report", systemImage: "trash")
        }
        .buttonStyle(.bordered)
    }

    private func reportExportText(_ report: ItemReportRecord) -> String {
        let formatter = DateFormatter()
        formatter.locale = NFAppLocalization.preferredLocale
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return [
            NFAppLocalization.localized("NeuroForge question report", locale: NFAppLocalization.preferredLocale, comment: "Title in a user-exported individual question report."),
            NFAppLocalization.localized("Reported: \(formatter.string(from: report.createdAt))", locale: NFAppLocalization.preferredLocale, comment: "Date in a user-exported individual question report."),
            NFAppLocalization.localized("Question: \(report.prompt)", locale: NFAppLocalization.preferredLocale, comment: "Question prompt in a user-exported individual report."),
            NFAppLocalization.localized("Reason: \(report.reason)", locale: NFAppLocalization.preferredLocale, comment: "Reason in a user-exported individual question report."),
            report.note.isEmpty
                ? NFAppLocalization.localized("Note: None", locale: NFAppLocalization.preferredLocale, comment: "Empty note in a user-exported individual question report.")
                : NFAppLocalization.localized("Note: \(report.note)", locale: NFAppLocalization.preferredLocale, comment: "Optional note in a user-exported individual question report."),
            NFItemReportStatusCopy.exportLine(for: report.status)
        ].joined(separator: "\n")
    }

    private func deletePendingReport() {
        guard let reportPendingDeletion else { return }
        store.context.delete(reportPendingDeletion)
        do {
            try store.context.save()
            store.reload()
            reportedItemsError = nil
        } catch {
            store.context.rollback()
            store.reload()
            reportedItemsError = NFAppLocalization.localized(
                "The saved report was not deleted. Try again.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Error after deleting an individual saved question report."
            )
        }
        self.reportPendingDeletion = nil
    }

    private var editableDraft: OnboardingDraft {
        guard let profile = store.profile else { return OnboardingDraft() }
        return OnboardingDraft(
            stage: profile.snapshot.stage,
            fields: profile.snapshot.fields,
            goals: profile.snapshot.goals,
            dailyDuration: profile.dailyDuration,
            timingMode: profile.snapshot.timingMode,
            aiMode: profile.snapshot.aiMode,
            iCloudEnabled: profile.iCloudEnabled,
            reducedMotion: profile.reducedMotion,
            hideTimers: profile.hideTimers,
            excludeVisualSpatial: profile.excludeVisualSpatial,
            preferredLanguageCode: profile.preferredLanguageCode,
            trainingDays: Set(profile.trainingDaysRaw.split(separator: ",").compactMap { Int($0) }),
            dayBoundaryHour: profile.dayBoundaryHour,
            claimsPolicyAcknowledgedVersion: profile.claimsPolicyAcknowledgedVersion,
            ageBandAcknowledged16Plus: profile.ageBandAcknowledged16Plus,
            preferredAnswerMode: NFPreferredAnswerMode(rawValue: profile.preferredAnswerModeRaw) ?? .adaptive,
            reinforcementHapticsEnabled: profile.reinforcementHapticsEnabled,
            reinforcementSoundEnabled: profile.reinforcementSoundEnabled,
            startBaselineImmediately: false
        )
    }

    private var calibrationDraft: OnboardingDraft {
        var draft = editableDraft
        if let calibration = store.latestInputCalibration {
            draft.preferredAnswerMode = calibration.preferredAnswerMode
            draft.keyboardLatencyMilliseconds = calibration.keyboardLatencyMilliseconds
            draft.touchLatencyMilliseconds = calibration.touchLatencyMilliseconds
            draft.pencilLatencyMilliseconds = calibration.pencilLatencyMilliseconds
        }
        return draft
    }

    private func calibrationDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = NFAppLocalization.preferredLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var hasAnyLocalCleanupScope: Bool {
        let snapshot = systemIntegrations.privacyDashboardSnapshot(store: store)
        return systemIntegrations.localDataDeletionError != nil
            || snapshot.localDurableRecordCount > 0
            || snapshot.localOnlyRecordCount > 0
            || systemIntegrations.notificationPreferences.hasConfiguredReminder
            || systemIntegrations.spotlightDraftEnabled
            || systemIntegrations.syncStatus.queue.pendingRecordCount > 0
            || systemIntegrations.syncStatus.queue.pendingAssetCount > 0
    }

    private var dayBoundaryDescription: String {
        NFTrainingDayBoundaryFormatter.title(for: store.profileSnapshot.dayBoundaryHour)
    }

    private var aiStatusTitle: String {
        switch store.profileSnapshot.aiMode {
        case .automatic:
            NFShortcutAuthoringConfiguration.installURL() == nil
                ? "Question Writer unavailable"
                : "Question Writer selected"
        case .onDeviceOnly, .disabled:
            "Offline authoring"
        }
    }

    private var aiStatusSymbol: String {
        switch store.profileSnapshot.aiMode {
        case .automatic:
            NFShortcutAuthoringConfiguration.installURL() == nil
                ? "exclamationmark.circle.fill"
                : "arrow.triangle.branch"
        case .onDeviceOnly, .disabled: "gearshape.2.fill"
        }
    }

    private var aiStatusColor: Color {
        switch store.profileSnapshot.aiMode {
        case .automatic:
            NFShortcutAuthoringConfiguration.installURL() == nil ? NFTheme.amberForeground : NFTheme.roseForeground
        case .onDeviceOnly, .disabled: NFTheme.amberForeground
        }
    }

    private var aiModeExplanation: String {
        switch store.profileSnapshot.aiMode {
        case .automatic:
            NFShortcutAuthoringConfiguration.installURL() == nil
                ? "The Question Writer Shortcut is not available in this build."
                : "Question Writer is selected. Its availability is checked when you create a set; if the Shortcut is missing or changed, reinstall it or create offline."
        case .onDeviceOnly, .disabled:
            "Question sets are created offline."
        }
    }

    private var shareSummary: String {
        let profile = store.profileSnapshot
        let locale = NFAppLocalization.preferredLocale
        let fieldNames = sortedFields.map(\.title).joined(separator: ", ")
        let goalNames = sortedGoals.map(\.title).joined(separator: ", ")
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let generatedAt = dateFormatter.string(from: Date())
        let storageMode = profile.iCloudEnabled
            ? NFAppLocalization.localized("Local first; private iCloud preference on", locale: locale, comment: "Redacted data-summary storage mode when private iCloud sync is enabled.")
            : NFAppLocalization.localized("Local only", locale: locale, comment: "Redacted data-summary storage mode when iCloud sync is disabled.")

        return [
            NFAppLocalization.localized("NeuroForge data summary", locale: locale, comment: "Title of the user-shareable redacted text summary."),
            NFAppLocalization.localized("Generated: \(generatedAt)", locale: locale, comment: "Redacted data-summary generation time; the placeholder is a locale-formatted date and time."),
            "",
            NFAppLocalization.localized("Profile stage: \(profile.stage.title)", locale: locale, comment: "Redacted data-summary profile stage; the placeholder is the localized stage name."),
            NFAppLocalization.localized("STEM fields: \(fieldNames)", locale: locale, comment: "Redacted data-summary selected STEM fields; the placeholder is a localized field list."),
            NFAppLocalization.localized("Training goals: \(goalNames)", locale: locale, comment: "Redacted data-summary training goals; the placeholder is a localized goal list."),
            NFAppLocalization.localized(
                "Daily session: \(NFAppLocalization.formattedMinutes(profile.dailyDuration, locale: locale))",
                locale: locale,
                comment: "Redacted data-summary daily duration; the placeholder is a localized duration."
            ),
            NFAppLocalization.localized("Timing: \(profile.timingMode.title)", locale: locale, comment: "Redacted data-summary timing preference; the placeholder is the localized preference name."),
            NFAppLocalization.localized("AI mode: \(profile.aiMode.title)", locale: locale, comment: "Redacted data-summary AI preference; the placeholder is the localized preference name."),
            NFAppLocalization.localized("Storage mode: \(storageMode)", locale: locale, comment: "Redacted data-summary storage preference; the placeholder is the localized mode."),
            "",
            NFAppLocalization.localized("Stored records on this device", locale: locale, comment: "Heading in the redacted data summary."),
            NFAppLocalization.localized("Attempts: \(store.attempts.count)", locale: locale, comment: "Redacted data-summary attempt count; the placeholder is the count."),
            NFAppLocalization.localized("Reported questions: \(store.itemReports.count)", locale: locale, comment: "Redacted data-summary reported-question count; the placeholder is the count."),
            NFAppLocalization.localized("Imported documents: \(store.documents.count)", locale: locale, comment: "Redacted data-summary imported-document count; the placeholder is the count."),
            "",
            NFAppLocalization.localized("This summary intentionally excludes answers, prompts, filenames, and document content.", locale: locale, comment: "Privacy note at the end of the redacted data summary.")
        ].joined(separator: "\n")
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        return switch (version, build) {
        case let (version?, build?): "\(version) (\(build))"
        case let (version?, nil): version
        default: "1.0"
        }
    }

    private func resolvePendingSubroute(using scrollProxy: ScrollViewProxy) {
        guard let subroute = store.pendingSettingsSubroute else { return }
        switch subroute {
        case .export:
            Task { @MainActor in
                // The pending value remains durable until the destination and
                // its lazy grid have entered the hierarchy.
                await Task.yield()
                guard store.pendingSettingsSubroute == subroute else { return }
                withAnimation {
                    scrollProxy.scrollTo(NFSettingsSectionAnchor.export, anchor: .top)
                }
                store.acknowledgeSettingsSubroute(subroute)
            }
        case .methodology:
            isShowingMethodologyLibrary = true
            store.acknowledgeSettingsSubroute(subroute)
        }
    }

}

private struct NFArchiveRestorePreviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let archiveURL: URL
    let preview: NFDataArchiveRestorePreview

    @State private var selectedPolicy: NFDataArchiveRestorePolicy?
    @State private var restoreError: String?
    @State private var restoreResult: NFDataArchiveRestoreResult?
    @State private var isShowingReplaceAllConfirmation = false
    @AccessibilityFocusState private var feedbackIsFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NFSectionHeader(
                        "Restore full backup",
                        eyebrow: archiveURL.lastPathComponent,
                        subtitle: "Review this validated archive before choosing how conflicts should be handled.",
                        headingLevel: .h1
                    )

                    archiveSummary
                    recordSummary
                    warningSummary
                    conflictPolicy
                    restoreFeedback

                    if restoreResult == nil {
                        Button {
                            guard let selectedPolicy else { return }
                            if selectedPolicy == .replaceAll {
                                isShowingReplaceAllConfirmation = true
                            } else {
                                restore(using: selectedPolicy)
                            }
                        } label: {
                            Label("Restore backup", systemImage: "arrow.uturn.backward.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NFTheme.controlTint)
                        .foregroundStyle(NFTheme.controlForeground)
                        .controlSize(.large)
                        .disabled(selectedPolicy == nil)
                    }
                }
                .padding(24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(AppBackground())
            .navigationTitle("Restore backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(restoreResult == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
            .alert("Replace every restorable local record?", isPresented: $isShowingReplaceAllConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Replace all local records", role: .destructive) {
                    restore(using: .replaceAll)
                }
            } message: {
                Text("This replaces the current profile, learning history, source index, plans, notes, reports, and other restorable app records with this backup. Original imported files and private iCloud records are not recreated by the JSON backup.")
            }
        }
        .nfDesktopPresentationFrame(minWidth: 420, idealWidth: 720, minHeight: 620, idealHeight: 820)
    }

    private var archiveSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backup details")
                .font(.title2.bold())
                .accessibilityHeading(.h2)
            LabeledContent("Archive version", value: String(preview.archiveVersion))
            LabeledContent("Created", value: exportedAtTitle)
            LabeledContent("App version", value: preview.appVersion)
            LabeledContent("Incoming records", value: String(preview.incoming.total))
            LabeledContent("Conflicting records", value: String(preview.conflicts.total))
            if preview.excludedPrivateAnnotationCount > 0 {
                LabeledContent(
                    "Private notes excluded from backup",
                    value: String(preview.excludedPrivateAnnotationCount)
                )
            }
        }
        .nfCard()
    }

    private var recordSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record counts")
                .font(.title2.bold())
                .accessibilityHeading(.h2)
            ForEach(visibleCategories) { category in
                LabeledContent(NFArchiveRestoreCopy.categoryTitle(category)) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(NFAppLocalization.localized(
                            "\(preview.incoming[category]) incoming",
                            locale: NFAppLocalization.preferredLocale,
                            comment: "Archive restore preview incoming record count; the placeholder is the count."
                        ))
                        if preview.conflicts[category] > 0 {
                            Text(NFAppLocalization.localized(
                                "\(preview.conflicts[category]) conflicts",
                                locale: NFAppLocalization.preferredLocale,
                                comment: "Archive restore preview conflict count; the placeholder is the count."
                            ))
                                .foregroundStyle(NFTheme.amberForeground)
                        }
                    }
                    .font(.subheadline.monospacedDigit())
                }
            }
        }
        .nfCard()
    }

    @ViewBuilder
    private var warningSummary: some View {
        if !preview.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Before you restore")
                    .font(.title2.bold())
                    .accessibilityHeading(.h2)
                ForEach(Array(preview.warnings.enumerated()), id: \.offset) { _, warning in
                    Label {
                        Text(verbatim: warning)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(NFTheme.amberForeground)
                            .accessibilityHidden(true)
                    }
                }
            }
            .nfCard()
        }
    }

    private var conflictPolicy: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conflict policy")
                .font(.title2.bold())
                .accessibilityHeading(.h2)
            Text("Choose explicitly how this restore should handle records already on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Conflict policy", selection: $selectedPolicy) {
                Text("Choose a policy").tag(NFDataArchiveRestorePolicy?.none)
                ForEach(NFDataArchiveRestorePolicy.allCases) { policy in
                    Text(NFArchiveRestoreCopy.policyTitle(policy)).tag(Optional(policy))
                }
            }
            .pickerStyle(.menu)
            .disabled(restoreResult != nil)

            if let selectedPolicy {
                Text(NFArchiveRestoreCopy.policyDetail(selectedPolicy))
                    .font(.footnote)
                    .foregroundStyle(selectedPolicy == .replaceAll ? NFTheme.roseForeground : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .nfCard()
    }

    @ViewBuilder
    private var restoreFeedback: some View {
        if let restoreResult {
            VStack(alignment: .leading, spacing: 8) {
                Label("Backup restored", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(NFTheme.mintForeground)
                Text(NFAppLocalization.localized(
                    "\(NFAppLocalization.formattedRecordCount(restoreResult.restored.total)) restored; \(NFAppLocalization.formattedRecordCount(restoreResult.skipped.total)) skipped.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Archive restore completion with localized restored and skipped record counts."
                ))
                    .font(.subheadline.monospacedDigit())
                ForEach(Array(restoreResult.warnings.enumerated()), id: \.offset) { _, warning in
                    Text(verbatim: warning)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .nfCard()
            .accessibilityElement(children: .contain)
            .accessibilityFocused($feedbackIsFocused)
        } else if let restoreError {
            Label {
                Text(verbatim: restoreError)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(NFTheme.roseForeground)
            .nfCard()
            .accessibilityFocused($feedbackIsFocused)
        }
    }

    private var visibleCategories: [NFDataArchiveCategory] {
        NFDataArchiveCategory.allCases.filter {
            preview.incoming[$0] > 0 || preview.conflicts[$0] > 0
        }
    }

    private var exportedAtTitle: String {
        let formatter = DateFormatter()
        formatter.locale = NFAppLocalization.preferredLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: preview.exportedAt)
    }

    private func restore(using policy: NFDataArchiveRestorePolicy) {
        do {
            let result = try NFDataArchiveRestoreService.restore(
                archiveAt: archiveURL,
                into: store,
                policy: policy
            )
            restoreError = nil
            restoreResult = result
        } catch {
            restoreResult = nil
            restoreError = error.localizedDescription
        }
        feedbackIsFocused = true
    }
}

private enum NFArchiveRestoreCopy {
    static func categoryTitle(_ category: NFDataArchiveCategory) -> String {
        switch category {
        case .profile: NFAppLocalization.localized("Profile", comment: "Archive restore record category.")
        case .attempts: NFAppLocalization.localized("Attempts", comment: "Archive restore record category.")
        case .reflections: NFAppLocalization.localized("Reflections", comment: "Archive restore record category.")
        case .documents: NFAppLocalization.localized("Documents", comment: "Archive restore record category.")
        case .sourceChunks: NFAppLocalization.localized("Source excerpts", comment: "Archive restore record category.")
        case .generatedSets: NFAppLocalization.localized("Generated question sets", comment: "Archive restore record category.")
        case .checkpoints: NFAppLocalization.localized("Saved sessions", comment: "Archive restore record category.")
        case .dailyPlans: NFAppLocalization.localized("Daily plans", comment: "Archive restore record category.")
        case .calibrations: NFAppLocalization.localized("Input calibrations", comment: "Archive restore record category.")
        case .annotations: NFAppLocalization.localized("Progress notes", comment: "Archive restore record category.")
        case .weeklyMission: NFAppLocalization.localized("Weekly mission", comment: "Archive restore record category.")
        case .reassessment: NFAppLocalization.localized("Reassessment schedule", comment: "Archive restore record category.")
        case .adaptiveHistory: NFAppLocalization.localized("Adaptive explanation history", comment: "Archive restore record category.")
        case .reports: NFAppLocalization.localized("Reported items", comment: "Archive restore record category.")
        }
    }

    static func policyTitle(_ policy: NFDataArchiveRestorePolicy) -> String {
        switch policy {
        case .abortOnConflict: NFAppLocalization.localized("Restore only with no conflicts", comment: "Archive restore conflict-policy option.")
        case .keepExisting: NFAppLocalization.localized("Keep existing records", comment: "Archive restore conflict-policy option.")
        case .replaceMatching: NFAppLocalization.localized("Replace matching records", comment: "Archive restore conflict-policy option.")
        case .replaceAll: NFAppLocalization.localized("Replace all local records", comment: "Archive restore destructive conflict-policy option.")
        }
    }

    static func policyDetail(_ policy: NFDataArchiveRestorePolicy) -> String {
        switch policy {
        case .abortOnConflict:
            NFAppLocalization.localized("Make no changes if any incoming record has the same identity as a local record.", comment: "Archive restore abort-on-conflict explanation.")
        case .keepExisting:
            NFAppLocalization.localized("Keep local versions when identities match and add only records that are not already present.", comment: "Archive restore keep-existing explanation.")
        case .replaceMatching:
            NFAppLocalization.localized("Replace local records with matching identities and keep unrelated local records.", comment: "Archive restore replace-matching explanation.")
        case .replaceAll:
            NFAppLocalization.localized("Delete every restorable local app record, then install this backup. This does not delete private iCloud records or recreate original imported files.", comment: "Archive restore replace-all explanation.")
        }
    }
}

struct SettingsCard<Content: View>: View {
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String
    let content: Content

    init(
        symbol: String,
        color: Color,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.symbol = symbol
        self.color = color
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                NFIconTile(symbol: symbol, color: color)

                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(title))
                        .font(.headline)
                        .accessibilityHeading(.h2)
                    Text(LocalizedStringKey(subtitle))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nfCard()
    }
}

private struct SettingsChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.11), in: Capsule())
    }
}

struct SettingsStatusRow: View {
    let symbol: String
    let title: String
    let detail: String
    let status: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.body.weight(.semibold))
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(detail))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(LocalizedStringKey(status))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    NFSectionHeader(
                        "Privacy policy",
                        eyebrow: "Effective August 29, 2026",
                        subtitle: "How NeuroForge stores and uses your data.",
                        headingLevel: .h1
                    )

                    policySection(
                        "Data stored on this device",
                        "NeuroForge stores your profile, practice history, answers, progress notes, saved question sets, question-set configuration drafts, and imported app-managed copies. Session scratchpad content is saved for resume and completed review; it is removed when the related history or all local data is deleted."
                    )
                    policySection(
                        "Question Writer Shortcut",
                        "When enabled, NeuroForge sends a question brief to the user-owned Shortcut. ChatGPT is recommended for its Use Model action, but you can choose or edit the provider and NeuroForge cannot verify that choice. Imported sources default to Offline only. You must choose Question Writer + offline for a source before its excerpts are eligible, and NeuroForge asks again before every run. It sends at most four excerpts, no more than 1,600 characters each or 4,800 characters total. Original files remain local. Returned questions are checked on this device, and offline question writing remains available."
                    )
                    policySection(
                        "Imported documents",
                        "Selected files are copied into app-managed storage and are never executed. OCR runs on the device when you request it for a scanned PDF. The Question Writer Shortcut receives only bounded excerpts from sources you approve for that run, never the original file. A document original syncs to iCloud only when you enable sync for that document. Spotlight indexing is optional."
                    )
                    policySection(
                        "Sharing and export",
                        "NeuroForge has no advertising or analytics service and does not sell your data. Data leaves the app when you share or export it, enable iCloud sync, or approve sharing a question brief and bounded excerpts from selected sources with the Question Writer Shortcut. Private progress notes are exported only when you include them."
                    )
                    policySection(
                        "Retention and deletion",
                        "Data remains until you delete a document, delete NeuroForge data, or remove the app. Deleting an imported copy never changes the original file outside NeuroForge. You can delete this device’s data or request deletion from both iCloud and this device in Settings."
                    )
                    policySection(
                        "Educational scope",
                        "NeuroForge is an educational training tool, not an intelligence test, medical device, diagnostic service, or treatment. Results describe performance on defined in-app tasks and may not generalize to other activities."
                    )
                }
                .padding(24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(AppBackground())
            .navigationTitle("Privacy")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func policySection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(LocalizedStringKey(title))
                .font(.headline)
                .accessibilityHeading(.h2)
            Text(LocalizedStringKey(text))
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .nfCard()
    }
}

import Observation
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum NFAIStudioQuestionStylePolicy {
    static func suggestedStyles(for lab: TrainingLab) -> [NFQuestionStyle] {
        switch lab {
        case .mentalMath: [.numerical, .multipleChoice, .shortAnswer]
        case .spatial: [.spatialTransformation, .multipleChoice, .shortAnswer]
        case .quantitative: [.dataInterpretation, .numerical, .multipleChoice]
        case .scientificReasoning: [.experimentalDesign, .dataInterpretation, .multipleChoice, .shortAnswer]
        case .logicDebugging: [.debugging, .proofOrDerivation, .multipleChoice, .shortAnswer]
        case .retrieval: [.shortAnswer, .multipleChoice]
        case .transfer: [.proofOrDerivation, .multipleChoice, .dataInterpretation, .shortAnswer]
        }
    }

    static func reconciledStyle(
        current: NFQuestionStyle,
        available: [NFQuestionStyle]
    ) -> NFQuestionStyle {
        available.contains(current) ? current : (available.first ?? .shortAnswer)
    }
}

enum NFAIStudioStarterSourcePolicy {
    static func requiresImportedSource(starterSetID: String?) -> Bool {
        starterSetID == "nf.starter.general.source-study"
    }

    static func supportedStyles(starterSetID: String?) -> [NFQuestionStyle]? {
        requiresImportedSource(starterSetID: starterSetID) ? [.shortAnswer] : nil
    }
}

enum NFAIStudioSourceAuthoringPolicy {
    static let offlineSupportedStyles: [NFQuestionStyle] = [.shortAnswer]

    static func shortcutSupportedStyles(for lab: TrainingLab) -> [NFQuestionStyle] {
        NFAIStudioQuestionStylePolicy.suggestedStyles(for: lab)
            .filter(NFQuestionWriterAuthoringPolicy.supports)
    }

    static func supportsOffline(_ style: NFQuestionStyle) -> Bool {
        offlineSupportedStyles.contains(style)
    }
}

enum NFAIStudioDocumentAuthoringPolicy {
    static func allowsQuestionWriter(_ policy: DocumentAIPolicy) -> Bool {
        policy == .privateCloudAllowed
    }

    static func allowsOfflineQuestions(_ policy: DocumentAIPolicy) -> Bool {
        policy != .noAI
    }

    static func requestPolicies(
        for documentIDs: Set<UUID>,
        policiesByDocumentID: [UUID: DocumentAIPolicy]
    ) -> [DocumentAIPolicy] {
        documentIDs
            .sorted { $0.uuidString < $1.uuidString }
            .map { policiesByDocumentID[$0] ?? .noAI }
    }
}

enum NFAIStudioLocalePolicy {
    static func authoringLocaleIdentifier(profileLanguageCode: String?) -> String {
        let selected = profileLanguageCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selected, !selected.isEmpty { return selected }
        return NFAppLocalization.preferredLanguageCode
    }
}

enum NFAIStudioRelativeTimeFormatter {
    static func string(
        from date: Date,
        relativeTo now: Date = Date(),
        locale: Locale = NFAppLocalization.preferredLocale
    ) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        switch elapsed {
        case ..<45:
            return NFAppLocalization.localized("Just now", locale: locale, comment: "Stable relative time for a very recent generated question set.")
        case ..<90:
            return NFAppLocalization.localized("1 min ago", locale: locale, comment: "Stable singular-minute relative time for a generated question set.")
        case ..<3_600:
            let minutes = max(2, Int(elapsed / 60))
            return NFAppLocalization.localized("\(minutes) min ago", locale: locale, comment: "Stable whole-minute relative time for a generated question set.")
        case ..<5_400:
            return NFAppLocalization.localized("1 hr ago", locale: locale, comment: "Stable singular-hour relative time for a generated question set.")
        case ..<86_400:
            let hours = max(2, Int(elapsed / 3_600))
            return NFAppLocalization.localized("\(hours) hr ago", locale: locale, comment: "Stable whole-hour relative time for a generated question set.")
        case ..<129_600:
            return NFAppLocalization.localized("Yesterday", locale: locale, comment: "Stable relative time for a generated question set from the previous day.")
        case ..<(7 * 86_400):
            let days = max(2, Int(elapsed / 86_400))
            return NFAppLocalization.localized("\(days) days ago", locale: locale, comment: "Stable whole-day relative time for a generated question set.")
        default:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

struct NFAIStudioEditorSnapshot: Codable, Equatable, Sendable {
    let lab: TrainingLab
    let field: STEMField
    let customTopic: String
    let objective: String
    let style: NFQuestionStyle
    let difficulty: Double
    let count: Int
    let selectedDocumentIDs: Set<UUID>
    let selectedStarterSetID: String?
}

struct NFAIStudioDraftPayload: Codable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let editor: NFAIStudioEditorSnapshot
    let unsavedRequest: NFAuthoringRequest?
    let unsavedResult: NFAuthoringResult?

    init(
        editor: NFAIStudioEditorSnapshot,
        unsavedRequest: NFAuthoringRequest? = nil,
        unsavedResult: NFAuthoringResult? = nil
    ) {
        schemaVersion = Self.schemaVersion
        self.editor = editor
        self.unsavedRequest = unsavedRequest
        self.unsavedResult = unsavedResult
    }

    var hasValidUnsavedResultPair: Bool {
        switch (unsavedRequest, unsavedResult) {
        case (nil, nil): true
        case let (request?, result?):
            result.provenance.requestID == request.id
                && !result.questions.isEmpty
                && result.questions.allSatisfy(\.hasValidResponseSchema)
        case (nil, _?), (_?, nil): false
        }
    }
}

enum NFAIStudioDraftIdentity {
    static let planID = "ai-studio-draft|configuration-v1"
    static let blockID = "question-set-configuration"
    static let sessionID = UUID(uuidString: "5165BEE5-5A69-4A14-BBC3-4AF26D39C1A1")!
}

struct NFAIStudioSourceChoice: Identifiable, Equatable, Sendable {
    let id: UUID
    let filename: String
    let status: String
    let route: String
    let exclusion: String?
    var canSelect: Bool { exclusion == nil }
}

enum NFAIStudioSourceChooserProjection {
    static let pageSize = 20

    static func matching(_ choices: [NFAIStudioSourceChoice], query: String,
                         selectedOnly: Bool, selectedIDs: Set<UUID>) -> [NFAIStudioSourceChoice] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return choices.filter { choice in
            (!selectedOnly || selectedIDs.contains(choice.id))
                && terms.allSatisfy { term in
                    [choice.filename, choice.status, choice.route, choice.exclusion ?? ""]
                        .contains { $0.localizedStandardContains(term) }
                }
        }
    }

    static func toggling(_ choice: NFAIStudioSourceChoice, selectedIDs: Set<UUID>) -> Set<UUID> {
        var result = selectedIDs
        if result.contains(choice.id) { result.remove(choice.id) }
        else if choice.canSelect { result.insert(choice.id) }
        return result
    }
}

private struct NFAIStudioSourceChooser: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let choices: [NFAIStudioSourceChoice]
    @Binding var selectedIDs: Set<UUID>
    @State private var query = ""
    @State private var selectedOnly = false
    @State private var visibleCount = NFAIStudioSourceChooserProjection.pageSize
    @FocusState private var searchIsFocused: Bool

    private var matches: [NFAIStudioSourceChoice] {
        NFAIStudioSourceChooserProjection.matching(choices, query: query,
            selectedOnly: selectedOnly, selectedIDs: selectedIDs)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Search sources", text: $query)
                    .textFieldStyle(.roundedBorder).frame(minHeight: 44)
                    .focused($searchIsFocused).submitLabel(.search)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded { searchIsFocused = true })
                    .onSubmit { searchIsFocused = false }
                    .accessibilityIdentifier("ai-source-search")
                Toggle("Selected sources only", isOn: $selectedOnly)
                Text("Selected sources: \(selectedIDs.count)").font(.subheadline).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if matches.isEmpty {
                            ContentUnavailableView("No matching sources", systemImage: "doc.text.magnifyingglass",
                                description: Text("Try another search or show all sources. Your selection is unchanged."))
                            Button("Clear filters") { query = ""; selectedOnly = false }
                                .buttonStyle(.bordered)
                        } else {
                            ForEach(matches.prefix(visibleCount)) { choice in sourceRow(choice) }
                            if visibleCount < matches.count {
                                Button("Show more") { visibleCount += NFAIStudioSourceChooserProjection.pageSize }
                                    .buttonStyle(.bordered).frame(maxWidth: .infinity, minHeight: 44)
                            }
                        }
                    }
                }.scrollDismissesKeyboard(.interactively)
            }
            .padding(20)
            .navigationTitle("Choose sources")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { searchIsFocused = false; dismiss() }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let document = store.documents.first(where: { $0.id == id }) {
                    DocumentDetailView(document: document)
                } else {
                    ContentUnavailableView("Source unavailable", systemImage: "doc.questionmark",
                        description: Text("The source may have been deleted. Your saved answers remain in History."))
                }
            }
        }
        .nfDesktopPresentationFrame(minWidth: 400, idealWidth: 650, minHeight: 520, idealHeight: 760)
        .onChange(of: query) { _, _ in visibleCount = NFAIStudioSourceChooserProjection.pageSize }
        .onChange(of: selectedOnly) { _, _ in visibleCount = NFAIStudioSourceChooserProjection.pageSize }
    }

    private func sourceRow(_ choice: NFAIStudioSourceChoice) -> some View {
        let selected = selectedIDs.contains(choice.id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                selectedIDs = NFAIStudioSourceChooserProjection.toggling(choice, selectedIDs: selectedIDs)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(selected ? NFTheme.indigoForeground : .secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(choice.filename).font(.headline).fixedSize(horizontal: false, vertical: true)
                        Text(choice.status).font(.subheadline).foregroundStyle(.secondary)
                        if !choice.route.isEmpty && choice.canSelect {
                            Text(choice.route).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!choice.canSelect && !selected)
            .accessibilityLabel(choice.filename)
            .accessibilityValue([NFAppLocalization.localized(selected ? "Selected" : "Not selected", comment: "Source selection state."), choice.status, choice.route, choice.exclusion ?? ""].filter { !$0.isEmpty }.joined(separator: ". "))
            .accessibilityAddTraits(selected ? .isSelected : [])
            if let exclusion = choice.exclusion {
                Text(exclusion).font(.footnote).foregroundStyle(.secondary)
            }
            if store.documents.contains(where: { $0.id == choice.id }) {
                NavigationLink("Open source", value: choice.id).buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityLabel(Text("Open source: \(choice.filename)"))
            }
        }
        .padding(14)
        .background(selected ? NFTheme.indigo.opacity(0.08) : .primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct AIStudioView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var lab: TrainingLab = .logicDebugging
    @State private var field: STEMField = .general
    @State private var customTopic = ""
    @FocusState private var topicIsFocused: Bool
    @State private var objective = ""
    @State private var style: NFQuestionStyle = .multipleChoice
    @State private var difficulty = 0.5
    @State private var count = 5
    @State private var selectedDocumentIDs: Set<UUID> = []
    @State private var result: NFAuthoringResult?
    @State private var requestUsed: NFAuthoringRequest?
    @State private var isGenerating = false
    @State private var isCancelling = false
    @State private var generationTask: Task<Void, Never>?
    @State private var generationError: String?
    @State private var resultNeedsSave = false
    @State private var showPractice = false
    @State private var practiceUsesSavedDraft = true
    @State private var showsQuestionReview = false
    @State private var selectedStarterSetID: String?
    @State private var showsStarterCatalog = false
    @State private var showsSourceChooser = false
    @State private var showsMoreOptions = false
    @AccessibilityFocusState private var resultIsFocused: Bool
    @State private var pendingShortcutLaunch: NFShortcutAuthoringLaunch?
    @State private var shortcutTimeoutTask: Task<Void, Never>?
    @State private var showsSourceSharingConfirmation = false
    @State private var showsGenerationHistory = false
    @State private var confirmsLeavingEditor = false
    @State private var savedEditorSnapshot: NFAIStudioEditorSnapshot?
    @State private var didConfigureEditor = false
    @State private var draftSaveError: String?
    @State private var dirtyEditorRegistrationID = UUID()
    @State private var isDiscardingEditorDraft = false
    private let initialDocumentID: UUID?

    init(initialDocumentID: UUID? = nil) {
        self.initialDocumentID = initialDocumentID
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if !store.aiGenerations.isEmpty {
                                recentSetsCard
                            }
                            starterSetsCard
                            focusCard
                            materialCard
                            generateCard
                            if let result {
                                resultCard(result)
                                    .id(AIStudioScrollAnchor.result)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: result?.provenance.requestID) { _, requestID in
                        guard requestID != nil else { return }
                        withAnimation {
                            scrollProxy.scrollTo(AIStudioScrollAnchor.result, anchor: .top)
                        }
                        resultIsFocused = true
                    }
                }
            }
            .navigationTitle("Create a question set")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if hasUnsavedEditorWork {
                            confirmsLeavingEditor = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
        }
        .nfDesktopPresentationFrame(minWidth: 420, idealWidth: 920, minHeight: 620, idealHeight: 850)
        .accessibilityIdentifier("ai-studio-root")
        .nfGuardsUnsavedEditor(
            hasUnsavedEditorWork,
            title: NFAppLocalization.localized("AI Studio", comment: "Dirty-editor name used in the global navigation warning."),
            registrationID: dirtyEditorRegistrationID,
            onDiscard: { _ = removeEditorDraft(reportFailure: false) }
        )
        .task {
            guard !didConfigureEditor else { return }
            configureDefaults()
            let configuredDefaults = editorSnapshot
            restoreEditorDraftIfPresent()
            savedEditorSnapshot = configuredDefaults
            didConfigureEditor = true
            _ = try? store.purgeExpiredAIGenerationPayloads()
            await handleShortcutCallback()
        }
        .onChange(of: editorSnapshot) { _, _ in
            guard didConfigureEditor, hasUnsavedEditorWork else { return }
            _ = persistEditorDraft(reportFailure: false)
        }
        .onChange(of: resultNeedsSave) { _, needsSave in
            guard didConfigureEditor else { return }
            if needsSave {
                _ = persistEditorDraft(reportFailure: false)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active, hasUnsavedEditorWork else { return }
            _ = persistEditorDraft(reportFailure: true)
        }
        .onChange(of: lab) { _, _ in
            style = NFAIStudioQuestionStylePolicy.reconciledStyle(
                current: style,
                available: availableStyles
            )
        }
        .onChange(of: selectedDocumentIDs) { _, _ in
            style = NFAIStudioQuestionStylePolicy.reconciledStyle(
                current: style,
                available: availableStyles
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .neuroForgeShortcutAuthoringCallback)) { _ in
            Task { await handleShortcutCallback() }
        }
        .onDisappear {
            if hasUnsavedEditorWork,
               !isDiscardingEditorDraft,
               !store.dirtyEditorWasDiscarded(id: dirtyEditorRegistrationID) {
                _ = persistEditorDraft(reportFailure: false)
            }
            generationTask?.cancel()
            shortcutTimeoutTask?.cancel()
            if let pendingShortcutLaunch {
                invalidateShortcutSetup(after: .cancelled)
                Task {
                    try? await NFShortcutAuthoringRequestStore.shared.cancel(
                        requestID: pendingShortcutLaunch.requestID,
                        callbackNonce: pendingShortcutLaunch.callbackNonce
                    )
                }
            }
            pendingShortcutLaunch = nil
        }
        .sheet(isPresented: $showPractice) {
            if let practiceResult, let requestUsed {
                AIGeneratedPracticeView(
                    result: practiceResult,
                    request: requestUsed,
                    restoresProgress: false,
                    savedDraft: practiceUsesSavedDraft ? store.generatedPracticeDraft(for: practiceResult.provenance.requestID) : nil
                )
                    .environment(store)
            }
        }
        .sheet(isPresented: $showsSourceChooser) {
            NFAIStudioSourceChooser(choices: sourceChoices, selectedIDs: $selectedDocumentIDs)
                .environment(store)
        }
        .sheet(isPresented: $showsStarterCatalog) {
            NFStarterQuestionSetBrowser { starter in
                apply(starter)
                showsStarterCatalog = false
            }
        }
        .sheet(isPresented: $showsGenerationHistory) {
            AIGenerationHistoryView(
                reopen: { record, startsPractice in
                    showsGenerationHistory = false
                    reopenRecentSet(record, startPractice: startsPractice)
                },
                remove: { record in
                    try await store.withLinkedRestoreArtifactDeletion { try store.discardAIGenerationPayload(id: record.id) }
                }
            )
            .environment(store)
        }
        .confirmationDialog(
            "Leave AI Studio?",
            isPresented: $confirmsLeavingEditor,
            titleVisibility: .visible
        ) {
            Button("Keep editing", role: .cancel) {}
            Button("Save draft and close") {
                saveEditorDraftAndDismiss()
            }
            Button("Discard unsaved changes", role: .destructive) {
                closeAIStudioDiscardingChanges()
            }
        } message: {
            Text("Save keeps this question-set configuration on this device. Discard removes the current configuration draft. Saved sets and completed attempts remain in history.")
        }
        .alert("Question-set draft not saved", isPresented: Binding(
            get: { draftSaveError != nil },
            set: { if !$0 { draftSaveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(draftSaveError ?? "Your configuration remains on screen so you can retry."))
        }
        .alert("Questions could not be prepared", isPresented: Binding(
            get: { generationError != nil },
            set: { if !$0 { generationError = nil } }
        )) {
            if resultNeedsSave {
                Button("Retry saving") { retrySavingCurrentSet() }
            }
            if result == nil, canGenerate {
                Button("Try again") {
                    Task { await beginDefaultAuthoring() }
                }
                if canGenerateOffline {
                    Button("Create offline") {
                        generationTask = Task { await generate(preferShortcut: false) }
                    }
                }
            }
            if shortcutAuthoringRequested, let shortcutInstallURL {
                Button("Add or reinstall Question Writer") {
                    Task { @MainActor in
                        _ = await openExternalURL(shortcutInstallURL)
                    }
                }
            }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(generationError ?? "Try again with a narrower topic."))
        }
        .confirmationDialog(
            "Send selected excerpts to Question Writer?",
            isPresented: $showsSourceSharingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Send excerpts and create") {
                generationTask = Task {
                    await generate(preferShortcut: true, sourceConsentGranted: true)
                }
            }
            if canGenerateOffline {
                Button("Create offline instead") {
                    generationTask = Task { await generate(preferShortcut: false) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(sourceSharingConfirmationMessage)
        }
    }

    private var recentSetsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recent question sets")
                        .font(.title2.bold())
                    Text("Continue a set you created in the last seven days.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("See all") { showsGenerationHistory = true }
                    .buttonStyle(.bordered)
            }

            ForEach(recoverableGenerationRecords) { record in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        NFIconTile(
                            symbol: record.isFallback ? "gearshape.2.fill" : "wand.and.stars",
                            color: record.isFallback ? NFTheme.amber : NFTheme.rose,
                            size: 42
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recentSetTitle(record))
                                .font(.headline)
                            Text("\(NFAppLocalization.formattedQuestionCount(record.questionCount)) · \(recentSetField(record).title)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(verbatim: NFAIStudioRelativeTimeFormatter.string(from: record.createdAt))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            let attempts = attempts(for: record)
                            if !attempts.isEmpty {
                                Text(attemptSummary(attempts, questionCount: record.questionCount))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Menu {
                            Button("Remove from recent sets", role: .destructive) {
                                removeRecentSet(record)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("More actions for \(recentSetTitle(record))")
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { recentSetActions(record) }
                        VStack(alignment: .leading, spacing: 8) { recentSetActions(record) }
                    }
                }
                .padding(12)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            }
            if recoverableGenerationRecords.isEmpty {
                Text("No generated question content is currently retained. Attempt history and set metadata remain available in See all.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .nfCard()
    }

    @ViewBuilder
    private func recentSetActions(_ record: AIGenerationRecord) -> some View {
        Button(store.isGenerationSaved(record.id) ? "Saved on this device" : "Save set") {
            do { try store.saveGenerationSet(record.id) }
            catch { generationError = "We couldn't save this yet. Your answer is still here." }
        }.buttonStyle(.bordered).disabled(store.isGenerationSaved(record.id))
        Button("Review") { reopenRecentSet(record, startPractice: false) }
            .buttonStyle(.bordered)
        Button("Practice") { reopenRecentSet(record, startPractice: true) }
            .buttonStyle(.borderedProminent)
            .tint(NFTheme.controlTint(for: "indigo"))
            .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
    }

    private var recoverableGenerationRecords: [AIGenerationRecord] {
        Array(store.aiGenerations.lazy.filter {
            store.recoverAIGeneration(id: $0.id) != nil || store.generatedPracticeDraft(for: $0.id) != nil
        }.prefix(5))
    }

    private func attempts(for record: AIGenerationRecord) -> [AttemptRecord] {
        store.attempts
            .filter { $0.generationID == record.id }
            .sorted { $0.submittedAt > $1.submittedAt }
    }

    private func attemptSummary(_ attempts: [AttemptRecord], questionCount: Int) -> String {
        let matched = attempts.filter(\.isCorrect).count
        let tried = Set(attempts.map(\.itemID)).count
        return NFAppLocalization.localized(
            "\(NFAppLocalization.formattedAttemptCount(attempts.count)) · \(matched) matched · \(tried) of \(NFAppLocalization.formattedQuestionCount(questionCount)) tried",
            locale: NFAppLocalization.preferredLocale,
            comment: "Compact generated-set attempt-history summary with total attempts, matched responses, and distinct questions tried."
        )
    }

    private func recentSetTitle(_ record: AIGenerationRecord) -> String {
        let topic = record.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        return topic.isEmpty
            ? NFAppLocalization.localized("Untitled question set", locale: NFAppLocalization.preferredLocale, comment: "Fallback title for a recent generated question set without a topic.")
            : topic
    }

    private func recentSetField(_ record: AIGenerationRecord) -> STEMField {
        STEMField(rawValue: record.fieldRaw) ?? .general
    }

    private func reopenRecentSet(_ record: AIGenerationRecord, startPractice: Bool) {
        let draft = store.generatedPracticeDraft(for: record.id)
        guard let recovered = draft?.result ?? store.recoverAIGeneration(id: record.id),
              let recoveredRequest = draft?.request ?? recoveredRequest(for: record, result: recovered) else {
            generationError = NFAppLocalization.localized(
                "This question set is no longer available. Create a new set instead.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Error when a recent generated question set can no longer be recovered."
            )
            return
        }
        result = recovered
        requestUsed = recoveredRequest
        resultNeedsSave = false
        showsQuestionReview = false
        if startPractice {
            practiceUsesSavedDraft = true
            showPractice = true
        }
    }

    private func recoveredRequest(
        for record: AIGenerationRecord,
        result: NFAuthoringResult
    ) -> NFAuthoringRequest? {
        guard let first = result.questions.first else { return nil }
        let chunksByID = Dictionary(uniqueKeysWithValues: store.sourceChunks.map { ($0.id, $0.snapshot) })
        let chunks = result.provenance.sourceChunkIDs.compactMap { chunksByID[$0] }
        let documentCount = Set(chunks.map(\.documentID)).count
        return NFAuthoringRequest(
            id: result.provenance.requestID,
            capability: NFAICapability(rawValue: record.capabilityRaw)
                ?? (chunks.isEmpty ? .contextualize : .sourceGroundedPractice),
            lab: TrainingLab(rawValue: record.labRaw) ?? first.lab,
            field: STEMField(rawValue: record.fieldRaw)
                ?? first.authoritativeExercise.sourceContext.primaryField,
            customTopic: record.topic,
            learningObjective: "",
            style: first.style,
            difficulty: first.difficulty,
            count: result.questions.count,
            localeIdentifier: first.authoritativeExercise.localeIdentifier,
            seed: first.authoritativeExercise.seed,
            sourceChunks: chunks,
            documentPolicies: Array(repeating: .onDeviceOnly, count: documentCount),
            aiMode: .disabled,
            allowsShortcutAuthoring: false
        )
    }

    private func removeRecentSet(_ record: AIGenerationRecord) {
        Task { @MainActor in
            do {
                try await store.withLinkedRestoreArtifactDeletion { try store.discardAIGenerationPayload(id: record.id) }
            } catch {
                generationError = (error as? NFRestoreLinkedDeletionError)?.errorDescription
                    ?? NFAppLocalization.localized(
                        "The question set could not be removed. Try again.",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Error after removing a recoverable generated question set.")
            }
        }
    }

    private var starterSetsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Start with a question set")
                        .font(.title2.bold())
                    Text("Pick one, then adjust anything below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Browse all") { showsStarterCatalog = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(starterSets) { starter in
                        NFStarterQuestionSetButton(
                            starter: starter,
                            isSelected: selectedStarterSetID == starter.id,
                            action: { apply(starter) }
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .nfCard()
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What do you want to practice?").font(.title2.bold())
            TextField("e.g. limiting reagents, induction proofs, or graph traversal", text: $customTopic)
                .textFieldStyle(.roundedBorder)
                .focused($topicIsFocused)
                .submitLabel(.done)
                .onSubmit { topicIsFocused = false }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("What do you want to practice?")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                Picker("Reasoning lab", selection: $lab) {
                    ForEach(TrainingLab.allCases) { lab in Text(lab.title).tag(lab) }
                }.pickerStyle(.menu)
                Picker("Field", selection: $field) {
                    ForEach(STEMField.allCases) { field in Text(field.title).tag(field) }
                }.pickerStyle(.menu)
            }
            Text("\(style.title) · \(NFAppLocalization.formattedQuestionCount(count)) · \(difficultyLabel)")
                .font(.subheadline).foregroundStyle(.secondary)
            DisclosureGroup("More options", isExpanded: $showsMoreOptions) {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Question form", selection: $style) {
                        ForEach(availableStyles) { style in Text(style.title).tag(style) }
                    }.pickerStyle(.menu)
                    Stepper(NFAppLocalization.formattedQuestionCount(count), value: $count, in: 1...10)
                    TextField("Learning objective (optional)", text: $objective, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...4)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Difficulty").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(difficultyLabel).foregroundStyle(.secondary)
                        }
                        Slider(value: $difficulty, in: 0.15...0.9, step: 0.05).tint(NFTheme.rose)
                            .accessibilityLabel("Difficulty")
                            .accessibilityValue(difficultyLabel)
                    }
                }.padding(.top, 12)
            }
            .accessibilityIdentifier("ai-studio-more-options")
            if availableStyles.count < suggestedStyles.count {
                Label("Question forms are limited to those supported by the selected material.", systemImage: "checkmark.shield")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.nfCard()
    }

    private var materialCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Use your material", systemImage: "doc.text.magnifyingglass").font(.title2.bold())
            Text(store.profileSnapshot.aiMode == .automatic
                ? "Optional. Sources set to Question Writer + offline can use approved excerpts; prose sources can also create questions offline."
                : "Optional. Select sources with complete prose statements to build cited recall practice offline.")
                .font(.subheadline).foregroundStyle(.secondary)
            if store.documents.isEmpty && selectedDocumentIDs.isEmpty {
                Text("No study material ready yet.").foregroundStyle(.secondary)
                Button("Import in Sources") { store.requestDocumentImport(); dismiss() }.buttonStyle(.bordered)
            } else {
                Button { showsSourceChooser = true } label: {
                    Label(selectedDocumentIDs.isEmpty ? "Choose sources" : "Review selected sources", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered)
                .accessibilityIdentifier("ai-studio-source-chooser")
                if !selectedDocumentIDs.isEmpty {
                    Text("Selected sources: \(selectedDocumentIDs.count)").font(.subheadline.weight(.semibold))
                    ForEach(selectedDocuments.prefix(3)) { document in
                        Text(document.filename).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                    if selectedDocumentIDs.count > 3 {
                        Text("Review the full selection in the source chooser.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if !selectedSourcesAreUsable {
                        Label("Some selected sources cannot be used with this route. Review your selection.", systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(NFTheme.amberForeground)
                    }
                }
            }
        }.nfCard()
    }

    private var selectedSourcesAreUsable: Bool {
        guard selectedDocuments.count == selectedDocumentIDs.count else { return false }
        return selectedDocuments.allSatisfy { document in
            documentIsEligibleForCurrentRoute(document)
                && (shortcutAuthoringRequested || documentSupportsProseRecall(document))
        }
    }

    private var sourceChoices: [NFAIStudioSourceChoice] {
        let choices = store.documents.map { document in
            let policy = DocumentAIPolicy(rawValue: document.aiPolicyRaw) ?? .noAI
            let eligible = documentIsEligibleForCurrentRoute(document)
            let exclusion: String?
            if !NFAIStudioDocumentAuthoringPolicy.allowsOfflineQuestions(policy) {
                exclusion = NFAppLocalization.localized("Question creation is disabled for this source. Open the source to change its question privacy.", comment: "Source chooser exclusion and policy recovery.")
            } else if !documentHasReadyChunks(document) {
                exclusion = NFAppLocalization.localized("Open the source to reprocess it or review its preparation status.", comment: "Source chooser preparation recovery.")
            } else if !eligible {
                exclusion = NFAppLocalization.localized("This source has no complete prose statements for offline questions. Open it to review its content or allowed route.", comment: "Source chooser incompatible content recovery.")
            } else {
                exclusion = nil
            }
            return NFAIStudioSourceChoice(id: document.id, filename: document.filename,
                status: documentStatus(document),
                route: policy == .noAI ? "" : NFAppLocalization.localized(documentAllowsQuestionWriter(document) ? "Question Writer + offline" : "Created on this device", comment: "Allowed source question route."),
                exclusion: exclusion)
        }
        let knownIDs = Set(choices.map(\.id))
        let missing = selectedDocumentIDs.subtracting(knownIDs).map { id in
            NFAIStudioSourceChoice(id: id,
                filename: NFAppLocalization.localized("Source unavailable", comment: "Missing source selection."),
                status: NFAppLocalization.localized("The source may have been deleted. Your saved answers remain in History.", comment: "Missing source recovery."),
                route: "", exclusion: NFAppLocalization.localized("Remove this unavailable source from the selection.", comment: "Missing source selection recovery."))
        }
        return (choices + missing).sorted {
            let order = $0.filename.localizedStandardCompare($1.filename)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
    }

    private var generateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Create your set", systemImage: "wand.and.stars").font(.title2.bold())
            Label(shortcutAuthoringRequested ? "Uses Question Writer" : "Created on this device", systemImage: shortcutAuthoringRequested ? "arrow.up.forward.app" : "iphone")
                .font(.subheadline.weight(.semibold))
            Text(generationSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !selectedDocumentIDs.isEmpty {
                Label {
                    Text(shortcutAuthoringRequested
                        ? "Before the Shortcut opens, you’ll approve up to four excerpts. Original files stay on this device."
                        : "Selected material stays on this device and creates cited questions offline. To use approved excerpts with Question Writer, choose Question Writer + offline for each source in Sources.")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(NFTheme.mintForeground)
                }
                .font(.footnote)
            }
            Button {
                Task { await beginDefaultAuthoring() }
            } label: {
                HStack {
                    if isGenerating { ProgressView().controlSize(.small) }
                    Label(generateButtonTitle, systemImage: generateButtonSymbol)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(NFTheme.roseControlForeground)
                }
            }
            .buttonStyle(.borderedProminent).tint(NFTheme.roseControlTint).controlSize(.large)
            .accessibilityIdentifier("ai-studio-generate-action")
            .disabled(isGenerating || !canGenerate)
            if shortcutAuthoringRequested, let shortcutInstallURL {
                Button("Add or reinstall Question Writer") {
                    Task { @MainActor in
                        _ = await openExternalURL(shortcutInstallURL)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating)
            }
            if shortcutAuthoringRequested {
                Button {
                    generationTask = Task { await generate(preferShortcut: false) }
                } label: {
                    Text("Create offline instead").frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ai-studio-create-offline")
                .disabled(isGenerating || !canGenerateOffline)
            }
            if !canGenerate {
                Label(
                    selectedStarterRequiresSource
                        ? "Select at least one ready source for this set."
                        : "Add a topic or select at least one ready source.",
                    systemImage: "info.circle"
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if generationError != nil, NFShortcutAuthoringCallbackCenter.hasPending() {
                Button("Retry saving Shortcut result") {
                    Task { await handleShortcutCallback() }
                }
                .buttonStyle(.bordered)
            }
            if isGenerating {
                Button(isCancelling ? "Cancelling…" : "Cancel", role: .cancel) {
                    isCancelling = true
                    generationTask?.cancel()
                    if let pendingShortcutLaunch {
                        invalidateShortcutSetup(after: .cancelled)
                        Task {
                            try? await NFShortcutAuthoringRequestStore.shared.cancel(
                                requestID: pendingShortcutLaunch.requestID,
                                callbackNonce: pendingShortcutLaunch.callbackNonce
                            )
                        }
                    }
                    self.pendingShortcutLaunch = nil
                    shortcutTimeoutTask?.cancel()
                    shortcutTimeoutTask = nil
                    isGenerating = false
                }
                .buttonStyle(.bordered)
                .disabled(isCancelling)
                .accessibilityHint("Stops the active authoring request. You can reinstall Question Writer, try again, or create offline.")
            }
        }
        .nfCard()
    }

    private func resultCard(_ result: NFAuthoringResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                NFIconTile(symbol: result.provenance.isFallback ? "gearshape.2.fill" : "wand.and.stars", color: result.provenance.isFallback ? NFTheme.amber : NFTheme.rose)
                VStack(alignment: .leading) {
                    Text(NFAppLocalization.formattedPracticeQuestionsReady(result.questions.count)).font(.title3.bold())
                        .accessibilityHeading(.h2)
                        .accessibilityFocused($resultIsFocused)
                    Text(routeTitle(result.provenance.route))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let requestUsed,
               !requestUsed.sourceChunks.isEmpty,
               result.questions.count < requestUsed.count {
                Text(NFAppLocalization.formattedDistinctSourceQuestionSupport(result.questions.count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(store.isGenerationSaved(result.provenance.requestID) ? "Saved on this device" : "Temporary · new practice available for 7 days")
                .font(.footnote).foregroundStyle(.secondary)
            if !store.isGenerationSaved(result.provenance.requestID) && !resultNeedsSave {
                Button("Save set") {
                    do { try store.saveGenerationSet(result.provenance.requestID) }
                    catch { generationError = "We couldn't save this yet. Your answer is still here." }
                }.buttonStyle(.bordered)
            }
            if resultNeedsSave {
                Label("Save this set before starting practice.", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Retry saving") { retrySavingCurrentSet() }
                    .buttonStyle(.borderedProminent)
                    .tint(NFTheme.controlTint(for: "indigo"))
                    .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
            }
            Button(practiceResult == nil ? "No usable questions in this set" : (store.generatedPracticeDraft(for: result.provenance.requestID) == nil ? "Start practice" : "Continue session")) {
                practiceUsesSavedDraft = true
                showPractice = true
            }
            .buttonStyle(.borderedProminent)
            .tint(NFTheme.controlTint(for: "indigo"))
            .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(practiceResult == nil || resultNeedsSave || (store.recoverAIGeneration(id: result.provenance.requestID) == nil && store.generatedPracticeDraft(for: result.provenance.requestID) == nil))
            if practiceResult != nil, !resultNeedsSave, store.generatedPracticeDraft(for: result.provenance.requestID) != nil {
                Button {
                    practiceUsesSavedDraft = false
                    showPractice = true
                } label: {
                    Text("Start a new session").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.bordered)
            }
            DisclosureGroup("Review questions and reference answers", isExpanded: $showsQuestionReview) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(result.questions.enumerated()), id: \.element.id) { index, question in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Question \(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .accessibilityHeading(.h2)
                            NFFormattedLearningText(question.prompt)
                            Divider()
                            Text("Reference answer")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .accessibilityHeading(.h3)
                            NFFormattedLearningText(question.correctAnswer)
                            if !question.explanation.isEmpty {
                                Text("Explanation")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .accessibilityHeading(.h3)
                                NFFormattedLearningText(question.explanation, font: .subheadline)
                            }
                        }
                        .padding(12)
                        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.top, 8)
            }
            if practiceResult?.questions.count != result.questions.count {
                Text("Reported questions were removed from this set. Create a new set to replace them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .nfCard(cornerRadius: 22)
    }

    private var selectedDocuments: [SourceDocumentRecord] { store.documents.filter { selectedDocumentIDs.contains($0.id) } }

    private var sourceSharingConfirmationMessage: String {
        let orderedNames = selectedDocuments.map(\.filename).sorted()
        let visibleNames = orderedNames.prefix(3).joined(separator: ", ")
        let remainingCount = max(0, orderedNames.count - 3)
        let sourceList = remainingCount == 0
            ? visibleNames
            : "\(visibleNames), and \(remainingCount) more"
        return NFAppLocalization.localized(
            "Selected sources: \(sourceList). NeuroForge will choose and send at most four excerpts (1,600 characters each; 4,800 total) through your user-configured Shortcut. ChatGPT is recommended. Original files remain on this device.",
            locale: NFAppLocalization.preferredLocale,
            comment: "Per-run source-sharing confirmation; the placeholder lists the selected source filenames."
        )
    }

    private var shortcutAuthoringRequested: Bool {
        store.profileSnapshot.aiMode == .automatic
            && NFQuestionWriterAuthoringPolicy.supports(style)
            && (selectedDocumentIDs.isEmpty
                || selectedDocuments.allSatisfy(documentAllowsQuestionWriter))
    }

    private var practiceResult: NFAuthoringResult? {
        guard let result else { return nil }
        let allowed = result.questions.filter { !store.isQuarantined(question: $0, in: result) }
        guard !allowed.isEmpty else { return nil }
        return NFAuthoringResult(
            questions: allowed,
            provenance: result.provenance,
            routeCandidates: result.routeCandidates,
            validationStatus: result.validationStatus,
            validationNotes: result.validationNotes
        )
    }

    private var suggestedStyles: [NFQuestionStyle] {
        NFAIStudioQuestionStylePolicy.suggestedStyles(for: lab)
    }

    private var availableStyles: [NFQuestionStyle] {
        guard !selectedDocumentIDs.isEmpty else { return suggestedStyles }
        if store.profileSnapshot.aiMode == .automatic,
           selectedDocuments.allSatisfy(documentAllowsQuestionWriter) {
            return NFAIStudioSourceAuthoringPolicy.shortcutSupportedStyles(for: lab)
        }
        return NFAIStudioSourceAuthoringPolicy.offlineSupportedStyles
    }

    private var canGenerate: Bool {
        guard selectedSourcesAreUsable else { return false }
        if selectedStarterRequiresSource && selectedDocumentIDs.isEmpty {
            return false
        }
        if !selectedDocumentIDs.isEmpty {
            return shortcutAuthoringRequested
                ? selectedDocuments.contains(where: documentHasReadyChunks)
                : canGenerateOffline
        }
        return !customTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canGenerateOffline: Bool {
        guard selectedDocuments.count == selectedDocumentIDs.count,
              selectedDocuments.allSatisfy(documentSupportsProseRecall) else { return false }
        if selectedStarterRequiresSource && selectedDocumentIDs.isEmpty {
            return false
        }
        if !selectedDocumentIDs.isEmpty {
            return NFAIStudioSourceAuthoringPolicy.supportsOffline(style)
                && selectedDocuments.allSatisfy { document in
                    NFAIStudioDocumentAuthoringPolicy.allowsOfflineQuestions(
                        DocumentAIPolicy(rawValue: document.aiPolicyRaw) ?? .noAI
                    )
                }
                && selectedDocuments.contains(where: documentSupportsProseRecall)
        }
        return !customTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedStarterRequiresSource: Bool {
        NFAIStudioStarterSourcePolicy.requiresImportedSource(
            starterSetID: selectedStarterSetID
        )
    }

    private func documentSupportsProseRecall(_ document: SourceDocumentRecord) -> Bool {
        store.chunks(for: document).contains(where: chunkSupportsProseRecall)
    }

    private func documentHasReadyChunks(_ document: SourceDocumentRecord) -> Bool {
        !store.chunks(for: document).isEmpty
    }

    private func documentIsEligibleForCurrentRoute(_ document: SourceDocumentRecord) -> Bool {
        let policy = DocumentAIPolicy(rawValue: document.aiPolicyRaw) ?? .noAI
        guard NFAIStudioDocumentAuthoringPolicy.allowsOfflineQuestions(policy) else {
            return false
        }
        return store.profileSnapshot.aiMode == .automatic && documentAllowsQuestionWriter(document)
            ? documentHasReadyChunks(document)
            : documentSupportsProseRecall(document)
    }

    private func documentAllowsQuestionWriter(_ document: SourceDocumentRecord) -> Bool {
        NFAIStudioDocumentAuthoringPolicy.allowsQuestionWriter(
            DocumentAIPolicy(rawValue: document.aiPolicyRaw) ?? .noAI
        )
    }

    private func isCompatible(_ chunk: NFSourceChunk, with style: NFQuestionStyle) -> Bool {
        style == .shortAnswer && chunkSupportsProseRecall(chunk)
    }

    private func chunkSupportsProseRecall(_ chunk: NFSourceChunk) -> Bool {
        let tags = Set(chunk.contentTypeTags.map { $0.lowercased() })
        let language = chunk.language?.lowercased()
        guard !tags.contains("code"),
              !tags.contains("source-code"),
              !tags.contains("table"),
              !tags.contains("csv"),
              !tags.contains("equation"),
              !tags.contains("math"),
              !tags.contains("schema-summary") else { return false }
        if tags.contains("prose")
            || tags.contains("section")
            || tags.contains("plain-text")
            || tags.contains("markdown") { return true }
        return tags.isEmpty
            && (language == nil || ["text", "markdown", "en", "ja"].contains(language))
    }

    private var shortcutInstallURL: URL? {
        NFShortcutAuthoringConfiguration.installURL()
    }

    private var shortcutRouteIsLaunchable: Bool {
        shortcutInstallURL != nil
            && shortcutAuthoringRequested
    }

    private var generateButtonTitle: String {
        if isGenerating { return NFAppLocalization.localized("Creating questions…", locale: NFAppLocalization.preferredLocale, comment: "Question-set authoring active generation button title.") }
        return NFAppLocalization.localized(
            "Create \(NFAppLocalization.formattedQuestionCount(count))",
            locale: NFAppLocalization.preferredLocale,
            comment: "Question-set authoring button title with a localized question count."
        )
    }

    private var generateButtonSymbol: String {
        return shortcutRouteIsLaunchable ? "wand.and.stars" : "gearshape.2.fill"
    }

    private var generationSummary: String {
        if shortcutRouteIsLaunchable {
            return selectedDocumentIDs.isEmpty
                ? NFAppLocalization.localized("Question Writer will create a tailored set through your user-configured Shortcut. ChatGPT is recommended.", locale: NFAppLocalization.preferredLocale, comment: "Question-set authoring summary without source documents.")
                : NFAppLocalization.localized("Question Writer can use up to four excerpts you approve to create source-linked practice.", locale: NFAppLocalization.preferredLocale, comment: "Question-set authoring summary with explicitly approved source excerpts.")
        }
        return selectedDocumentIDs.isEmpty
            ? NFAppLocalization.localized("Questions are tailored locally and checked before practice begins.", locale: NFAppLocalization.preferredLocale, comment: "AI Practice Studio local generation summary without source documents.")
            : NFAppLocalization.localized("Questions cite your selected material and are checked before practice begins.", locale: NFAppLocalization.preferredLocale, comment: "AI Practice Studio local generation summary with source documents.")
    }

    private var difficultyLabel: String {
        switch difficulty {
        case ..<0.35: NFAppLocalization.localized("Foundation", locale: NFAppLocalization.preferredLocale, comment: "AI Practice Studio difficulty band.")
        case ..<0.6: NFAppLocalization.localized("Developing", locale: NFAppLocalization.preferredLocale, comment: "AI Practice Studio difficulty band.")
        case ..<0.8: NFAppLocalization.localized("Advanced", locale: NFAppLocalization.preferredLocale, comment: "AI Practice Studio difficulty band.")
        default: NFAppLocalization.localized("Expert", locale: NFAppLocalization.preferredLocale, comment: "AI Practice Studio difficulty band.")
        }
    }

    private func configureDefaults() {
        field = store.profileSnapshot.fields.sorted { $0.rawValue < $1.rawValue }.first ?? .general
        style = suggestedStyles.first ?? .multipleChoice
        if let initialDocumentID,
           store.documents.contains(where: {
               $0.id == initialDocumentID
                   && $0.chunkCount > 0
                   && documentIsEligibleForCurrentRoute($0)
           }) {
            selectedDocumentIDs.insert(initialDocumentID)
        }
    }

    private var starterSets: [NFStarterQuestionSetDescriptor] {
        NFStarterQuestionSetCatalog.recommendations(
            fields: store.profileSnapshot.fields,
            goals: store.profileSnapshot.goals,
            seed: AdaptiveEngine.fnv1a64(store.profileSnapshot.id.uuidString),
            limit: 6
        )
    }

    private func apply(_ starter: NFStarterQuestionSetDescriptor) {
        selectedStarterSetID = starter.id
        field = starter.field
        lab = starter.lab
        customTopic = starter.topic
        objective = starter.localizedLearningObjective
        style = starter.defaultStyle
        difficulty = starter.defaultDifficulty
        count = starter.defaultItemCount
    }

    @MainActor
    private func beginDefaultAuthoring() async {
        guard !isGenerating, canGenerate else { return }
        if shortcutRouteIsLaunchable && !selectedDocumentIDs.isEmpty {
            showsSourceSharingConfirmation = true
            return
        }
        generationTask = Task { await generate(preferShortcut: true) }
    }

    @MainActor
    private func generate(
        preferShortcut: Bool,
        sourceConsentGranted: Bool = false
    ) async {
        guard selectedDocuments.allSatisfy({ document in
            NFAIStudioDocumentAuthoringPolicy.allowsOfflineQuestions(
                DocumentAIPolicy(rawValue: document.aiPolicyRaw) ?? .noAI
            )
        }) else {
            generationError = NFAppLocalization.localized(
                "A selected source is set to Source review only. Change its Question privacy setting before creating questions.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Question-set authoring error when a selected source disables every authoring route."
            )
            return
        }
        let shouldLaunchShortcut = preferShortcut
            && shortcutRouteIsLaunchable
            && (selectedDocumentIDs.isEmpty || sourceConsentGranted)
        isGenerating = true
        isCancelling = false
        var isWaitingForShortcut = false
        defer {
            if !isWaitingForShortcut {
                isGenerating = false
                isCancelling = false
                generationTask = nil
            }
        }
        let query = [customTopic, objective, lab.subtitle, field.title].filter { !$0.isEmpty }.joined(separator: " ")
        let allChunks = selectedDocuments.flatMap { store.chunks(for: $0) }
        let compatibleChunks = shouldLaunchShortcut
            ? allChunks
            : allChunks.filter { isCompatible($0, with: style) }
        let retrieved = NFSourceRetriever.retrieve(
            query: query,
            from: compatibleChunks,
            limit: shouldLaunchShortcut
                ? NFShortcutSourceContextPolicy.maximumExcerptCount
                : 8
        )
        if !selectedDocumentIDs.isEmpty && retrieved.isEmpty {
            generationError = shouldLaunchShortcut
                ? NFAppLocalization.localized(
                    "No usable excerpts were found in the selected source. Choose another ready source and try again.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Question-set authoring error when selected documents yield no excerpt for Question Writer."
                )
                : NFAppLocalization.localized(
                    "No complete prose statements were found in the selected source. Choose a prose source and try again.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Question-set authoring error when selected documents yield no compatible prose excerpts."
                )
            return
        }
        let selectedPoliciesByDocumentID = Dictionary(
            uniqueKeysWithValues: selectedDocuments.map { document in
                (
                    document.id,
                    DocumentAIPolicy(rawValue: document.aiPolicyRaw) ?? .noAI
                )
            }
        )
        let policies = NFAIStudioDocumentAuthoringPolicy.requestPolicies(
            for: Set(retrieved.map(\.documentID)),
            policiesByDocumentID: selectedPoliciesByDocumentID
        )
        let requestID = UUID()
        let externalSourceConsent = NFExternalSourceConsent.make(
            explicitlyGranted: shouldLaunchShortcut
                && !retrieved.isEmpty
                && sourceConsentGranted,
            requestID: requestID,
            sourceChunks: retrieved
        )
        let request = NFAuthoringRequest(
            id: requestID,
            capability: retrieved.isEmpty ? (lab == .transfer ? .transferVariant : .contextualize) : .sourceGroundedPractice,
            lab: lab,
            field: field,
            customTopic: customTopic,
            learningObjective: objective,
            style: style,
            difficulty: difficulty,
            count: count,
            localeIdentifier: NFAIStudioLocalePolicy.authoringLocaleIdentifier(
                profileLanguageCode: store.profile?.preferredLanguageCode
            ),
            seed: AdaptiveEngine.fnv1a64("\(Date().timeIntervalSinceReferenceDate)|\(customTopic)|\(lab.rawValue)"),
            sourceChunks: retrieved,
            documentPolicies: policies,
            externalSourceConsent: externalSourceConsent,
            // Question Writer is the only model route. Any request that is not
            // actually handed to the installed Shortcut is deterministic.
            aiMode: shouldLaunchShortcut ? .automatic : .disabled,
            allowsShortcutAuthoring: shouldLaunchShortcut
        )

        if shouldLaunchShortcut {
            do {
                let launch = try await NFShortcutAuthoringRequestStore.shared.prepare(request)
                try Task.checkCancellation()
                pendingShortcutLaunch = launch
                requestUsed = request
                let accepted = await openExternalURL(launch.url)
                guard accepted else {
                    try? await NFShortcutAuthoringRequestStore.shared.cancel(
                        requestID: launch.requestID,
                        callbackNonce: launch.callbackNonce
                    )
                    pendingShortcutLaunch = nil
                    invalidateShortcutSetup(after: .launchDeclined)
                    generationError = NFAppLocalization.localized("Question Writer could not open. Try again or create this set offline.", locale: NFAppLocalization.preferredLocale, comment: "Question-set authoring error when the system declines the Shortcuts handoff URL.")
                    return
                }
                isWaitingForShortcut = true
                startShortcutTimeout(for: launch)
                generationTask = nil
                return
            } catch is CancellationError {
                invalidateShortcutSetup(after: .cancelled)
                return
            } catch {
                invalidateShortcutSetup(after: .failed)
                generationError = error.localizedDescription
                return
            }
        }

        let generated: NFAuthoringResult
        do {
            generated = try await NFAuthoringEngine.shared.author(request)
            try Task.checkCancellation()
        } catch is CancellationError {
            return
        } catch NFAIError.invalidOutput where !retrieved.isEmpty {
            generationError = NFAppLocalization.localized(
                "No complete questions could be made from this source. Select more prose and try again.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Question-set authoring error when selected material has no complete supported prose claim."
            )
            return
        } catch {
            generationError = "Questions could not be created. Try again or use a narrower topic."
            return
        }
        do {
            try store.saveAIGeneration(request: request, result: generated)
            resultNeedsSave = false
            showsQuestionReview = false
            result = generated
            requestUsed = request
            markEditorStateSaved()
        } catch {
            resultNeedsSave = true
            showsQuestionReview = false
            result = generated
            requestUsed = request
            generationError = "Questions were created, but their details could not be saved. Retry before beginning practice."
        }
    }

    private func retrySavingCurrentSet() {
        guard let result, let requestUsed else { return }
        do {
            try store.saveAIGeneration(request: requestUsed, result: result)
            resultNeedsSave = false
            generationError = nil
            markEditorStateSaved()
        } catch {
            resultNeedsSave = true
            generationError = NFAppLocalization.localized(
                "This set still could not be saved. Your questions remain on screen.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Question-set persistence retry failure while the generated questions remain visible."
            )
        }
    }

    @MainActor
    private func openExternalURL(_ url: URL) async -> Bool {
        #if DEBUG
        if NFUITestLaunchConfiguration.declinesExternalURLs {
            return false
        }
        #endif
        #if os(iOS)
        return await UIApplication.shared.open(url, options: [:])
        #elseif os(macOS)
        return NSWorkspace.shared.open(url)
        #else
        return false
        #endif
    }

    @MainActor
    private func invalidateShortcutSetup(
        after reason: NFShortcutAuthoringSetupInvalidationReason
    ) {
        NFShortcutAuthoringConfiguration.invalidateSetup(after: reason)
    }

    @MainActor
    private func handleShortcutCallback() async {
        var processedCallback = false
        while let callback = NFShortcutAuthoringCallbackCenter.first() {
            do {
                switch callback.kind {
                case let .success(receipt):
                    let completion = try await NFShortcutAuthoringRequestStore.shared.peekCompletion(
                        requestID: callback.requestID,
                        callbackNonce: callback.callbackNonce,
                        shortcutReceipt: receipt
                    )
                    try store.saveAIGeneration(
                        request: completion.request,
                        result: completion.result
                    )
                    try await NFShortcutAuthoringRequestStore.shared.finalizeConsume(
                        requestID: callback.requestID,
                        callbackNonce: callback.callbackNonce,
                        shortcutReceipt: receipt
                    )
                    NFShortcutAuthoringCallbackCenter.remove(
                        requestID: callback.requestID,
                        callbackNonce: callback.callbackNonce
                    )
                    requestUsed = completion.request
                    showsQuestionReview = false
                    resultNeedsSave = false
                    result = completion.result
                    generationError = nil
                    markEditorStateSaved()
                case .cancelled:
                    try await NFShortcutAuthoringRequestStore.shared.cancel(
                        requestID: callback.requestID,
                        callbackNonce: callback.callbackNonce
                    )
                    NFShortcutAuthoringCallbackCenter.remove(
                        requestID: callback.requestID,
                        callbackNonce: callback.callbackNonce
                    )
                    invalidateShortcutSetup(after: .cancelled)
                    generationError = NFAppLocalization.localized("Question Writer was cancelled. Reinstall it, try again, or create this set offline.", locale: NFAppLocalization.preferredLocale, comment: "Recoverable question-authoring error after the Question Writer Shortcut reports cancellation.")
                case let .failed(message):
                    try await NFShortcutAuthoringRequestStore.shared.cancel(
                        requestID: callback.requestID,
                        callbackNonce: callback.callbackNonce
                    )
                    NFShortcutAuthoringCallbackCenter.remove(
                        requestID: callback.requestID,
                        callbackNonce: callback.callbackNonce
                    )
                    invalidateShortcutSetup(after: .failed)
                    generationError = message.isEmpty
                        ? NFAppLocalization.localized("Question Writer did not finish. Try again or create this set offline.", locale: NFAppLocalization.preferredLocale, comment: "Question-set authoring error when the Question Writer Shortcut does not finish.")
                        : message
                }
                processedCallback = true
            } catch let error as NFShortcutAuthoringBridgeError
                where error == .requestMissing || error == .requestExpired {
                NFShortcutAuthoringCallbackCenter.remove(
                    requestID: callback.requestID,
                    callbackNonce: callback.callbackNonce
                )
                invalidateShortcutSetup(after: .failed)
                generationError = error.localizedDescription
                processedCallback = true
            } catch {
                // Keep the durable callback queued when persistence or another
                // retryable step fails, so the learner can retry without
                // asking the Shortcut to regenerate the set.
                generationError = error.localizedDescription
                shortcutTimeoutTask?.cancel()
                shortcutTimeoutTask = nil
                pendingShortcutLaunch = nil
                isGenerating = false
                isCancelling = false
                generationTask = nil
                return
            }
        }
        guard processedCallback else { return }
        shortcutTimeoutTask?.cancel()
        shortcutTimeoutTask = nil
        self.pendingShortcutLaunch = nil
        isGenerating = false
        isCancelling = false
        generationTask = nil
    }

    @MainActor
    private func startShortcutTimeout(for launch: NFShortcutAuthoringLaunch) {
        shortcutTimeoutTask?.cancel()
        shortcutTimeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(NFShortcutAuthoringRequestStore.callbackWaitTimeout))
            } catch { return }
            guard pendingShortcutLaunch?.requestID == launch.requestID else { return }
            try? await NFShortcutAuthoringRequestStore.shared.cancel(
                requestID: launch.requestID,
                callbackNonce: launch.callbackNonce
            )
            invalidateShortcutSetup(after: .timedOut)
            pendingShortcutLaunch = nil
            isGenerating = false
            isCancelling = false
            generationTask = nil
            generationError = NFAppLocalization.localized("Question Writer took too long. Try again or create this set offline.", locale: NFAppLocalization.preferredLocale, comment: "Question-set authoring timeout after waiting for the Question Writer Shortcut.")
        }
    }

    private func documentStatus(_ document: SourceDocumentRecord) -> String {
        switch document.indexState {
        case "ready": NFAppLocalization.formattedReadySectionCount(document.chunkCount)
        case "extractionFailed": NFAppLocalization.localized("Needs reprocessing · run local OCR or re-import text", locale: NFAppLocalization.preferredLocale, comment: "Study-document processing status with recovery guidance.")
        case "extracting": NFAppLocalization.localized("Preparing study material", locale: NFAppLocalization.preferredLocale, comment: "Study-document processing status.")
        default: NFAppLocalization.localized("Study material status unavailable", locale: NFAppLocalization.preferredLocale, comment: "Fallback study-document processing status.")
        }
    }

    private var editorSnapshot: NFAIStudioEditorSnapshot {
        NFAIStudioEditorSnapshot(
            lab: lab,
            field: field,
            customTopic: customTopic,
            objective: objective,
            style: style,
            difficulty: difficulty,
            count: count,
            selectedDocumentIDs: selectedDocumentIDs,
            selectedStarterSetID: selectedStarterSetID
        )
    }

    private var hasUnsavedEditorWork: Bool {
        resultNeedsSave
            || isGenerating
            || pendingShortcutLaunch != nil
            || savedEditorSnapshot.map { $0 != editorSnapshot } == true
    }

    private var editorDraftCheckpoint: SessionCheckpointRecord? {
        store.sessionCheckpoints.first {
            !$0.isComplete
                && $0.planID == NFAIStudioDraftIdentity.planID
                && $0.planBlockID == NFAIStudioDraftIdentity.blockID
        }
    }

    private func restoreEditorDraftIfPresent() {
        guard let checkpoint = editorDraftCheckpoint,
              let data = checkpoint.response.data(using: .utf8),
              let payload = try? JSONDecoder().decode(NFAIStudioDraftPayload.self, from: data),
              payload.schemaVersion == NFAIStudioDraftPayload.schemaVersion,
              payload.hasValidUnsavedResultPair else { return }
        applyEditorSnapshot(payload.editor)
        if let request = payload.unsavedRequest, let restoredResult = payload.unsavedResult {
            requestUsed = request
            result = restoredResult
            resultNeedsSave = true
            showsQuestionReview = false
        }
    }

    private func applyEditorSnapshot(_ snapshot: NFAIStudioEditorSnapshot) {
        lab = snapshot.lab
        field = snapshot.field
        customTopic = snapshot.customTopic
        objective = snapshot.objective
        difficulty = min(1, max(0, snapshot.difficulty))
        count = min(12, max(1, snapshot.count))
        selectedDocumentIDs = snapshot.selectedDocumentIDs.intersection(store.documents.map(\.id))
        selectedStarterSetID = snapshot.selectedStarterSetID
        style = NFAIStudioQuestionStylePolicy.reconciledStyle(
            current: snapshot.style,
            available: availableStyles
        )
    }

    @discardableResult
    private func persistEditorDraft(reportFailure: Bool) -> Bool {
        let unsavedRequest = resultNeedsSave ? requestUsed : nil
        let unsavedResult = resultNeedsSave ? result : nil
        let payload = NFAIStudioDraftPayload(
            editor: editorSnapshot,
            unsavedRequest: unsavedRequest,
            unsavedResult: unsavedResult
        )
        guard payload.hasValidUnsavedResultPair,
              let data = try? JSONEncoder().encode(payload),
              let response = String(data: data, encoding: .utf8) else {
            if reportFailure {
                draftSaveError = NFAppLocalization.localized(
                    "Your configuration remains on screen, but its local draft could not be prepared.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Question-set configuration draft encoding failure."
                )
            }
            return false
        }
        do {
            try store.upsertCheckpoint(
                sessionID: editorDraftCheckpoint?.sessionID ?? NFAIStudioDraftIdentity.sessionID,
                request: SessionRequest(
                    lab: lab,
                    source: .focused,
                    seed: 0,
                    evidenceClass: .documentPractice,
                    requestedItemCount: 1,
                    planID: NFAIStudioDraftIdentity.planID,
                    planBlockID: NFAIStudioDraftIdentity.blockID
                ),
                currentIndex: 0,
                itemCount: 1,
                response: response,
                scratchpad: "",
                results: []
            )
            draftSaveError = nil
            return true
        } catch {
            if reportFailure {
                draftSaveError = NFAppLocalization.localized(
                    "Your configuration remains on screen. NeuroForge could not save this draft locally yet.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Question-set configuration draft persistence failure."
                )
            }
            return false
        }
    }

    @discardableResult
    private func removeEditorDraft(reportFailure: Bool) -> Bool {
        guard let checkpoint = editorDraftCheckpoint else { return true }
        store.context.delete(checkpoint)
        do {
            try store.context.save()
            store.reload()
            draftSaveError = nil
            return true
        } catch {
            store.context.rollback()
            store.reload()
            if reportFailure {
                draftSaveError = NFAppLocalization.localized(
                    "The saved configuration draft could not be removed. AI Studio remains open.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Question-set configuration draft deletion failure."
                )
            }
            return false
        }
    }

    private func markEditorStateSaved() {
        savedEditorSnapshot = editorSnapshot
        _ = removeEditorDraft(reportFailure: false)
    }

    private func saveEditorDraftAndDismiss() {
        guard persistEditorDraft(reportFailure: true) else { return }
        generationTask?.cancel()
        shortcutTimeoutTask?.cancel()
        dismiss()
    }

    private func closeAIStudioDiscardingChanges() {
        isDiscardingEditorDraft = true
        guard removeEditorDraft(reportFailure: true) else {
            isDiscardingEditorDraft = false
            return
        }
        generationTask?.cancel()
        shortcutTimeoutTask?.cancel()
        if let pendingShortcutLaunch {
            invalidateShortcutSetup(after: .cancelled)
            Task {
                try? await NFShortcutAuthoringRequestStore.shared.cancel(
                    requestID: pendingShortcutLaunch.requestID,
                    callbackNonce: pendingShortcutLaunch.callbackNonce
                )
            }
        }
        self.pendingShortcutLaunch = nil
        dismiss()
    }

    private func routeTitle(_ route: NFAIRoute) -> String {
        switch route {
        case .privateCloudCompute: NFAppLocalization.localized("Earlier model version", locale: NFAppLocalization.preferredLocale, comment: "Compatibility label for a historical model route that is no longer available.")
        case .shortcutsAppleIntelligence: NFAppLocalization.localized("Earlier Apple Intelligence Shortcut", locale: NFAppLocalization.preferredLocale, comment: "Compatibility label for a question set created by an earlier Apple Intelligence Shortcut route.")
        case .externalShortcut: NFAppLocalization.localized("Question Writer Shortcut", locale: NFAppLocalization.preferredLocale, comment: "Question-set authoring route using the user-configured Question Writer Shortcut.")
        case .onDevice: NFAppLocalization.localized("Earlier question set", locale: NFAppLocalization.preferredLocale, comment: "Compatibility label for a restored question set created by an earlier app version.")
        case .deterministicFallback: NFAppLocalization.localized("Created offline", locale: NFAppLocalization.preferredLocale, comment: "Question-set authoring result created by the offline app rules.")
        }
    }
}

private enum AIStudioScrollAnchor: Hashable {
    case result
}

enum NFAIGenerationHistoryQuery {
    static let pageSize = 20

    static func recordMatches(
        _ record: AIGenerationRecord,
        attempts: [AttemptRecord],
        query: String,
        locale: Locale = NFAppLocalization.preferredLocale
    ) -> Bool {
        let needle = normalized(query)
        guard !needle.isEmpty else { return true }
        return metadataAndQuestionText(for: record, locale: locale).contains(needle)
            || attempts.contains { attemptText($0, locale: locale).contains(needle) }
    }

    /// If metadata or retained questions match, show every attempt for context.
    /// If only attempt text matches, show exactly those matching rows—including
    /// rows older than the first page.
    static func matchingAttempts(
        _ attempts: [AttemptRecord],
        for record: AIGenerationRecord,
        query: String,
        locale: Locale = NFAppLocalization.preferredLocale
    ) -> [AttemptRecord] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return attempts }
        if metadataAndQuestionText(for: record, locale: locale).contains(needle) { return attempts }
        return attempts.filter { attemptText($0, locale: locale).contains(needle) }
    }

    static func page(_ attempts: [AttemptRecord], visibleCount: Int) -> [AttemptRecord] {
        Array(attempts.prefix(max(0, visibleCount)))
    }

    static func advancedVisibleCount(current: Int, total: Int) -> Int {
        min(max(0, total), max(pageSize, current) + pageSize)
    }

    static func confidenceTitle(_ rawValue: String?) -> String {
        guard let rawValue else {
            return NFAppLocalization.localized("Not recorded", locale: NFAppLocalization.preferredLocale, comment: "Generated-practice attempt confidence when no confidence was recorded.")
        }
        guard let confidence = ConfidenceLevel(rawValue: rawValue) else {
            return NFAppLocalization.localized("Unavailable", locale: NFAppLocalization.preferredLocale, comment: "Generated-practice attempt confidence when a legacy value cannot be presented safely.")
        }
        return confidence.title
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

    private static func metadataAndQuestionText(
        for record: AIGenerationRecord,
        locale: Locale
    ) -> String {
        let retainedQuestionText = record.recoverableResult()?.questions.flatMap { question in
            [
                question.prompt,
                question.context,
                question.correctAnswer,
                question.explanation,
                question.hint,
                question.decisiveStep
            ] + question.choices + question.acceptedAnswers
        }.joined(separator: " ") ?? ""
        return normalized([
            record.topic,
            record.fieldRaw,
            STEMField(rawValue: record.fieldRaw)?.title ?? "",
            record.labRaw,
            TrainingLab(rawValue: record.labRaw)?.title ?? "",
            record.routeRaw,
            record.routeReason,
            dateSearchText(for: record.createdAt, locale: locale),
            retainedQuestionText
        ].joined(separator: " "))
    }

    private static func attemptText(_ attempt: AttemptRecord, locale: Locale) -> String {
        normalized([
            attempt.prompt,
            attempt.response,
            attempt.correctAnswerText,
            attempt.confidenceRaw ?? "",
            dateSearchText(for: attempt.submittedAt, locale: locale)
        ].joined(separator: " "))
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct NFAIGeneratedAttemptHistoryExport: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let attemptID: UUID
        let questionID: String
        let submittedAt: Date
        let prompt: String
        let response: String
        let referenceAnswer: String
        let matched: Bool
        let deterministicCredit: Double
        let confidence: String?
        let skipped: Bool
    }

    let schemaVersion: Int
    let generationID: UUID
    let generatedAt: Date
    let topic: String
    let attempts: [Entry]

    static func json(
        for record: AIGenerationRecord,
        attempts: [AttemptRecord]
    ) -> String? {
        let export = Self(
            schemaVersion: 1,
            generationID: record.id,
            generatedAt: record.createdAt,
            topic: record.topic,
            attempts: attempts.sorted { $0.submittedAt < $1.submittedAt }.map {
                Entry(
                    attemptID: $0.id,
                    questionID: $0.itemID,
                    submittedAt: $0.submittedAt,
                    prompt: $0.prompt,
                    response: $0.wasSkipped ? "" : $0.response,
                    referenceAnswer: $0.wasSkipped ? "" : $0.correctAnswerText,
                    matched: !$0.wasSkipped && $0.isCorrect,
                    deterministicCredit: $0.wasSkipped ? 0 : $0.deterministicCredit,
                    confidence: $0.wasSkipped ? nil : $0.confidenceRaw,
                    skipped: $0.wasSkipped
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(export) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct AIGenerationHistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let reopen: (AIGenerationRecord, Bool) -> Void
    let remove: @MainActor (AIGenerationRecord) async throws -> Void

    @State private var query = ""
    @State private var visibleSetCount = NFAIGenerationHistoryQuery.pageSize
    @State private var visibleAttemptCounts: [UUID: Int] = [:]
    @State private var pendingDeletionID: UUID?
    @State private var pendingAttemptDeletionID: UUID?
    @State private var historyError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Generated question content is retained for 7 days, subject to a limit of 64 sets and 32 MB. Set metadata and personal attempt history remain after question content expires. Search covers all retained metadata, available questions, and every saved attempt. Question content and attempt history can be exported or deleted separately; set metadata remains as provenance until all local data is deleted in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Retention")
                }

                Section("Question sets") {
                    if visibleRecords.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(visibleRecords) { record in
                        generationRow(record)
                    }
                    if filteredRecords.count > visibleRecords.count {
                        Button("Show more sets") {
                            visibleSetCount += NFAIGenerationHistoryQuery.pageSize
                        }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search date, topic, field, route, prompt, or response")
            .onChange(of: query) { _, _ in
                visibleSetCount = NFAIGenerationHistoryQuery.pageSize
                visibleAttemptCounts.removeAll()
            }
            .navigationTitle("Question-set history")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .nfDesktopPresentationFrame(minWidth: 620, idealWidth: 820, minHeight: 620, idealHeight: 820)
        .confirmationDialog(
            "Delete retained questions?",
            isPresented: Binding(
                get: { pendingDeletionID != nil },
                set: { if !$0 { pendingDeletionID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete question content", role: .destructive) {
                guard let id = pendingDeletionID,
                      let record = store.aiGenerations.first(where: { $0.id == id }) else { return }
                Task { @MainActor in
                    do {
                        try await remove(record)
                        pendingDeletionID = nil
                    } catch {
                        historyError = (error as? NFRestoreLinkedDeletionError)?.errorDescription
                            ?? NFAppLocalization.localized("The question set could not be removed. Try again.")
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingDeletionID = nil }
        } message: {
            Text("This removes reusable questions from the set and its collection memberships. Accepted unfinished sessions can still continue. Saved answers and original sources are kept.")
        }
        .confirmationDialog(
            "Delete attempt history?",
            isPresented: Binding(
                get: { pendingAttemptDeletionID != nil },
                set: { if !$0 { pendingAttemptDeletionID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete attempts", role: .destructive) {
                guard let id = pendingAttemptDeletionID else { return }
                Task { @MainActor in
                    do {
                        _ = try await store.withLinkedRestoreArtifactDeletion { try store.deleteAIGenerationAttempts(id: id) }
                        pendingAttemptDeletionID = nil
                    } catch {
                        historyError = (error as? NFRestoreLinkedDeletionError)?.errorDescription
                            ?? NFAppLocalization.localized(
                                "The attempt history could not be deleted. Try again.",
                                locale: NFAppLocalization.preferredLocale,
                                comment: "Error shown in generated-set history after attempt deletion fails.")
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingAttemptDeletionID = nil }
        } message: {
            Text("This permanently removes every saved attempt and reflection for this set from history and future exports. Retained questions and set metadata remain.")
        }
        .alert(
            "History update failed",
            isPresented: Binding(
                get: { historyError != nil },
                set: { if !$0 { historyError = nil } }
            )
        ) {
            Button("OK") { historyError = nil }
        } message: {
            Text(historyError ?? "")
        }
    }

    @ViewBuilder
    private func generationRow(_ record: AIGenerationRecord) -> some View {
        let attempts = attempts(for: record)
        let matchingAttempts = NFAIGenerationHistoryQuery.matchingAttempts(
            attempts,
            for: record,
            query: query
        )
        let visibleAttempts = NFAIGenerationHistoryQuery.page(
            matchingAttempts,
            visibleCount: visibleAttemptCounts[record.id] ?? NFAIGenerationHistoryQuery.pageSize
        )
        let result = store.recoverAIGeneration(id: record.id) ?? store.generatedPracticeDraft(for: record.id)?.result
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title(for: record)).font(.headline)
                    Text("\(NFAppLocalization.formattedQuestionCount(record.questionCount)) · \(field(for: record).title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: NFAIStudioRelativeTimeFormatter.string(from: record.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Menu {
                    if let export = exportJSON(for: record) {
                        ShareLink(item: export) {
                            Label("Export available questions", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let attemptExport = NFAIGeneratedAttemptHistoryExport.json(
                        for: record,
                        attempts: attempts
                    ), !attempts.isEmpty {
                        ShareLink(item: attemptExport) {
                            Label("Export attempt history", systemImage: "square.and.arrow.up.on.square")
                        }
                    }
                    if result != nil {
                        Button("Delete retained questions", role: .destructive) {
                            pendingDeletionID = record.id
                        }
                    }
                    if !attempts.isEmpty {
                        Button("Delete attempt history", role: .destructive) {
                            pendingAttemptDeletionID = record.id
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Actions for \(title(for: record))")
            }

            if result != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { generationActions(record, attempts: attempts) }
                    VStack(alignment: .leading, spacing: 8) { generationActions(record, attempts: attempts) }
                }
            } else {
                Label("Question content expired; attempt history remains.", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if attempts.isEmpty {
                Text("No attempts yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                DisclosureGroup(attemptSummary(attempts, questionCount: record.questionCount)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(improvementSummary(attempts))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(visibleAttempts) { attempt in
                            let presented = store.historyPresentation(for: NFReadOnlyAttemptSnapshot(attempt: attempt))
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(presented.resultTitle)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(attempt.submittedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Text(attempt.prompt).font(.subheadline).lineLimit(3)
                                if !attempt.response.isEmpty {
                                    LabeledContent("Your answer", value: presented.readableResponse(exercise: presented.source == .protectedAssessment ? nil : store.exerciseSnapshot(for: attempt.id)))
                                        .font(.caption)
                                }
                                if presented.hasObjectiveResult {
                                    Text(NFAppLocalization.localized(
                                        "\(presented.effectiveCredit.formatted(.percent.precision(.fractionLength(0)))) task credit · confidence: \(NFAIGenerationHistoryQuery.confidenceTitle(attempt.confidenceRaw))",
                                        comment: "Generated-practice attempt row with task credit and localized confidence."
                                    ))
                                    .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                        }
                        Text(
                            "Showing \(visibleAttempts.count) of \(NFAppLocalization.formattedAttemptCount(matchingAttempts.count))\(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " matching search")."
                        )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if matchingAttempts.count > visibleAttempts.count {
                            Button("Show more attempts") {
                                visibleAttemptCounts[record.id] = NFAIGenerationHistoryQuery.advancedVisibleCount(
                                    current: visibleAttempts.count,
                                    total: matchingAttempts.count
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           matchingAttempts.isEmpty {
                            Text("The set metadata or retained question content matched; no attempt row contains this search text.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func generationActions(_ record: AIGenerationRecord, attempts: [AttemptRecord]) -> some View {
        Button("Review") { reopen(record, false) }
            .buttonStyle(.bordered)
        Button(attempts.isEmpty ? "Practice" : "Resume or practice again") { reopen(record, true) }
            .buttonStyle(.borderedProminent)
            .tint(NFTheme.controlTint(for: "indigo"))
            .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
    }

    private var filteredRecords: [AIGenerationRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return store.aiGenerations }
        return store.aiGenerations.filter { record in
            NFAIGenerationHistoryQuery.recordMatches(
                record,
                attempts: attempts(for: record),
                query: needle
            )
        }
    }

    private var visibleRecords: [AIGenerationRecord] {
        Array(filteredRecords.prefix(visibleSetCount))
    }

    private func attempts(for record: AIGenerationRecord) -> [AttemptRecord] {
        store.attempts
            .filter { $0.generationID == record.id }
            .sorted { $0.submittedAt > $1.submittedAt }
    }

    private func title(for record: AIGenerationRecord) -> String {
        let topic = record.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        return topic.isEmpty
            ? NFAppLocalization.localized("Untitled question set", locale: NFAppLocalization.preferredLocale, comment: "Fallback title for a generated set in history.")
            : topic
    }

    private func field(for record: AIGenerationRecord) -> STEMField {
        STEMField(rawValue: record.fieldRaw) ?? .general
    }

    private func attemptSummary(_ attempts: [AttemptRecord], questionCount: Int) -> String {
        let matched = attempts.filter(\.isCorrect).count
        let tried = Set(attempts.map(\.itemID)).count
        return NFAppLocalization.localized(
            "\(NFAppLocalization.formattedAttemptCount(attempts.count)) · \(matched) matched · \(tried) of \(NFAppLocalization.formattedQuestionCount(questionCount)) tried",
            locale: NFAppLocalization.preferredLocale,
            comment: "Generated-set attempt history summary."
        )
    }

    private func improvementSummary(_ attempts: [AttemptRecord]) -> String {
        let chronological = attempts.sorted { $0.submittedAt < $1.submittedAt }
        let byQuestion = Dictionary(grouping: chronological, by: \.itemID)
        let retried = byQuestion.values.filter { $0.count > 1 }.count
        let improved = byQuestion.values.filter { values in
            values.first?.isCorrect == false && values.last?.isCorrect == true
        }.count
        return NFAppLocalization.localized(
            "\(NFAppLocalization.formattedQuestionCount(retried)) retried · \(improved) improved from the first to latest attempt",
            locale: NFAppLocalization.preferredLocale,
            comment: "Generated-set improvement summary comparing each question's first and latest attempt."
        )
    }

    private func exportJSON(for record: AIGenerationRecord) -> String? {
        guard let result = record.recoverableResult() else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(result) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

@MainActor
@Observable
final class AIGeneratedPracticeRuntime {
    let draftSaveGate = NFSessionDraftSaveGate()
    private(set) var result: NFAuthoringResult
    private(set) var request: NFAuthoringRequest
    private(set) var index = 0
    // 0 editable answer, 1 immutable prepared commit, 2 feedback, 3 summary,
    // 4 self-check comparison. Confidence is optional inline input.
    private let lifecycle = NFSessionLifecycleCoordinator()
    // Only the legacy private envelope/UI boundary uses numeric phase codes.
    private(set) var stage: Int {
        get {
            switch lifecycle.phase {
            case .confidence: 1
            case .feedback, .reflection: 2
            case .summary: 3
            case .selfCheckComparison: 4
            case .item: 0
            }
        }
        set {
            lifecycle.phase = switch newValue {
            case 1: .confidence
            case 2: .feedback
            case 3: .summary
            case 4: .selfCheckComparison
            default: .item
            }
        }
    }
    private(set) var traceInspection: NFTraceInspectionDraft?
    var numericValue = ""
    var numericUnit = ""
    var singleChoiceID: String?
    var multipleChoiceIDs: Set<String> = []
    var orderedStepIDs: [String] = []
    var shortText = ""
    var selfCheckRating: NFSelfCheckRating?
    var selfCheckReflection = ""
    var selfCheckReferenceRevealed = false
    var claimSelections: [String: Set<String>] = [:]
    var logicState: [String: String] = [:]
    private(set) var mathWork: NFMathWorkDraft?
    private(set) var dataInspection: NFDataInspectionDraft?
    private(set) var scienceStudy: NFScienceStudyDraft?
    private(set) var transferRelationship: NFTransferRelationshipDraft?
    var violatedRuleID: String?
    var showsCoaching = false
    private var hasRevealedCoaching = false
    var coachingHintCount: Int { runState?.nextHintIndex ?? (hasRevealedCoaching ? 1 : 0) }
    var confidence: ConfidenceLevel? {
        didSet {
            confidenceResponseIdentity = confidence == nil || unavailableReason != nil
                ? nil : responseDraftIdentity
        }
    }
    private var confidenceResponseIdentity: String?
    private(set) var correctness: [Bool] = []
    private(set) var lastScore: NFExerciseScoringResult?
    var saveError: String?
    private var pendingAttemptID: UUID?
    private(set) var runState: NFGeneratedRunState?
    private var terminalState: NFGeneratedTerminalState?
    private var terminalInventory: NFGeneratedTerminalInventory?
    private var pendingUnscored: NFGeneratedRunState.Outcome?
    private var acknowledgedRevision: Int?
    private var acknowledgedLegacyPayloadDigest: String?
    private var awaitsWriterRefresh = false
    private(set) var isDurablyPrepared = false
    #if DEBUG
    var privateCheckpointWriteFailure: ((NFGeneratedPracticeDraft) throws -> Void)?
    #endif
    private var preparedResponse: NFExerciseResponse?
    private(set) var isCommitInFlight = false
    private var pendingGeneratedSubmission: NFPendingGeneratedSubmission?
    private var pendingGeneratedAdvance: NFGeneratedAdvanceIntent?
    private var checkpointContinuation: NFGeneratedCheckpointContinuation?
    private var savedClarificationMessage: String?
    private var clarificationResponse: NFExerciseResponse?
    private var shownAt = Date()
    private var didRestoreDurableProgress = false
    private(set) var runID = UUID()
    private var activeSegmentStart: TimeInterval?
    private var accumulatedActiveDuration: TimeInterval = 0
    private(set) var isPaused = false
    private(set) var isReadOnlyRecovery = false
    private(set) var unavailableReason: String?
    private var restoredDraft: NFGeneratedPracticeDraft?
    private let writerID = UUID()
    #if DEBUG
    var receiptWriteAcknowledged: (() -> Void)?
    #endif
    private var writerRepository: NFLocalSessionRepository?
    private var retainedWriterAuthority: NFLocalWriterAuthority?
    private var activeCommandAuthority: NFLocalWriterAuthority?

    init(result: NFAuthoringResult, request: NFAuthoringRequest, draft: NFGeneratedPracticeDraft? = nil) {
        self.result = draft?.result ?? result
        self.request = draft?.request ?? request
        restoredDraft = draft
        if let draft { runID = draft.id }
        unavailableReason = draft?.unavailableReason
            ?? NFGeneratedPracticeCompatibility.unavailableReason(for: self.result)
        isReadOnlyRecovery = unavailableReason != nil
        prepareInteraction()
        if draft == nil, unavailableReason == nil {
            do {
                runState = try NFGeneratedRunState.initial(exercise: exercise)
                pendingAttemptID = runState?.current.attemptID
            } catch { unavailableReason = NFGeneratedPracticeCompatibility.unavailableMessage; isReadOnlyRecovery = true }
        }
    }

    var question: NFAuthoredQuestion { result.questions[index] }
    var exercise: NFExercise { question.authoritativeExercise }
    var isComparingSelfCheck: Bool {
        guard unavailableReason == nil, stage == 4 else { return false }
        if case .selfCheck = exercise.interaction { return true }
        return false
    }
    var hasUnsavedWork: Bool {
        guard unavailableReason == nil else { return false }
        if stage == 1 || stage == 4 { return true }
        guard stage == 0 else { return false }
        return switch exercise.interaction {
        case .numeric:
            !numericValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !numericUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .singleChoice:
            singleChoiceID != nil
        case .multipleChoice:
            !multipleChoiceIDs.isEmpty
        case let .orderedSteps(schema):
            orderedStepIDs != schema.steps.map(\.id)
        case .shortText:
            !shortText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .selfCheck:
            !selfCheckReflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .claimEvidence:
            claimSelections.values.contains { !$0.isEmpty }
        case .logicState:
            logicState.values.contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } || violatedRuleID != nil
        }
    }
    var canSubmit: Bool {
        guard !draftSaveGate.hasQueuedAction else { return false }
        guard canEditDraft || canRateSelfCheck else { return false }
        guard traceInspection.map({ $0.isValid(for: exercise) }) ?? true else { return false }
        guard unavailableReason == nil else { return false }
        if case .selfCheck = exercise.interaction {
            if stage == 4 {
                return selfCheckReferenceRevealed && selfCheckRating != nil
            }
            return !selfCheckReflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let transferRelationship, !transferRelationship.isCompatible(with: exercise, response: makeResponse()) { return false }
        if awaitsTransferRelationship { return canLockTransferRelationship }
        if awaitsScienceEvidence { return scienceEvidenceValidation?.isValid == true }
        if awaitsEstimateLock { return NFStateValueAuthority.exactNumber(logicState[NFEstimateExactContract.estimateKey] ?? "") != nil }
        return responseValidation.isValid
    }

    var responseValidation: NFExerciseResponseValidation {
        NFExerciseResponseValidator.validate(
            makeResponse(),
            for: exercise.interaction,
            localeIdentifier: exercise.localeIdentifier
        )
    }

    var clarificationMessage: String? {
        guard stage == 0, clarificationResponse == makeResponse() else { return nil }
        return savedClarificationMessage
    }

    var responseValidationMessage: String? {
        if let transferRelationship, !transferRelationship.isCompatible(with: exercise, response: makeResponse()) { return NFAppLocalization.localizedCatalogValue("This target response is too large to save. Your original text is retained; shorten it or export it before closing.", locale: NFAppLocalization.preferredLocale) }
        if awaitsTransferRelationship { return nil }
        if awaitsScienceEvidence { return scienceEvidenceValidation?.issue?.guidance }
        if awaitsEstimateLock {
            return canSubmit ? nil : NFAppLocalization.localized("Enter a numerical estimate before continuing.", locale: NFAppLocalization.preferredLocale, comment: "First-stage estimate input guidance.")
        }
        if let unavailableReason { return unavailableReason }
        if case .selfCheck = exercise.interaction {
            if stage == 4, selfCheckRating == nil {
                return NFAppLocalization.localized("Choose how closely your answer matched the reference.", locale: NFAppLocalization.preferredLocale, comment: "Authored-practice self-check guidance before choosing a match rating.")
            }
            if selfCheckReflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return NFAppLocalization.localized("Enter your answer before continuing.", locale: NFAppLocalization.preferredLocale, comment: "Authored-practice self-check guidance for an empty pre-reference response.")
            }
            return nil
        }
        return responseValidation.issue?.guidance
    }

    func submit(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.submit(store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        if awaitsTransferRelationship { _ = lockTransferRelationship(store: store); return }
        if awaitsScienceEvidence { _ = lockScienceEvidence(store: store); return }
        if awaitsEstimateLock { _ = lockEstimate(store: store); return }
        guard stage == 0, canSubmit, !isReadOnlyRecovery, !isPaused, ownsWriter else { return }
        invalidateConfidenceAfterEdit()
        stopTiming()
        if case .selfCheck = exercise.interaction {
            if !lifecycle.revealReference(canMutate: { self.ownsWriter && !self.isReadOnlyRecovery },
                expose: { self.selfCheckReferenceRevealed = $0 }, persist: { self.checkpoint(store: store) }) {
                activeSegmentStart = ProcessInfo.processInfo.systemUptime
            }
        } else { persistAttempt(store: store) }
    }

    func saveSelfCheck(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.saveSelfCheck(store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canRateSelfCheck, canSubmit else { return }
        persistAttempt(store: store)
    }

    private func persistAttempt(store: AppStore) {
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard !isReadOnlyRecovery, ownsWriter else { return }
        if let id = pendingAttemptID, store.attempts.contains(where: { $0.id == id }),
           let original = store.localSessions.archive.snapshots.first(where: { $0.attemptID == id }),
           (original.mathWork != mathWork || original.dataInspection != dataInspection || original.scienceStudy != scienceStudy || original.transferRelationship != transferRelationship) {
            unavailableReason = NFGeneratedPracticeCompatibility.unavailableMessage; isReadOnlyRecovery = true; return
        }
        let response = preparedResponse ?? makeResponse()
        let recovered: NFSessionLifecycleCoordinator.CommitIntent?
        if stage == 1 {
            guard let lastScore, let pendingAttemptID, preparedResponse == response else {
                unavailableReason = NFGeneratedPracticeCompatibility.unavailableMessage
                isReadOnlyRecovery = true
                return
            }
            recovered = .init(attemptID: pendingAttemptID, response: response, score: lastScore, confidence: confidence)
        } else { recovered = nil }
        stopTiming()
        lifecycle.commit(exercise: exercise, response: response, attemptID: pendingAttemptID,
            confidence: confidence, recoveredIntent: recovered,
            canMutate: { self.ownsWriter && !self.isReadOnlyRecovery },
            receipt: { intent in
                guard let committed = store.attempts.first(where: { $0.id == intent.attemptID }) else { return .absent }
                return self.matchesCommittedReceipt(committed, response: intent.response, score: intent.score, confidence: intent.confidence, store: store)
                    ? .matching : .conflicting
            }, allowsNewCommit: {
                guard !store.isQuarantined(question: self.question, in: self.result) else {
                    self.saveError = NFAppLocalization.localizedCatalogValue("This question was reported and is unavailable for practice. Your saved work remains readable.", locale: NFAppLocalization.preferredLocale)
                    return false
                }
                return true
            }, publishPrepared: { intent in
                self.pendingAttemptID = intent.attemptID
                self.preparedResponse = intent.response
                self.lastScore = intent.score
                self.confidence = intent.confidence
            }, persistPrepared: { self.checkpoint(store: store) },
            saveAttempt: { intent in
                try store.withSessionCommand(try self.sessionWriterCommand(), sessionID: self.runID) {
                    try store.saveAuthoredExerciseAttempt(attemptID: intent.attemptID,
                        generationID: self.result.provenance.requestID, sessionID: self.attemptSessionID, question: self.question,
                        response: intent.response, score: intent.score, confidence: intent.confidence,
                        sourceDocumentIDs: self.result.provenance.sourceDocumentIDs,
                        shownAt: self.shownAt, activeDuration: self.accumulatedActiveDuration,
                        hintCount: self.capturedSupportCount, mathWork: self.mathWork, traceInspection: self.traceInspection, dataInspection: self.dataInspection, scienceStudy: self.scienceStudy, transferRelationship: self.transferRelationship)
                    #if DEBUG
                    self.receiptWriteAcknowledged?()
                    #endif
                }
            }, acknowledge: { intent in
                let alreadyAcknowledged = self.runState?.current.outcome != nil || (self.runState == nil && self.stage == 2 && self.correctness.count > self.index)
                if intent.score.outcome != .selfReported && !alreadyAcknowledged { self.correctness.append(intent.score.isCorrect) }
                if var state = self.runState {
                    state.slots[state.slots.count - 1].outcome = intent.score.outcome == .selfReported ? .selfReported : .scored
                    self.runState = state
                }
                self.lastScore = intent.score
                self.saveError = nil
            }, persistFeedback: { self.checkpoint(store: store) },
            nonScorable: { score in
                self.saveError = nil
                if score.outcome == .invalidItem {
                    self.unavailableReason = score.feedback.explanation
                    self.isReadOnlyRecovery = true
                } else {
                    self.savedClarificationMessage = score.feedback.explanation
                    self.clarificationResponse = response
                    self.activeSegmentStart = ProcessInfo.processInfo.systemUptime
                    _ = self.checkpoint(store: store)
                }
            }, conflictingReceipt: { intent in
                if let intent {
                    do {
                        try store.withSessionCommand(try self.sessionWriterCommand(), sessionID: self.runID) {
                            try store.recordAuthoredExerciseAttemptConflict(attemptID: intent.attemptID,
                                generationID: self.result.provenance.requestID, sessionID: self.attemptSessionID, question: self.question,
                                response: intent.response, score: intent.score, confidence: intent.confidence,
                                sourceDocumentIDs: self.result.provenance.sourceDocumentIDs,
                                shownAt: self.shownAt, activeDuration: self.accumulatedActiveDuration,
                                hintCount: self.capturedSupportCount)
                        }
                    } catch {
                        self.saveError = NFAppLocalization.localizedCatalogValue("We couldn't save this yet. Your answer is still here.", locale: NFAppLocalization.preferredLocale)
                        return
                    }
                }
                self.unavailableReason = NFGeneratedPracticeCompatibility.unavailableMessage
                self.isReadOnlyRecovery = true
            }, failedSave: {
                self.saveError = NFAppLocalization.localized("Your answer remains on screen. Try saving it again.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "AI Practice Studio save error; the learner's typed answer remains visible for another save attempt.")
            })
    }

    private func matchesCommittedReceipt(_ attempt: AttemptRecord, response: NFExerciseResponse,
                                         score: NFExerciseScoringResult, confidence: ConfidenceLevel?, store: AppStore) -> Bool {
        guard let savedResponse = try? JSONDecoder().decode(NFExerciseResponse.self, from: Data(attempt.response.utf8)),
              savedResponse == response,
              store.localSessions.archive.snapshots.first(where: { $0.attemptID == attempt.id })?.exercise == exercise else { return false }
        let expectedConfidence: String? = score.outcome == .selfReported ? nil : confidence?.rawValue
        let expectedKey: String
        if case .selfCheck = exercise.interaction,
           exercise.evidenceClass == .documentPractice, !exercise.provenance.sourceDocumentIDs.isEmpty {
            expectedKey = ""
        } else { expectedKey = score.expectedAnswerSummary ?? "" }
        return attempt.generationID == result.provenance.requestID && attempt.sessionID == attemptSessionID
            && attempt.itemID == exercise.id && attempt.templateID == exercise.templateID && attempt.seed == exercise.seed
            && attempt.gameID == exercise.lab.rawValue && attempt.prompt == exercise.prompt
            && attempt.evidenceClassRaw == EvidenceClass.documentPractice.rawValue && attempt.assessmentBlockRaw == nil
            && attempt.sessionSourceRaw == SessionSource.focused.rawValue && !attempt.wasSkipped
            && attempt.scoringVersion == score.scoringVersion && attempt.isCorrect == score.isCorrect
            && attempt.deterministicCredit == score.credit && attempt.errorCode == score.errorCode
            && attempt.correctAnswerText == expectedKey && attempt.confidenceRaw == expectedConfidence
            && attempt.responseFormatRaw == response.responseFormatRaw
            && attempt.hintCount == capturedSupportCount
            && (runState == nil || (attempt.shownAt == shownAt && attempt.activeDurationSeconds == accumulatedActiveDuration))
            && store.localSessions.archive.snapshots.first(where: { $0.attemptID == attempt.id })?.mathWork == mathWork
            && store.localSessions.archive.snapshots.first(where: { $0.attemptID == attempt.id })?.traceInspection == traceInspection
            && store.localSessions.archive.snapshots.first(where: { $0.attemptID == attempt.id })?.dataInspection == dataInspection
            && store.localSessions.archive.snapshots.first(where: { $0.attemptID == attempt.id })?.scienceStudy == scienceStudy
            && store.localSessions.archive.snapshots.first(where: { $0.attemptID == attempt.id })?.transferRelationship == transferRelationship
            && attempt.sourceDocumentIDsRaw == exercise.provenance.sourceDocumentIDs.joined(separator: ",")
            && attempt.sourceChunkIDsRaw == exercise.provenance.sourceChunkIDs.joined(separator: ",")
    }

    func next(store: AppStore, expectedAttemptID: UUID? = nil) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.next(store: store, expectedAttemptID: expectedAttemptID)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard expectedAttemptID == nil || expectedAttemptID == pendingAttemptID else { return }
        guard canAdvanceFeedback else { return }
        advanceToNextSnapshot(store: store, ending: index + 1 >= result.questions.count)
    }

    func endSession(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.endSession(store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard !isReadOnlyRecovery, ownsWriter, !hasExited, !isCommitInFlight, pendingGeneratedSubmission == nil else { return }
        if stage == 1 { retryCommit(store: store); if stage == 1 || saveError != nil { return } }
        guard stage != 3 else { return }
        stopTiming()
        advanceToNextSnapshot(store: store, ending: true, learnerEnded: true)
    }

    private func advanceToNextSnapshot(store: AppStore, ending: Bool, learnerEnded: Bool = false) {
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        lifecycle.advance(command: learnerEnded ? .endSession : .next,
            canMutate: { self.ownsWriter && !self.isReadOnlyRecovery && !self.hasExited },
            persistCurrent: { self.checkpoint(store: store) },
            prepare: { () -> NFSessionLifecycleCoordinator.Advance<NFGeneratedPracticeDraft?> in
                guard let source = self.currentSnapshot(store: store) else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
                let proposal = try self.makeAdvanceDraft(source: source, ending: ending, learnerEnded: learnerEnded)
                return proposal.stage == 3 ? .summary(proposal) : .item(proposal)
            }, persist: { self.persistSnapshot($0, store: store) },
            publish: { snapshot in
                guard let snapshot else { return }
                self.saveError = nil
                if snapshot.stage != 3 {
                    self.index = snapshot.index
                    self.prepareInteraction()
                }
                self.result = snapshot.result
                self.request = snapshot.request
                self.runState = snapshot.runState
                self.terminalState = snapshot.terminalState
                self.terminalInventory = snapshot.terminalInventory
                self.pendingUnscored = snapshot.runState?.pendingUnscored ?? snapshot.pendingUnscored
                self.pendingAttemptID = snapshot.pendingAttemptID
                self.shownAt = snapshot.shownAt
                self.isDurablyPrepared = true
                if snapshot.stage == 3 { self.stopTiming() }
            }, unavailable: { self.saveError = $0 }, failedPreparation: {
                self.saveError = NFGeneratedPracticeCompatibility.unavailableMessage
            })
    }

    /// Compatibility API no longer reconstructs run ownership from set-wide
    /// history. Explicit saved drafts are the sole continuation authority.
    func restoreDurableProgress(from attempts: [AttemptRecord]) {
        didRestoreDurableProgress = true
    }

    func moveStep(from index: Int, offset: Int) {
        let destination = index + offset
        guard orderedStepIDs.indices.contains(index), orderedStepIDs.indices.contains(destination) else { return }
        orderedStepIDs.swapAt(index, destination)
    }

    private func prepareInteraction() {
        guard unavailableReason == nil else { return }
        lifecycle.resetForItem()
        mathWork = NFMathWorkPolicy.kind(for: exercise) == .estimateFirst ? .initial(for: exercise) : nil
        dataInspection = .initial(for: exercise)
        scienceStudy = .initial(for: exercise)
        transferRelationship = .initial(for: exercise)
        savedClarificationMessage = nil
        clarificationResponse = nil
        numericValue = ""
        numericUnit = ""
        singleChoiceID = nil
        multipleChoiceIDs = []
        orderedStepIDs = []
        shortText = ""
        selfCheckRating = nil
        selfCheckReflection = ""
        selfCheckReferenceRevealed = false
        claimSelections = [:]
        logicState = [:]
        violatedRuleID = nil
        showsCoaching = false
        hasRevealedCoaching = false
        traceInspection = nil
        confidence = nil
        lastScore = nil
        pendingAttemptID = nil
        pendingUnscored = nil
        preparedResponse = nil
        isDurablyPrepared = false
        shownAt = Date()
        accumulatedActiveDuration = 0
        activeSegmentStart = nil
        switch exercise.interaction {
        case let .orderedSteps(schema):
            orderedStepIDs = schema.steps.map(\.id)
        case let .claimEvidence(schema):
            claimSelections = Dictionary(uniqueKeysWithValues: schema.claims.map { ($0.id, Set<String>()) })
        case let .logicState(schema):
            logicState = Dictionary(uniqueKeysWithValues: schema.expectedFinalState.keys.map { ($0, "") })
        default:
            break
        }
    }

    var ownsWriter: Bool {
        !awaitsWriterRefresh && (writerRepository?.isWriter(activeCommandAuthority ?? retainedWriterAuthority, sessionID: runID) ?? true)
    }

    func sessionWriterCommand() throws -> NFSessionWriterCommand {
        guard !awaitsWriterRefresh, let writerRepository else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
        return try writerRepository.sessionCommand(authority: activeCommandAuthority ?? retainedWriterAuthority,
            sessionID: runID)
    }
    func releaseWriter() { writerRepository?.releaseWriter(writerID) }

    func takeOver(store: AppStore, automaticallyRetryPrepared: Bool = true) {
        guard !isReadOnlyRecovery,
              store.localSessions.takeOver(writerID, sessionID: runID, checkpoint: { [weak self, weak store] in
                  guard let self, let store else { return true }
                  self.stopTiming()
                  return self.checkpoint(store: store)
              }) else { return }
        writerRepository = store.localSessions
        retainedWriterAuthority = store.localSessions.writerAuthority(for: writerID, sessionID: runID)
        if let latest = store.generatedPracticeRuns.first(where: { $0.id == runID }) {
            restoredDraft = latest
            _ = restoreCheckpoint(store: store, automaticallyRetryPrepared: automaticallyRetryPrepared)
        } else {
            store.localSessions.releaseWriter(writerID)
            retainedWriterAuthority = nil
            saveError = NFGeneratedPracticeCompatibility.unavailableMessage
        }
    }

    var draftFingerprint: String { generatedDraftFingerprint(includePhase: true) }

    private func generatedDraftFingerprint(includePhase: Bool) -> String {
        guard unavailableReason == nil else { return "unavailable|\(request.id.uuidString)" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = (try? encoder.encode(makeResponse())) ?? Data()
        return "\(index)|\(includePhase ? String(stage) : "")|\(confidence?.rawValue ?? "")|\(showsCoaching)|\(payload.base64EncodedString())|\(((try? encoder.encode(dataInspection)) ?? Data()).base64EncodedString())"
    }

    var responseDraftIdentity: String {
        guard unavailableReason == nil else { return "unavailable" }
        return NFConfidenceResponseIdentity.value(makeResponse(), exercise: exercise)
    }

    var confidenceInvitation: Bool {
        guard !isReadOnlyRecovery else { return false }
        if case .selfCheck = exercise.interaction { return false }
        return EditorialBandEvidenceV1.confidenceInvited(sessionID: runID.uuidString.lowercased(),
            ordinaryPresentationOrdinal: index)
    }

    func chooseConfidence(_ value: ConfidenceLevel?) {
        guard canEditDraft else { return }
        confidence = value
    }

    func invalidateConfidenceAfterEdit() {
        guard stage == 0 else { return }
        if confidenceResponseIdentity != responseDraftIdentity { confidence = nil }
    }

    var codeTraceProjection: NFCodeTraceProjection? { NFCodeTraceProjection.make(exercise: exercise) }
    var capturedSupportCount: Int { coachingHintCount + (traceInspection == nil ? 0 : 1) + (dataInspection?.supportCount ?? 0) }
    func inspectCode(_ action: NFCodeTraceAction, store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.inspectCode(action, store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canEditDraft,
              let projection = codeTraceProjection else { return }
        let previous = traceInspection
        do {
            if var draft = traceInspection {
                switch action {
                case .next: draft.next(in: projection)
                case .previous: draft.previous()
                case .reset: draft.reset()
                case let .selectLine(line): draft.select(line: line, in: projection)
                case let .predict(name, value): draft.predict(variable: name, value: value, in: projection)
                }
                guard draft.isValid(for: exercise) else {
                    if case .predict = action {
                        // Keep the complete current edit for correction/export;
                        // incompatible text must not replace the durable draft.
                        traceInspection = draft
                        saveError = NFTraceInspectionDraft.oversizedPredictionMessage
                    }
                    return
                }
                traceInspection = draft
            } else {
                guard case .next = action, canSubmit else { return }
                traceInspection = try NFTraceInspectionDraft.begin(exercise: exercise, prediction: makeResponse())
            }
            guard traceInspection != previous else { return }
            if !checkpoint(store: store) {
                if case .predict = action { return } // New text remains available for Retry/export.
                traceInspection = previous
            }
        } catch { saveError = NFGeneratedPracticeCompatibility.unavailableMessage }
    }

    func toggleCoaching(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.toggleCoaching(store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard !awaitsTransferRelationship else { return }
        if runState != nil, coachingHintCount == 0 { requestHint(store: store); return }
        guard canEditDraft || canRateSelfCheck else { return }
        let previousVisibility = showsCoaching
        let previousExposure = hasRevealedCoaching
        showsCoaching.toggle()
        hasRevealedCoaching = hasRevealedCoaching || showsCoaching
        guard checkpoint(store: store) else {
            showsCoaching = previousVisibility
            hasRevealedCoaching = previousExposure
            return
        }
    }

    var submittedResponseText: String {
        if unavailableReason != nil || awaitsWriterRefresh { return recoveryResponseText ?? "" }
        return NFResponsePresentation.text(makeResponse(), exercise: exercise)
    }

    var recoveryResponseText: String? {
        // A future exercise cannot supply current option labels, keys or
        // feedback. Only its independently decodable learner response is shown.
        restoredDraft.map { NFResponsePresentation.text($0.response) }
    }

    private var activeDuration: TimeInterval {
        accumulatedActiveDuration + (activeSegmentStart.map { max(0, ProcessInfo.processInfo.systemUptime - $0) } ?? 0)
    }

    private func stopTiming() {
        accumulatedActiveDuration = activeDuration
        activeSegmentStart = nil
    }

    func pause(store: AppStore) {
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard stage != 3, !hasExited, !isPaused else { return }
        stopTiming()
        isPaused = true
        if var state = runState { state.interruptionCount += 1; runState = state }
        _ = checkpoint(store: store)
    }

    func resume() {
        guard !isReadOnlyRecovery, isDurablyPrepared, ownsWriter, !hasExited, stage != 3 else { return }
        isPaused = false
        activeSegmentStart = nil
    }

    @discardableResult func checkpoint(store: AppStore) -> Bool {
        if store.localSessions.archiveWriteVerificationNeeded, !draftSaveGate.isSaving {
            Task { @MainActor [weak self, weak store] in
                guard let self, let store else { return }; _ = await self.checkpointAsync(store: store)
            }
            return false
        }
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; _ = self.checkpoint(store: store)
        }, followsAcceptedAdvance: true) { return false }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard !hasExited else { return false }
        invalidateConfidenceAfterEdit()
        if unavailableReason == nil {
            unavailableReason = store.generatedPracticeRecoveryReason(for: result.provenance.requestID)
                ?? store.localSessions.archive.savedSets?.first(where: { $0.id == result.provenance.requestID })?.unavailableReason
        }
        if unavailableReason != nil { isReadOnlyRecovery = true }
        guard !isReadOnlyRecovery else { return true }
        if writerRepository == nil {
            writerRepository = store.localSessions
            guard store.localSessions.claimWriter(writerID, sessionID: runID, checkpoint: { [weak self, weak store] in
                guard let self, let store else { return true }
                self.stopTiming()
                self.isPaused = true
                return self.checkpoint(store: store)
            }) else { return false }
            retainedWriterAuthority = store.localSessions.writerAuthority(for: writerID, sessionID: runID)
            activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        }
        guard ownsWriter else { return false }
        if pendingAttemptID == nil { pendingAttemptID = UUID() }
        return persistSnapshot(currentSnapshot(store: store), store: store)
    }

    private func currentSnapshot(store: AppStore, stageOverride: Int? = nil,
        referenceOverride: Bool? = nil) -> NFGeneratedPracticeDraft? {
        guard pendingGeneratedSubmission == nil, pendingGeneratedAdvance == nil, !hasUnexpectedPreparedResponseEdit else { return nil }
        var state = runState
        if var value = state {
            guard let nextRevision = try? NFSessionWriterRevision.next(after: acknowledgedRevision) else { return nil }
            value.revision = nextRevision
            if !value.isTerminal { value.status = isPaused ? .suspended : .active }
            state = value
        }
        return NFGeneratedPracticeDraft(
            id: runID, ownerDeviceID: store.localSessions.ownerDeviceID,
            result: result, request: request, index: index, stage: stageOverride ?? stage,
            response: preparedResponse ?? makeResponse(), confidence: confidence,
            referenceRevealed: referenceOverride ?? selfCheckReferenceRevealed, hintRevealed: hasRevealedCoaching,
            correctness: correctness, lastScore: lastScore, scoredResponse: preparedResponse,
            pendingAttemptID: pendingAttemptID, shownAt: shownAt, activeDuration: activeDuration,
            clarificationMessage: clarificationMessage, hintExpanded: showsCoaching, mathWork: mathWork, traceInspection: traceInspection,
            dataInspection: dataInspection, scienceStudy: scienceStudy, transferRelationship: transferRelationship,
            runState: state, terminalState: terminalState, terminalInventory: terminalInventory, pendingUnscored: pendingUnscored)
    }

    private func persistSnapshot(_ snapshot: NFGeneratedPracticeDraft?, store: AppStore) -> Bool {
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard ownsWriter, !isReadOnlyRecovery else { return false }
        guard let snapshot else {
            saveError = NFGeneratedPracticeCompatibility.unavailableMessage
            return false
        }
        do {
            let command = try sessionWriterCommand()
            guard snapshot.valid else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
            #if DEBUG
            try privateCheckpointWriteFailure?(snapshot)
            #endif
            if snapshot.runState != nil {
                try store.localSessions.saveGeneratedSession(snapshot, command: command, expectedRevision: acknowledgedRevision)
            } else {
                try store.localSessions.saveLegacyGeneratedSession(snapshot, command: command,
                    expectedPayloadDigest: acknowledgedLegacyPayloadDigest)
            }
            acknowledgeSnapshot(snapshot, store: store)
            saveError = nil
            return true
        } catch {
            saveError = NFAppLocalization.localizedCatalogValue("We couldn't save this yet. Your answer is still here.", locale: NFAppLocalization.preferredLocale)
            return false
        }
    }

    private(set) var hasExited = false

    var recoveryText: String {
        guard unavailableReason == nil, !awaitsWriterRefresh else { return recoveryResponseText ?? "" }
        return [NFSessionRecoveryText.make(response: hasUnexpectedPreparedResponseEdit ? makeResponse() : preparedResponse ?? makeResponse(), exercise: exercise),
            dataInspection?.recoveryText(exercise: exercise), scienceStudy?.recoveryText(exercise: exercise), transferRelationship?.recoveryText(exercise: exercise)].compactMap { $0 }.joined(separator: "\n\n")
            + (traceInspection.map { "\n\n" + $0.recoveryText(exercise: exercise) } ?? "")
    }

    func exitDisposition(store: AppStore, saveSucceeded: Bool = false) -> NFSessionExitDisposition {
        if draftSaveGate.isSaving || pendingGeneratedSubmission != nil || pendingGeneratedAdvance != nil || hasUnexpectedPreparedResponseEdit || store.localSessions.archiveWriteVerificationNeeded { return .unacknowledged }
        // A stale read-only presentation has never accepted edits. Its original
        // payload remains retained; closing it must not manufacture a new run.
        if isReadOnlyRecovery || awaitsWriterRefresh { return .saved }
        guard var desired = currentSnapshot(store: store),
              let acknowledged = store.generatedPracticeRuns.first(where: { $0.id == runID && $0.ownerDeviceID == store.localSessions.ownerDeviceID }) else {
            return .resolve(saveSucceeded: saveSucceeded, exactAcknowledgement: false, pendingCommit: stage == 1)
        }
        desired.runState?.revision = acknowledged.runState?.revision ?? 0
        let exact = (try? NFImmutableAttemptRecordSnapshot.encoded(desired))
            == (try? NFImmutableAttemptRecordSnapshot.encoded(acknowledged))
        if desired.stage == 2, acknowledged.stage == 1,
           let id = desired.pendingAttemptID, id == acknowledged.pendingAttemptID,
           let record = store.attempts.first(where: { $0.id == id }) {
            let receiptMatches: Bool
            if let outcome = pendingUnscored {
                receiptMatches = matchesUnscoredReceipt(record, outcome: outcome, response: desired.response, store: store)
            } else if let score = desired.lastScore {
                receiptMatches = matchesCommittedReceipt(record, response: desired.response, score: score,
                    confidence: desired.confidence, store: store)
            } else { receiptMatches = false }
            // Roll back only fields that the verified immutable receipt advances.
            // Any later response, support, source or working edit still blocks close.
            desired.stage = 1
            desired.correctness = acknowledged.correctness
            if var state = desired.runState, let saved = acknowledged.runState,
               state.slots.count == saved.slots.count {
                state.slots[state.slots.count - 1].outcome = saved.current.outcome
                desired.runState = state
            }
            if receiptMatches, (try? NFImmutableAttemptRecordSnapshot.encoded(desired))
                == (try? NFImmutableAttemptRecordSnapshot.encoded(acknowledged)) { return .pendingCommit }
        }
        return .resolve(saveSucceeded: saveSucceeded, exactAcknowledgement: exact,
            pendingCommit: stage == 1)
    }

    @discardableResult
    func prepareToClose(store: AppStore) -> NFSessionExitDisposition {
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        stopTiming()
        isPaused = true
        if draftSaveGate.isSaving { _ = checkpoint(store: store); return .unacknowledged }
        let saved = checkpoint(store: store)
        let disposition = exitDisposition(store: store, saveSucceeded: saved)
        if !disposition.permitsClose, saveError == nil {
            saveError = NFAppLocalization.localizedCatalogValue("This session is open in another window.", locale: NFAppLocalization.preferredLocale)
        }
        return disposition
    }

    func finishClosing() {
        pendingGeneratedSubmission = nil
        pendingGeneratedAdvance = nil
        checkpointContinuation = nil
        hasExited = true
        stopTiming()
        saveError = nil
        releaseWriter()
    }

    func restoreCheckpoint(store: AppStore, automaticallyRetryPrepared: Bool = true) -> Bool {
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        if unavailableReason == nil {
            unavailableReason = store.generatedPracticeRecoveryReason(for: result.provenance.requestID)
                ?? store.localSessions.archive.savedSets?.first(where: { $0.id == result.provenance.requestID })?.unavailableReason
        }
        if unavailableReason != nil {
            isReadOnlyRecovery = true
            didRestoreDurableProgress = true
            activeSegmentStart = nil
            return true
        }
        guard let draft = restoredDraft, draft.valid else { return false }
        if let record = store.localSessions.archive.privateStudyRuns?.first(where: { $0.id == draft.id }) {
            guard let saved = try? JSONDecoder().decode(NFGeneratedPracticeDraft.self, from: record.payload),
                  (try? NFImmutableAttemptRecordSnapshot.encoded(saved)) == (try? NFImmutableAttemptRecordSnapshot.encoded(draft)) else {
                runID = draft.id
                writerRepository = store.localSessions
                store.localSessions.releaseWriter(writerID)
                retainedWriterAuthority = nil
                awaitsWriterRefresh = true
                saveError = NFAppLocalization.localizedCatalogValue("This session is open in another window.", locale: NFAppLocalization.preferredLocale)
                return false
            }
            acknowledgedLegacyPayloadDigest = NFReservationSnapshot.digest(record.payload)
        }
        awaitsWriterRefresh = false
        restoredDraft = nil
        didRestoreDurableProgress = true
        lifecycle.resetForItem()
        pendingGeneratedAdvance = nil
        checkpointContinuation = nil
        applyGeneratedDraftFields(draft)
        isReadOnlyRecovery = draft.ownerDeviceID != store.localSessions.ownerDeviceID
        isPaused = stage != 3
        if isPaused, var state = runState { state.interruptionCount += 1; runState = state }
        if !isReadOnlyRecovery, stage == 2 {
            let record = pendingAttemptID.flatMap { id in store.attempts.first { $0.id == id } }
            let matches: Bool
            if let record, let pendingUnscored {
                matches = matchesUnscoredReceipt(record, outcome: pendingUnscored, response: draft.response, store: store)
            } else if let record, let score = lastScore {
                matches = matchesCommittedReceipt(record, response: draft.response, score: score, confidence: confidence, store: store)
            } else { matches = false }
            if !matches { isReadOnlyRecovery = true; unavailableReason = NFGeneratedPracticeCompatibility.unavailableMessage; return true }
        }
        if !isReadOnlyRecovery {
            guard checkpoint(store: store), ownsWriter else { return true }
            if stage == 1, automaticallyRetryPrepared { retryCommit(store: store) }


        }
        return true
    }

    func retryCommit(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.retryCommit(store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard stage == 1, !isReadOnlyRecovery, ownsWriter else { return }
        if let pendingUnscored { saveUnscored(pendingUnscored, store: store) }
        else { persistAttempt(store: store) }
    }

    private func makeResponse() -> NFExerciseResponse {
        switch exercise.interaction {
        case .numeric:
            .numeric(NFNumericSubmission(value: numericValue, unit: numericUnit.isEmpty ? nil : numericUnit))
        case .singleChoice:
            .singleChoice(optionID: singleChoiceID ?? "")
        case .multipleChoice:
            .multipleChoice(optionIDs: multipleChoiceIDs.sorted())
        case .orderedSteps:
            .orderedSteps(stepIDs: orderedStepIDs)
        case .shortText:
            .shortText(shortText)
        case .selfCheck:
            .selfCheck(NFSelfCheckSubmission(
                rating: selfCheckRating ?? .notYet,
                reflection: selfCheckReflection.isEmpty ? nil : selfCheckReflection
            ))
        case .claimEvidence:
            .claimEvidence(NFClaimEvidenceSubmission(pairs: claimSelections.map {
                NFClaimEvidencePair(claimID: $0.key, evidenceIDs: $0.value.sorted())
            }))
        case .logicState:
            .logicState(NFLogicStateSubmission(
                finalState: NFMathWorkPolicy.finalState(logicState, draft: mathWork),
                violatedRuleID: violatedRuleID
            ))
        }
    }
}

enum NFAIGeneratedPracticeCommandPolicy {
    static func resolve(stage: Int, canSubmit: Bool, isPaused: Bool = false, canMutate: Bool = true) -> NFSessionCommandCapabilities {
        guard canMutate, [0, 2, 4].contains(stage) else { return .inactive }
        if isPaused { return .init(canAdvance: false, canTogglePause: true, canShowScratchpad: false) }
        switch stage {
        case 0, 4:
            return NFSessionCommandCapabilities(
                canAdvance: canSubmit,
                canTogglePause: true,
                canShowScratchpad: false
            )
        case 2:
            return NFSessionCommandCapabilities(
                canAdvance: true,
                canTogglePause: true,
                canShowScratchpad: false
            )
        default:
            return .inactive
        }
    }
}

struct AIGeneratedPracticeView: View {
    private enum AccessibleFocus: Hashable { case prompt, feedback, reference, clarification }

    private enum ResponseFocus: Hashable {
        case numericValue
        case numericUnit
        case shortText
        case selfCheck
        case logic(String)
    }

    @Environment(AppStore.self) private var store
    @Environment(NFSessionCommandBridge.self) private var sessionCommands
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var runtime: AIGeneratedPracticeRuntime
    @State private var showsConfidence = false
    @State private var showReport = false
    @State private var saveAndClosePending = false
    @FocusState private var responseFocus: ResponseFocus?
    @State private var dataPredictionFocusReset = UUID()
    @AccessibilityFocusState private var accessibleFocus: AccessibleFocus?
    @State private var lastAccessiblePresentation: String?
    @State private var hasAcknowledgedLocalSave = false
    private let restoresProgress: Bool

    private var commandCapabilities: NFSessionCommandCapabilities {
        NFAIGeneratedPracticeCommandPolicy.resolve(
            stage: runtime.stage,
            canSubmit: runtime.canSubmit, isPaused: runtime.isPaused,
            canMutate: runtime.isDurablyPrepared && runtime.ownsWriter && !runtime.isReadOnlyRecovery && !runtime.hasExited
        )
    }

    init(
        result: NFAuthoringResult,
        request: NFAuthoringRequest,
        restoresProgress: Bool = true,
        savedDraft: NFGeneratedPracticeDraft? = nil
    ) {
        _runtime = State(initialValue: AIGeneratedPracticeRuntime(result: result, request: request, draft: savedDraft))
        self.restoresProgress = restoresProgress
    }

    private var sessionPresentation: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                Group {
                    if let reason = runtime.unavailableReason {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Saved work unavailable").font(.title2.bold())
                                Text(LocalizedStringKey(reason))
                                if let response = runtime.recoveryResponseText, !response.isEmpty {
                                    Text("Your response").font(.headline)
                                    Text(response).textSelection(.enabled)
                                    ShareLink("Export recovery copy", item: runtime.recoveryText)
                                }
                            }.padding(20)
                        }
                    } else {
                        switch runtime.stage {
                        case 0, 1, 2, 4:
                            if runtime.isDurablyPrepared { questionView }
                            else {
                                VStack(spacing: 16) {
                                    ProgressView("Preparing saved question")
                                    if runtime.saveError != nil { Button("Retry saving") { hasAcknowledgedLocalSave = runtime.checkpoint(store: store) } }
                                }.padding(24).accessibilityIdentifier("ai-practice-preparing")
                            }
                        default: summaryView
                        }
                    }
                }
            }
            .navigationTitle("Question-set practice")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(runtime.unavailableReason == nil ? "Save and close" : "Close") {
                        attemptSaveAndClose()
                    }
                }
                if runtime.stage != 3, runtime.unavailableReason == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Session actions") {
                            Button(LocalizedStringKey(runtime.isPaused ? "Resume" : "Pause")) { runtime.isPaused ? runtime.resume() : runtime.pause(store: store) }
                            if let attemptID = runtime.acceptedAttemptID, runtime.canSkip { Button("Skip") { Task { await runtime.skipAsync(store: store, expectedAttemptID: attemptID) } } }
                            Button("End session") { Task { await runtime.endSessionAsync(store: store) } }
                                .disabled(runtime.stage == 1 || runtime.isReadOnlyRecovery || !runtime.ownsWriter)
                            Button("Report item") { showReport = true }
                        }
                    }
                }
            }
        }
    }

    private var observedSession: some View {
        let commandAttemptID = runtime.acceptedAttemptID
        let commandStage = runtime.stage
        return sessionPresentation
        .nfDesktopPresentationFrame(minWidth: 400, idealWidth: 760, minHeight: 600, idealHeight: 800)
        .interactiveDismissDisabled(runtime.stage != 3 || runtime.saveError != nil)
        .onAppear {
            _ = runtime.restoreCheckpoint(store: store, automaticallyRetryPrepared: false)
            hasAcknowledgedLocalSave = runtime.checkpoint(store: store)
            if runtime.stage == 1 { Task { await runtime.retryCommitAsync(store: store) } }
            showsConfidence = runtime.confidenceInvitation
            sessionCommands.activate(
                requestID: runtime.runID,
                capabilities: commandCapabilities
            )
            focusFirstResponseFieldIfNeeded()
        }
        .task(id: accessiblePresentationIdentity) {
            await focusSavedPresentation()
        }
        .onChange(of: runtime.awaitsEstimateLock) { wasWaiting, isWaiting in
            if wasWaiting, !isWaiting, !runtime.isPaused {
                responseFocus = .logic(NFEstimateExactContract.exactKey)
            }
        }
        .task(id: runtime.draftFingerprint) {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard !Task.isCancelled else { return }
            if await runtime.checkpointAsync(store: store) { hasAcknowledgedLocalSave = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { runtime.pause(store: store) }
        }
        .onDisappear {
            if !runtime.hasExited { runtime.pause(store: store) }
            runtime.releaseWriter()
            sessionCommands.deactivate(requestID: runtime.runID)
        }
        .onChange(of: runtime.stage) { _, stage in
            if stage == 0 { focusFirstResponseFieldIfNeeded() }
            else { responseFocus = nil }
            sessionCommands.update(
                requestID: runtime.runID,
                capabilities: commandCapabilities
            )
        }
        .onChange(of: runtime.clarificationMessage) { _, message in
            guard message != nil else { return }
            responseFocus = nil
            Task { @MainActor in
                await Task.yield()
                guard runtime.clarificationMessage == message, !runtime.isPaused else { return }
                accessibleFocus = .clarification
            }
        }
        .onChange(of: runtime.index) { _, _ in
            showsConfidence = runtime.confidenceInvitation
        }
        .onChange(of: runtime.responseDraftIdentity) { _, _ in
            runtime.invalidateConfidenceAfterEdit()
        }
        .onChange(of: commandCapabilities) { _, _ in
            sessionCommands.update(
                requestID: runtime.runID,
                capabilities: commandCapabilities
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .neuroForgeTogglePause)) { notification in
            guard notification.object as? UUID == runtime.runID, commandCapabilities.canTogglePause else { return }
            runtime.isPaused ? runtime.resume() : runtime.pause(store: store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .neuroForgeAdvanceUniversalSession)) { notification in
            guard notification.object as? UUID == runtime.runID,
                  commandCapabilities.canAdvance, runtime.acceptedAttemptID == commandAttemptID, runtime.stage == commandStage else { return }
            if runtime.stage == 2 {
                Task { await runtime.nextAsync(store: store) }
            } else {
                submitCurrentResponse()
            }
        }
    }

    var body: some View {
        observedSession
        .sheet(isPresented: Binding(get: { runtime.saveError != nil }, set: { if !$0 { runtime.saveError = nil } })) {
            NFSessionSaveRecoveryView(message: NFAppLocalization.localizedCatalogValue(runtime.saveError ?? "", locale: NFAppLocalization.preferredLocale),
                disposition: runtime.exitDisposition(store: store), recoveryText: runtime.recoveryText,
                retry: {
                    Task {
                        await runtime.retryCommitAsync(store: store)
                        if saveAndClosePending { attemptSaveAndClose() }
                    }
                }, close: { closeSavedSession() }, discard: { closeSavedSession() },
                keepOpen: { runtime.saveError = nil; saveAndClosePending = false })
        }
        #if os(macOS)
        .onExitCommand {
            guard !showReport, runtime.saveError == nil else { return }
            attemptSaveAndClose()
        }
        #endif
        .nfPendingSessionSave(runtime.draftSaveGate)
        .nfSessionCloseGuard(id: runtime.runID, saveGate: runtime.draftSaveGate, prepare: {
            runtime.prepareToClose(store: store).permitsClose
        }, close: { closeSavedSession() })
        .sheet(isPresented: $showReport) {
            ReportAuthoredQuestionView(question: runtime.question, result: runtime.result)
                .environment(store)
        }
    }

    private func attemptSaveAndClose() {
        saveAndClosePending = true
        if runtime.draftSaveGate.isSaving {
            _ = runtime.prepareToClose(store: store)
            Task { @MainActor in
                await runtime.draftSaveGate.waitUntilIdle()
                guard !runtime.hasExited, saveAndClosePending else { return }
                attemptSaveAndClose()
            }
            return
        }
        guard runtime.prepareToClose(store: store).permitsClose else { return }
        closeSavedSession()
    }

    private func closeSavedSession() {
        runtime.finishClosing()
        saveAndClosePending = false
        dismiss()
    }

    private var questionView: some View {
        ScrollViewReader { scroll in
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        NFStatusPill(text: runtime.question.lab.shortTitle, symbol: runtime.question.lab.symbol, color: NFTheme.rose)
                        Spacer()
                        Text("\(runtime.index + 1) / \(runtime.result.questions.count)").monospacedDigit().foregroundStyle(.secondary)
                            .accessibilityIdentifier("ai-practice-position")
                    }
                }
                if runtime.exercise.contractMetadata?.contextRole == nil || runtime.exercise.contractMetadata?.contextRole == .essentialGiven,
                   let presentation = runtime.question.presentationEnhancement {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(
                                NFAppLocalization.localized("Additional context", locale: NFAppLocalization.preferredLocale, comment: "Heading for optional compatibility context attached to a restored question."),
                                systemImage: "wand.and.stars"
                            )
                            .font(.caption.weight(.bold))
                            .accessibilityHeading(.h2)
                            Spacer()
                            if let rawLevel = presentation.scaffoldingLevel,
                               let level = NFAuthoringScaffoldingLevel(rawValue: rawLevel) {
                                Text(level.title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            }
                        }
                        NFFormattedLearningText(presentation.contextLabel, font: .subheadline)
                    }
                    .nfCard(cornerRadius: 14, padding: 12)
                } else if let context = NFMathWorkPolicy.presentationContext(exercise: runtime.exercise, draft: runtime.mathWork), !context.isEmpty {
                    NFFormattedLearningText(context, font: .subheadline)
                        .foregroundStyle(.secondary)
                }
                NFFormattedLearningText(
                    runtime.question.prompt,
                    font: .system(.title2, design: .rounded, weight: .bold)
                )
                .accessibilityHeading(.h1)
                .accessibilityIdentifier("ai-practice-prompt")
                .id("ai-practice-prompt-anchor")
                .accessibilityFocused($accessibleFocus, equals: .prompt)
                if let asset = NFRetrievalAssetContract.make(exercise: runtime.exercise) { NFRetrievalAssetStimulusView(asset: asset) }
                if runtime.exercise.contractMetadata?.spatialAssembly != nil,let value=NFSpatialAssemblyContract.make(exercise:runtime.exercise) {
                    NFSpatialDiagramView(metadata:value.representation,localeIdentifier:runtime.exercise.localeIdentifier,prefersReducedMotion:store.profile?.reducedMotion == true,
                        exercise:runtime.exercise,learningPhase:runtime.stage == 2 ? .committedFeedback:.independent)
                }
                if runtime.exercise.contractMetadata?.coordinateReasoning != nil,let value=NFCoordinateReasoningContract.make(exercise:runtime.exercise) {
                    NFSpatialDiagramView(metadata:value.representation,localeIdentifier:runtime.exercise.localeIdentifier,prefersReducedMotion:store.profile?.reducedMotion == true,
                        exercise:runtime.exercise,learningPhase:runtime.stage == 2 ? .committedFeedback:.independent)
                }
                if runtime.exercise.contractMetadata?.netFolding != nil,let net=NFNetFoldingContract.make(exercise:runtime.exercise) {
                    NFSpatialDiagramView(metadata:net.representation,localeIdentifier:runtime.exercise.localeIdentifier,prefersReducedMotion:store.profile?.reducedMotion == true,
                        exercise:runtime.exercise,learningPhase:runtime.stage == 2 ? .committedFeedback:.independent)
                }
                if let section=NFSolidSectionContract.make(exercise:runtime.exercise) {
                    NFSpatialDiagramView(metadata:section.representation,localeIdentifier:runtime.exercise.localeIdentifier,prefersReducedMotion:store.profile?.reducedMotion == true,
                        exercise:runtime.exercise,learningPhase:runtime.stage == 2 ? .committedFeedback:.independent)
                }
                if let coordinates=NFCoordinateTransformContract.make(exercise:runtime.exercise) {
                    NFSpatialDiagramView(metadata:coordinates.representation,localeIdentifier:runtime.exercise.localeIdentifier,
                        exercise:runtime.exercise,learningPhase:runtime.stage == 2 ? .committedFeedback : .independent)
                }
                if let geometry = NFSpatialStructureContract.make(exercise: runtime.exercise) {
                    NFSpatialDiagramView(metadata: geometry.representation, localeIdentifier: runtime.exercise.localeIdentifier,prefersReducedMotion:store.profile?.reducedMotion == true,
                        exercise: runtime.exercise, learningPhase: runtime.stage == 2 ? .committedFeedback : .independent)
                }
                if let trace = runtime.codeTraceProjection {
                    NFCodeTraceView(projection: trace, draft: runtime.traceInspection,
                        canInspect: runtime.canEditDraft,
                        predictionIsReady: runtime.canSubmit, perform: { action in
                            if case .predict = action { } else { responseFocus = nil }
                            runtime.inspectCode(action, store: store)
                        })
                }
                if !runtime.isReadOnlyRecovery, runtime.unavailableReason == nil, !runtime.isPaused, runtime.ownsWriter, let explanation = NFObservedProportionExplanation.make(exercise: runtime.exercise) {
                    NFDataInspectionView(data: explanation.data, controlledPointID: runtime.dataInspection?.selectedPointID,
                        onSelect: runtime.dataInspection == nil || runtime.stage != 0 ? nil : { runtime.selectDataPoint($0, store: store) },
                        highlightPointID: runtime.dataInspection?.overlayExpanded == true ? explanation.criterionPointID : nil,
                        onBeginInspection: { responseFocus = nil; dataPredictionFocusReset = UUID() })
                    if let draft = runtime.dataInspection, !runtime.isReadOnlyRecovery, runtime.stage != 2 {
                        NFDataPredictionView(draft: draft, exercise: runtime.exercise,
                            canEdit: runtime.canEditDraft,
                            setPrediction: { runtime.setDataPrediction($0) },
                            reveal: { _ = runtime.revealDataExplanation(store: store) },
                            toggleOverlay: { runtime.toggleDataExplanation(store: store) }, focusResetToken: dataPredictionFocusReset)
                    }
                }
                if runtime.isReadOnlyRecovery {
                    Label("Recovered work · read-only", systemImage: "lock")
                    Text(runtime.submittedResponseText).textSelection(.enabled)
                    Text("You can review your saved answer and start a separate new practice set.")
                } else if !runtime.ownsWriter {
                    Text("This session is open in another window.")
                    Button("Take over on this device") { Task { await runtime.takeOverAsync(store: store) } }.buttonStyle(.bordered)
                } else if runtime.isPaused {
                    Text("Session paused").font(.headline)
                    Button("Resume") { runtime.resume() }.buttonStyle(.borderedProminent)
                } else {
                    if runtime.stage == 2 { Text("Your saved answer").font(.headline) }
                    authoredResponseView.disabled(!(runtime.canEditDraft || runtime.canRateSelfCheck))
                }
                if runtime.stage == 0 && !runtime.isReadOnlyRecovery && !runtime.awaitsEstimateLock && !runtime.awaitsScienceEvidence && !runtime.awaitsTransferRelationship {
                    DisclosureGroup(isExpanded: $showsConfidence) {
                        Picker("Confidence", selection: Binding(get: { runtime.confidence }, set: { runtime.chooseConfidence($0) })) {
                            Text("Not recorded").tag(nil as ConfidenceLevel?)
                            ForEach(ConfidenceLevel.allCases) { level in Text(level.title).tag(Optional(level)) }
                        }.pickerStyle(.menu).frame(minHeight: 44)
                    } label: {
                        Text("Confidence (optional)").frame(minHeight: 44).contentShape(Rectangle())
                    }.disabled(!runtime.canEditDraft)
                }
                if runtime.stage == 1 {
                    Label("Answer waiting to finish saving", systemImage: "arrow.clockwise")
                    Button("Retry saving") { Task { await runtime.retryCommitAsync(store: store) } }.buttonStyle(.borderedProminent)
                }
                if let attemptID = runtime.acceptedAttemptID, runtime.canEditDraft && !runtime.awaitsTransferRelationship && (!runtime.activeHintLadder.isEmpty || runtime.canRevealSolution) {
                    let hintIndex = runtime.hintRequestIndex
                    Button { Task { await runtime.requestHintAsync(store: store, expectedAttemptID: attemptID, expectedHintIndex: hintIndex) } } label: {
                        Text(LocalizedStringKey(runtime.hintActionTitle)).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.bordered)
                }
                if runtime.showsCoaching {
                    ForEach(Array(runtime.visibleHints.enumerated()), id: \.offset) { _, hint in
                        NFFormattedLearningText(hint).nfCard(cornerRadius: 14, padding: 12)
                    }
                }
                if runtime.isUnscoredFeedback {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(runtime.isSolutionViewed ? "Solution viewed — no score" : "Skipped — no score").font(.title2.bold())
                            .accessibilityIdentifier("ai-practice-unscored-feedback")
                        if runtime.isSolutionViewed {
                            Text(NFResponsePresentation.expectedAnswer(for: runtime.exercise) ?? "")
                            NFFormattedLearningText(runtime.exercise.feedback.correctExplanation)
                            citationList(revealsExcerpt: true)
                        }
                    }.id("ai-practice-feedback-anchor")
                } else                 if runtime.stage == 2 {
                    feedbackContent.id("ai-practice-feedback-anchor")
                } else {
                citationList(revealsExcerpt: false)
                DisclosureGroup("How this answer is checked") {
                    Label(
                        runtime.result.validationStatus.summary,
                        systemImage: runtime.result.validationStatus.hasDeterministicAnswerAuthority ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                }
                Button(
                    runtime.awaitsTransferRelationship ? NFAppLocalization.localized("Save relationship and continue", locale: NFAppLocalization.preferredLocale, comment: "Freeze relationship before solving.") : runtime.awaitsScienceEvidence ? NFAppLocalization.localized("Save evidence and continue", locale: NFAppLocalization.preferredLocale, comment: "Save the first study stage before choosing the experiment.") : runtime.awaitsEstimateLock
                        ? NFAppLocalization.localized("Save estimate and continue", locale: NFAppLocalization.preferredLocale, comment: "Save the estimate before exact work.")
                        : runtime.isComparingSelfCheck
                        ? NFAppLocalization.localized("Save self-check", locale: NFAppLocalization.preferredLocale, comment: "Button that saves a learner's post-reference self-check rating.")
                        : NFAppLocalization.localized("Submit answer", locale: NFAppLocalization.preferredLocale, comment: "Button that submits an authored-practice answer before confidence is requested.")
                ) {
                    submitCurrentResponse()
                }
                .buttonStyle(.borderedProminent)
                .tint(NFTheme.controlTint(for: "indigo"))
                .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!runtime.canSubmit || runtime.stage == 1 || runtime.isReadOnlyRecovery || runtime.isPaused || !runtime.ownsWriter)
                .keyboardShortcut(.defaultAction)
                if let message = runtime.clarificationMessage {
                    Label {
                        Text(verbatim: NFAppLocalization.localizedCatalogValue(message, locale: NFAppLocalization.preferredLocale))
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-practice-answer-clarification")
                    .accessibilityFocused($accessibleFocus, equals: .clarification)
                }
                if let message = runtime.responseValidationMessage, !runtime.canSubmit {
                    Label {
                        Text(verbatim: message)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-practice-response-requirement")
                }
                }
            }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if runtime.stage == 2 {
                feedbackForwardAction.padding(.horizontal, 24).padding(.vertical, 12).background(.bar)
            }
        }
        .task(id: "\(runtime.runID)|\(runtime.index)|\(runtime.stage)|\(runtime.isPaused)|\(runtime.isDurablyPrepared)") {
            runtime.acknowledgePresented(store: store)
            guard hasAcknowledgedLocalSave, !runtime.isPaused else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            if runtime.stage == 2 { scroll.scrollTo("ai-practice-feedback-anchor", anchor: .top) }
            else if runtime.stage == 0 { scroll.scrollTo("ai-practice-prompt-anchor", anchor: .top) }
        }
        }
    }

    @ViewBuilder
    private var authoredResponseView: some View {
        switch runtime.exercise.interaction {
        case let .numeric(schema):
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { numericResponseFields(schema) }
                VStack(alignment: .leading, spacing: 12) { numericResponseFields(schema) }
            }

        case let .singleChoice(schema):
            choiceGrid(schema.options, multiple: false)

        case let .multipleChoice(schema):
            VStack(alignment: .leading, spacing: 10) {
                Text("Select all that apply")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                choiceGrid(schema.options, multiple: true)
            }

        case let .orderedSteps(schema):
            NFOrderedResponseEditor(schema: schema, order: $runtime.orderedStepIDs,
                isEditable: runtime.canEditDraft,
                permitsEditing: { runtime.canEditDraft })
                .id("ordered-\(runtime.runID)-\(runtime.index)")

        case let .shortText(schema):
            VStack(alignment: .trailing, spacing: 6) {
                TextField("Your answer", text: $runtime.shortText, axis: .vertical)
                    .focused($responseFocus, equals: .shortText)
                    .textFieldStyle(.plain)
                    .lineLimit(5...12)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("ai-practice-short-text-input")
                Text("\(runtime.shortText.count) / \(schema.maximumCharacters)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(runtime.shortText.count > schema.maximumCharacters ? NFTheme.roseForeground : .secondary)
                    .accessibilityLabel(NFAppLocalization.localized(
                        "\(NFAppLocalization.formattedCharacterCount(runtime.shortText.count)) of \(NFAppLocalization.formattedCharacterCount(schema.maximumCharacters))",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Short-text character usage with localized current and maximum character counts."
                    ))
            }

        case let .selfCheck(schema):
            VStack(alignment: .leading, spacing: 12) {
                Text("Your answer")
                    .font(.headline)
                    .accessibilityHeading(.h2)
                Text(
                    runtime.selfCheckReferenceRevealed
                        ? NFAppLocalization.localized("Compare your answer with the reference, then rate the match.", locale: NFAppLocalization.preferredLocale, comment: "Guidance shown after pre-reveal confidence for a self-check question.")
                        : NFAppLocalization.localized("Answer from memory before seeing the reference. Confidence is optional.", locale: NFAppLocalization.preferredLocale, comment: "Guidance shown before an optional confidence choice and reference reveal for a self-check question.")
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Your answer", text: $runtime.selfCheckReflection, axis: .vertical)
                    .accessibilityLabel("Your answer from memory")
                    .focused($responseFocus, equals: .selfCheck)
                    .textFieldStyle(.plain)
                    .lineLimit(4...10)
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .disabled(runtime.selfCheckReferenceRevealed)
                    .accessibilityIdentifier("ai-practice-self-check-input")
                if runtime.selfCheckReferenceRevealed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reference answer")
                            .font(.caption.weight(.semibold))
                            .accessibilityHeading(.h2)
                            .accessibilityFocused($accessibleFocus, equals: .reference)
                        NFFormattedLearningText(schema.referenceAnswer, font: .body)
                            .textSelection(.enabled)
                        Text("Check your recall against:")
                            .font(.caption.weight(.semibold))
                            .accessibilityHeading(.h3)
                        ForEach(schema.criteria, id: \.self) { criterion in
                            Label(criterion, systemImage: "checkmark")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)

                    ForEach(NFSelfCheckRating.allCases, id: \.rawValue) { rating in
                        let selected = runtime.selfCheckRating == rating
                        Button { runtime.selfCheckRating = rating } label: {
                            HStack {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                Text(selfCheckTitle(rating))
                                Spacer()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(selected ? NFTheme.indigo : .secondary)
                        .nfSelectionAccessibility(selected)
                    }
                }
            }

        case let .claimEvidence(schema):
            if let draft = runtime.scienceStudy {
                NFScienceStudyEditor(exercise: runtime.exercise, draft: draft, selection: runtime.claimSelections,
                    canEdit: runtime.canEditDraft,
                    updateSelection: { runtime.setScienceSelection($0) }, onInput: {})
            } else {
                NFClaimEvidenceEditor(schema: schema, selection: $runtime.claimSelections)
            }
        case let .logicState(schema):
            if let graph = runtime.graphConstruction, let inputIdentity = runtime.graphInputIdentity {
                NFGraphConstructionEditor(graph: graph, response: runtime.graphResponse,
                    canEdit: runtime.canEditDraft, revealsExpected: runtime.stage == 2,
                    updateResponse: { runtime.setGraphResponse($0, expectedInputIdentity: inputIdentity) })
                    .id(inputIdentity)
            } else {
            if let draft = runtime.transferRelationship {
                NFTransferRelationshipEditor(exercise: runtime.exercise, draft: draft, response: runtime.transferResponse,
                    canEdit: runtime.canEditDraft,
                    choose: { runtime.setTransferRelationship($0) }, enterTotal: { runtime.setTransferTotal($0) }, onInput: {},
                    onSubmit: { submitCurrentResponse() })
            } else {
            VStack(alignment: .leading, spacing: 14) {
                if let estimate = runtime.mathWork?.lockedEstimate {
                    LabeledContent("Estimate saved before exact work", value: estimate).accessibilityIdentifier("math-locked-estimate")
                } else if runtime.awaitsEstimateLock {
                    Text("First save your estimate. The exact-result fields open afterward.").font(.subheadline)
                }
                ForEach(runtime.visibleLogicKeys(schema), id: \.self) { key in
                    let responseLabel = runtime.exercise.contractMetadata?.coordinateReasoning.flatMap { _ in
                        NFCoordinateReasoningContract.make(exercise: runtime.exercise).map { $0.responseLabel(key) }
                    } ?? NFCoordinateTransformContract.make(exercise: runtime.exercise).map {
                        $0.text("\(key) (grid units)", "\(key)（格子単位）")
                    } ?? NFMathWorkPolicy.responseLabel(for: key, draft: runtime.mathWork)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Response for \(responseLabel)").font(.subheadline.bold())
                        TextField("Response for \(responseLabel)", text: Binding(
                            get: { runtime.logicState[key, default: ""] },
                            set: { runtime.logicState[key] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture().onEnded { responseFocus = .logic(key) })
                        .focused($responseFocus, equals: .logic(key))
                        .submitLabel(.next)
                        .onSubmit { focusNextLogicField(after: key, schema: schema) }
                        .accessibilityLabel("Response for \(responseLabel)")
                    }
                }
                if !schema.ruleOptions.isEmpty {
                    Text("Violated invariant").font(.headline)
                    ForEach(schema.ruleOptions) { option in
                        Button { runtime.violatedRuleID = option.id } label: {
                            HStack {
                                Image(systemName: runtime.violatedRuleID == option.id ? "checkmark.circle.fill" : "circle")
                                Text(option.text)
                                Spacer()
                            }
                        }
                        .buttonStyle(.bordered)
                        .nfSelectionAccessibility(runtime.violatedRuleID == option.id)
                    }
                }
            }
            }
            }
        }
    }

    @ViewBuilder
    private func choiceGrid(_ options: [NFChoiceOption], multiple: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
            ForEach(options) { option in
                let selected = multiple
                    ? runtime.multipleChoiceIDs.contains(option.id)
                    : runtime.singleChoiceID == option.id
                Button {
                    if multiple {
                        if selected { runtime.multipleChoiceIDs.remove(option.id) }
                        else { runtime.multipleChoiceIDs.insert(option.id) }
                    } else {
                        runtime.singleChoiceID = option.id
                    }
                } label: {
                    HStack(alignment: .top) {
                        Image(systemName: multiple ? (selected ? "checkmark.square.fill" : "square") : (selected ? "largecircle.fill.circle" : "circle"))
                        NFFormattedLearningText(option.text)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .background(
                        selected ? NFTheme.indigo.opacity(0.12) : .primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
                .nfSelectionAccessibility(selected)
            }
        }
    }

    @ViewBuilder
    private func numericResponseFields(_ schema: NFNumericResponseSchema) -> some View {
        TextField(schema.placeholder, text: $runtime.numericValue)
            .textFieldStyle(.roundedBorder)
            .font(.title2.monospacedDigit())
            .numericKeyboard()
            .focused($responseFocus, equals: .numericValue)
            .submitLabel(schema.answer.unitRequired ? .next : .done)
            .onSubmit {
                if schema.answer.unitRequired,
                   runtime.numericUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    responseFocus = .numericUnit
                } else {
                    submitCurrentResponse()
                }
            }
        if schema.answer.canonicalUnit != nil {
            TextField("Unit", text: $runtime.numericUnit)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 150)
                .focused($responseFocus, equals: .numericUnit)
                .submitLabel(.done)
                .onSubmit { submitCurrentResponse() }
        }
    }

    private func selfCheckTitle(_ rating: NFSelfCheckRating) -> String {
        switch rating {
        case .matched: NFAppLocalization.localized("Matched", locale: NFAppLocalization.preferredLocale, comment: "Self-check rating indicating the learner's recall matched the reference.")
        case .partiallyMatched: NFAppLocalization.localized("Partially matched", locale: NFAppLocalization.preferredLocale, comment: "Self-check rating indicating partial agreement with the reference.")
        case .notYet: NFAppLocalization.localized("Not yet", locale: NFAppLocalization.preferredLocale, comment: "Self-check rating indicating recall did not yet match the reference.")
        }
    }

    @ViewBuilder
    private var feedbackContent: some View {
                if let rating = runtime.selfCheckRating {
                    Text(NFResponsePresentation.ratingTitle(rating)).font(.headline)
                        .accessibilityFocused($accessibleFocus, equals: .feedback)
                } else if let score = runtime.lastScore {
                    Label(
                        score.feedback.title,
                        systemImage: score.isCorrect ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"
                    )
                    .font(.title.bold())
                    .accessibilityFocused($accessibleFocus, equals: .feedback)
                    .foregroundStyle(score.isCorrect ? NFTheme.mintForeground : NFTheme.amberForeground)
                    LabeledContent("Score", value: score.credit.formatted(.percent.precision(.fractionLength(0))))
                    .nfCard(cornerRadius: 16, padding: 14)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reference answer").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if runtime.graphConstruction != nil || runtime.transferRelationship != nil {
                        Text(NFResponsePresentation.expectedAnswer(for: runtime.exercise) ?? "")
                    } else if case .claimEvidence = runtime.exercise.interaction {
                        if let expected = NFResponsePresentation.expectedAnswer(for: runtime.exercise) {
                            Text(expected)
                        } else {
                            Text("Original response context is unavailable.")
                        }
                    } else {
                        NFFormattedLearningText(runtime.question.correctAnswer)
                    }
                }
                .nfCard(cornerRadius: 16, padding: 14)
                NFFormattedLearningText(runtime.question.explanation, font: .title3)
                if let draft = runtime.transferRelationship {
                    NFTransferSavedRelationshipView(exercise: runtime.exercise, draft: draft)
                    NFTransferRelationshipDebriefView(exercise: runtime.exercise)
                }
                if runtime.stage == 2,
                   let graph = NFGraphConstructionHistoryProjection.make(exercise: runtime.exercise, response: runtime.graphResponse, isProtected: runtime.exercise.assessmentProtected) {
                    NFGraphConstructionFeedbackView(projection: graph)
                }
                if runtime.scienceStudy != nil {
                    NFScienceStudyFeedbackView(exercise: runtime.exercise, response: runtime.scienceResponse)
                }
                if let explanation = NFObservedProportionExplanation.make(exercise: runtime.exercise) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let prediction = runtime.dataInspection?.firstPrediction {
                            LabeledContent("Prediction saved before explanation (%)", value: prediction.value)
                        }
                        NFDataDenominatorExplanationView(explanation: explanation)
                    }.nfCard().accessibilityIdentifier("ai-data-feedback-explanation")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label("Decisive step", systemImage: "scope").font(.caption.weight(.semibold))
                    NFFormattedLearningText(runtime.question.decisiveStep)
                }
                .nfCard(cornerRadius: 16, padding: 14)
                if let presentation = runtime.question.presentationEnhancement {
                    VStack(alignment: .leading, spacing: 7) {
                        Label(
                            NFAppLocalization.localized("Try it in another context", locale: NFAppLocalization.preferredLocale, comment: "Heading for post-answer transfer guidance."),
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.headline)
                        NFFormattedLearningText(presentation.transferLens)
                    }
                    .nfCard(cornerRadius: 16, padding: 14)
                }
                citationList(revealsExcerpt: true)
    }

    private var feedbackForwardAction: some View {
        let attemptID = runtime.acceptedAttemptID
        return Button(runtime.index + 1 == runtime.result.questions.count ? "View summary" : "Next challenge") {
                    Task { await runtime.nextAsync(store: store, expectedAttemptID: attemptID) }
                }
                .buttonStyle(.borderedProminent)
                .tint(NFTheme.controlTint(for: "indigo"))
                .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!runtime.canAdvanceFeedback)
    }

    private var summaryView: some View {
        ScrollView {
            VStack(spacing: 18) {
                NFIconTile(symbol: "checkmark.seal.fill", color: NFTheme.mint, size: 78)
                Text(runtime.runSummary).font(.largeTitle.bold())
                    .accessibilityIdentifier("ai-practice-summary")
                if let answered = runtime.answeredActivityCount { Text(NFAppLocalization.formattedAnswerCount(answered)) }
                if runtime.skippedActivityCount + runtime.revealedActivityCount > 0 {
                    Text(NFAppLocalization.localized("Skipped \(runtime.skippedActivityCount) · Solutions viewed \(runtime.revealedActivityCount)", locale: NFAppLocalization.preferredLocale, comment: "Unscored activity totals."))
                }
                Text("Your study activity was saved. Skipped and solution-viewed questions do not change skill scores.")
                    .font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                Text("Saved to your practice history.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(NFTheme.controlTint(for: "indigo"))
                    .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                    .controlSize(.large)
            }
            .padding(30)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func citationList(revealsExcerpt: Bool) -> some View {
        if !runtime.question.citationChunkIDs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(revealsExcerpt
                     ? NFAppLocalization.localized("Cited excerpts", locale: NFAppLocalization.preferredLocale, comment: "Heading for source excerpts shown after a learner answers.")
                     : NFAppLocalization.localized("Cited source anchors", locale: NFAppLocalization.preferredLocale, comment: "Heading for citation labels shown before a learner answers."))
                    .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                ForEach(runtime.question.citationChunkIDs, id: \.self) { id in
                    if let chunk = runtime.request.sourceChunks.first(where: { $0.id == id }) {
                        if revealsExcerpt {
                            DisclosureGroup(chunk.citationLabel) {
                                NFFormattedLearningText(
                                    chunk.text,
                                    font: .caption,
                                    sourceLanguage: chunk.language,
                                    contentTypeTags: chunk.contentTypeTags
                                )
                                    .textSelection(.enabled)
                                    .padding(.top, 6)
                            }
                        } else {
                            Label(chunk.citationLabel, systemImage: "doc.text").font(.caption)
                        }
                    }
                }
                if !revealsExcerpt {
                    Text(NFAppLocalization.localized("The excerpt appears after you answer.", locale: NFAppLocalization.preferredLocale, comment: "Compact disclosure explaining when source text appears."))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }.nfCard(cornerRadius: 14, padding: 12)
        }
    }

    private func submitCurrentResponse() {
        guard runtime.canSubmit else { return }
        Task {
            if runtime.isComparingSelfCheck {
                await runtime.saveSelfCheckAsync(store: store)
            } else if runtime.stage == 0 {
                let wasEstimate = runtime.awaitsEstimateLock
                await runtime.submitAsync(store: store)
                if wasEstimate && !runtime.awaitsEstimateLock { responseFocus = .logic(NFEstimateExactContract.exactKey) }
            }
        }
    }

    private var accessiblePresentationIdentity: String {
        "\(runtime.request.id)|\(runtime.index)|\(runtime.stage)|\(runtime.isPaused)|\(runtime.saveError == nil)|\(runtime.ownsWriter)|\(hasAcknowledgedLocalSave)"
    }

    private func focusSavedPresentation() async {
        let identity = accessiblePresentationIdentity
        guard hasAcknowledgedLocalSave, runtime.unavailableReason == nil, !runtime.isReadOnlyRecovery,
              runtime.ownsWriter, !runtime.isPaused, runtime.saveError == nil,
              scenePhase == .active, lastAccessiblePresentation != identity else { return }
        let destination: AccessibleFocus
        switch runtime.stage {
        case 0: destination = .prompt
        case 2: destination = .feedback
        case 4: destination = .reference
        default: return
        }
        await Task.yield()
        guard !Task.isCancelled, accessiblePresentationIdentity == identity,
              runtime.unavailableReason == nil, runtime.saveError == nil,
              !runtime.isPaused, scenePhase == .active else { return }
        lastAccessiblePresentation = identity
        accessibleFocus = destination
    }

    private func focusFirstResponseFieldIfNeeded() {
        #if os(macOS)
        guard runtime.unavailableReason == nil, runtime.stage == 0 else { return }
        Task { @MainActor in
            await Task.yield()
            guard runtime.unavailableReason == nil else { return }
            switch runtime.exercise.interaction {
            case .numeric: responseFocus = .numericValue
            case .shortText: responseFocus = .shortText
            case .selfCheck: responseFocus = .selfCheck
            case let .logicState(schema):
                responseFocus = runtime.visibleLogicKeys(schema).first.map(ResponseFocus.logic)
            default: responseFocus = nil
            }
        }
        #endif
    }

    private func focusNextLogicField(after key: String, schema: NFLogicStateResponseSchema) {
        let keys = runtime.visibleLogicKeys(schema)
        guard let index = keys.firstIndex(of: key), keys.indices.contains(index + 1) else {
            if runtime.canSubmit { submitCurrentResponse() }
            return
        }
        responseFocus = .logic(keys[index + 1])
    }
}

private struct ReportAuthoredQuestionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let question: NFAuthoredQuestion
    let result: NFAuthoringResult
    @State private var reason = "Answer or explanation seems incorrect"
    @State private var note = ""
    @State private var saved = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Generated item") {
                    Text(question.prompt)
                }
                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        Text("Answer or explanation seems incorrect").tag("Answer or explanation seems incorrect")
                        Text("Prompt is ambiguous").tag("Prompt is ambiguous")
                        Text("Citation does not support the claim").tag("Citation does not support the claim")
                        if !question.citationChunkIDs.isEmpty || !question.authoritativeExercise.citations.isEmpty {
                            Text("Source excerpt is insufficient").tag("Source excerpt is insufficient")
                        }
                        Text("Accessibility issue").tag("Accessibility issue")
                        Text("Inappropriate content").tag("Inappropriate content")
                    }
                    TextField("Optional note", text: $note, axis: .vertical)
                }
                Text("Reported questions are excluded from future practice. The report is included in your export and is not sent automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle(saved ? "Report saved" : "Report generated item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save locally") { save() }.disabled(saved)
                }
            }
        }
        .nfDesktopPresentationFrame(minWidth: 380, minHeight: 480)
        .alert("Report could not be saved", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(LocalizedStringKey(saveError ?? "Retry the local save.")) }
    }

    private func save() {
        do {
            try store.saveItemReport(question: question, result: result, reason: reason, note: note)
            saved = true
        } catch {
            saveError = "The report remains on screen so you can try again."
        }
    }
}

private struct NFStarterQuestionSetButton: View {
    let starter: NFStarterQuestionSetDescriptor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Label {
                    Text(starter.field.title)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: starter.lab.symbol)
                        .foregroundStyle(NFTheme.foregroundColor(for: starter.lab.colorToken))
                }
                    .font(.caption.weight(.bold))

                Text(starter.localizedTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(starter.localizedSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Spacer(minLength: 0)

                Label(
                    isSelected ? "Selected" : "Use this set",
                    systemImage: isSelected ? "checkmark.circle.fill" : "arrow.right.circle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? NFTheme.mintForeground : NFTheme.indigoForeground)
            }
            .frame(width: 220, alignment: .topLeading)
            .frame(minHeight: 174, alignment: .topLeading)
            .padding(14)
            .background(
                isSelected ? NFTheme.indigo.opacity(0.10) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? NFTheme.indigo.opacity(0.5) : Color.primary.opacity(0.07))
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ai-studio-starter-set")
        .accessibilityHint("Fills the question settings below. You can still edit them.")
        .nfSelectionAccessibility(isSelected)
    }
}

private struct NFStarterQuestionSetBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    let onSelect: (NFStarterQuestionSetDescriptor) -> Void

    private var filteredSets: [NFStarterQuestionSetDescriptor] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return NFStarterQuestionSetCatalog.sets }
        return NFStarterQuestionSetCatalog.search(query, limit: NFStarterQuestionSetCatalog.sets.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if filteredSets.isEmpty {
                        ContentUnavailableView {
                            Label("No matching question sets", systemImage: "magnifyingglass")
                        } description: {
                            Text("Try another topic or field.")
                        } actions: {
                            Button("Clear search") { searchText = "" }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, minHeight: 360)
                    } else {
                        ForEach(filteredSets) { starter in
                            Button { onSelect(starter) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    NFIconTile(
                                        symbol: starter.lab.symbol,
                                        color: NFTheme.color(for: starter.lab.colorToken),
                                        size: 44
                                    )
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(starter.localizedTitle)
                                            .font(.headline)
                                        Text(starter.localizedSummary)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text(starter.field.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(14)
                                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .background(AppBackground())
            .navigationTitle("Question sets")
            .searchable(text: $searchText, prompt: "Search topics and fields")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .nfDesktopPresentationFrame(minWidth: 420, idealWidth: 680, minHeight: 560, idealHeight: 760)
    }
}


extension AIGeneratedPracticeRuntime {
    var awaitsEstimateLock: Bool { mathWork?.awaitsEstimate == true }
    func visibleLogicKeys(_ schema: NFLogicStateResponseSchema) -> [String] {
        NFMathWorkPolicy.responseKeys(schema: schema, draft: mathWork)
    }
    @discardableResult
    func lockEstimate(store: AppStore) -> Bool {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; _ = self.lockEstimate(store: store)
        }) { return false }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canEditDraft, let previous = mathWork,
              previous.isCompatible(with: exercise, response: makeResponse()),
              let next = previous.lockingEstimate(logicState[NFEstimateExactContract.estimateKey] ?? "", activeSeconds: activeDuration) else { return false }
        let previousConfidence = confidence
        mathWork = next; confidence = nil
        guard checkpoint(store: store), !isReadOnlyRecovery, ownsWriter else { mathWork = previous; confidence = previousConfidence; return false }
        return true
    }
}


extension AIGeneratedPracticeRuntime {
    func setDataPrediction(_ text: String) {
        guard canEditDraft, text.count <= 500,
              dataInspection?.overlayRevealed == false else { return }
        dataInspection?.predictionText = text
    }
    func selectDataPoint(_ id: Int, store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.selectDataPoint(id, store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canEditDraft, let previous = dataInspection,
              let next = previous.selecting(pointID: id, exercise: exercise) else { return }
        dataInspection = next
        if !checkpoint(store: store) || isReadOnlyRecovery { dataInspection = previous }
    }
    @discardableResult
    func revealDataExplanation(store: AppStore) -> Bool {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; _ = self.revealDataExplanation(store: store)
        }) { return false }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canEditDraft, let previous = dataInspection,
              let next = previous.revealing(exercise: exercise, activeSeconds: activeDuration) else { return false }
        let oldConfidence = confidence
        dataInspection = next; confidence = nil
        guard checkpoint(store: store), !isReadOnlyRecovery, ownsWriter else {
            dataInspection = previous; confidence = oldConfidence; return false
        }
        return true
    }
    func toggleDataExplanation(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.toggleDataExplanation(store: store)
        }) { return }
        guard canEditDraft,
              let previous = dataInspection, previous.overlayRevealed else { return }
        dataInspection?.overlayExpanded.toggle()
        if !checkpoint(store: store) || isReadOnlyRecovery { dataInspection = previous }
    }
}

extension AIGeneratedPracticeRuntime {
    var scienceResponse: NFExerciseResponse { makeResponse() }
    var awaitsScienceEvidence: Bool { scienceStudy?.awaitsEvidence == true }
    var scienceEvidenceValidation: NFExerciseResponseValidation? {
        scienceStudy?.evidenceValidation(makeResponse(), exercise: exercise)
    }
    func setScienceSelection(_ value: [String: Set<String>]) {
        guard canEditDraft, let draft = scienceStudy else { return }
        let response = NFExerciseResponse.claimEvidence(.init(pairs: value.keys.sorted().map {
            .init(claimID: $0, evidenceIDs: value[$0, default: []].sorted())
        }))
        guard draft.isCompatible(with: exercise, response: response) else { return }
        claimSelections = value
    }
    @discardableResult
    func lockScienceEvidence(store: AppStore) -> Bool {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; _ = self.lockScienceEvidence(store: store)
        }) { return false }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canEditDraft, let previous = scienceStudy,
              let next = previous.locking(response: makeResponse(), exercise: exercise,
                  activeSeconds: activeDuration) else { return false }
        let previousConfidence = confidence
        scienceStudy = next; confidence = nil
        guard checkpoint(store: store), !isReadOnlyRecovery, ownsWriter else {
            scienceStudy = previous; confidence = previousConfidence; return false
        }
        return true
    }
}

extension AIGeneratedPracticeRuntime {
    var transferResponse: NFExerciseResponse { makeResponse() }
    var awaitsTransferRelationship: Bool { transferRelationship?.awaitsRelationship == true }
    var canLockTransferRelationship: Bool {
        guard canEditDraft, let draft = transferRelationship else { return false }
        return draft.locking(response: makeResponse(), exercise: exercise, activeSeconds: activeDuration) != nil
    }
    func setTransferRelationship(_ id: String?) {
        guard canEditDraft,
              let draft = transferRelationship, draft.awaitsRelationship else { return }
        let response = NFExerciseResponse.logicState(.init(finalState: logicState, violatedRuleID: id))
        guard draft.isCompatible(with: exercise, response: response) else { return }
        violatedRuleID = id
    }
    func setTransferTotal(_ value: String) {
        guard canEditDraft, transferRelationship?.awaitsRelationship == false else { return }
        logicState[NFTransferRelationshipContract.totalKey] = value
    }
    @discardableResult
    func lockTransferRelationship(store: AppStore) -> Bool {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; _ = self.lockTransferRelationship(store: store)
        }) { return false }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canLockTransferRelationship, let previous = transferRelationship,
              let next = previous.locking(response: makeResponse(), exercise: exercise, activeSeconds: activeDuration) else { return false }
        let previousConfidence = confidence
        transferRelationship = next; confidence = nil
        guard checkpoint(store: store), !isReadOnlyRecovery, ownsWriter else {
            transferRelationship = previous; confidence = previousConfidence; return false
        }
        return true
    }
}


extension AIGeneratedPracticeRuntime {
    var graphConstruction: NFGraphConstructionContract? { NFGraphConstructionContract.make(exercise: exercise) }
    var graphResponse: NFExerciseResponse { makeResponse() }
    var graphExerciseDigest: String? { try? NFLocalItemCheckpoint.digest(exercise) }
    var graphInputIdentity: String? { graphExerciseDigest.map { "\(runID.uuidString)|\(index)|\($0)" } }
    @discardableResult func setGraphPoint(_ point: NFGraphConstructionContract.Point, expectedInputIdentity: String) -> Bool {
        guard let graph = graphConstruction, graph.contains(point) else { return false }
        return setGraphResponse(point.response, expectedInputIdentity: expectedInputIdentity)
    }
    @discardableResult func setGraphResponse(_ response: NFExerciseResponse, expectedInputIdentity: String) -> Bool {
        guard canEditDraft,
              graphInputIdentity == expectedInputIdentity, let graph = graphConstruction,
              response == NFExerciseResponse.initialDraft(for: exercise) || graph.point(from: response) != nil,
              case let .logicState(value) = response else { return false }
        logicState = value.finalState; violatedRuleID = nil
        invalidateConfidenceAfterEdit()
        return true
    }
}

extension AIGeneratedPracticeRuntime {
    var canEditDraft: Bool {
        if draftSaveGate.hasQueuedAction || isCommitInFlight || pendingGeneratedSubmission != nil || pendingGeneratedAdvance != nil { return false }
        return stage == 0 && isDurablyPrepared && ownsWriter && !isPaused && !isReadOnlyRecovery
            && unavailableReason == nil && !hasExited && pendingUnscored == nil
    }
    var canRateSelfCheck: Bool {
        if draftSaveGate.hasQueuedAction || isCommitInFlight || pendingGeneratedSubmission != nil || pendingGeneratedAdvance != nil { return false }
        return stage == 4 && isDurablyPrepared && ownsWriter && !isPaused && !isReadOnlyRecovery && !hasExited
    }
    var canAdvanceFeedback: Bool {
        !isCommitInFlight && pendingGeneratedSubmission == nil && pendingGeneratedAdvance == nil && stage == 2 && isDurablyPrepared && ownsWriter && !isPaused && !isReadOnlyRecovery && !hasExited
    }
    var canSkip: Bool { canEditDraft }
    var isUnscoredFeedback: Bool { stage == 2 && pendingUnscored != nil }
    var isSolutionViewed: Bool { pendingUnscored == .revealed && stage == 2 }
    var acceptedSlotID: UUID? { runState?.current.id }
    var acceptedAttemptID: UUID? { pendingAttemptID }
    var answeredActivityCount: Int? { runState?.answeredCount }
    var skippedActivityCount: Int { runState?.slots.filter { $0.outcome == .skipped }.count ?? 0 }
    var revealedActivityCount: Int { runState?.slots.filter { $0.outcome == .revealed }.count ?? 0 }
    var completedActivityCount: Int {
        runState?.completedCount ?? terminalState?.completedCount ?? (index + (stage == 2 ? 1 : 0))
    }
    var plannedQuestionCount: Int { terminalInventory?.plannedQuestionCount ?? result.questions.count }
    var runSummary: String {
        let ended = runState?.status == .endedEarly || terminalState?.endedEarly == true
        return ended
            ? NFAppLocalization.localized("Ended after \(completedActivityCount) of \(plannedQuestionCount) questions.", locale: NFAppLocalization.preferredLocale, comment: "Authored run early ending.")
            : NFAppLocalization.localized("Completed \(completedActivityCount) of \(plannedQuestionCount) questions.", locale: NFAppLocalization.preferredLocale, comment: "Authored run completion.")
    }
    var activeHintLadder: [String] {
        guard !awaitsTransferRelationship else { return [] }
        if runState == nil { return [question.presentationEnhancement?.coachingHint ?? question.hint].filter { !$0.isEmpty } }
        return Array(exercise.feedback.hintLadder.prefix(64))
    }
    var hintRequestIndex: Int { runState?.nextHintIndex ?? coachingHintCount }
    var hintActionTitle: String {
        let count = runState?.nextHintIndex ?? coachingHintCount
        return count >= activeHintLadder.count ? "See worked solution" : count == 0 ? "Use a hint" : "Next hint"
    }
    var visibleHints: [String] { Array(activeHintLadder.prefix(runState?.nextHintIndex ?? coachingHintCount)) }
    var canRevealSolution: Bool {
        guard canEditDraft, !awaitsTransferRelationship else { return false }
        if case .selfCheck = exercise.interaction { return false }
        return true
    }
    func acknowledgePresented(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.acknowledgePresented(store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard isDurablyPrepared, !isPaused, ownsWriter, !hasExited, !isReadOnlyRecovery else { return }
        if runState?.current.presentedAt == nil, var value = runState {
            value.slots[value.slots.count - 1].presentedAt = Date()
            let previous = runState
            runState = value
            guard checkpoint(store: store) else { runState = previous; return }
        }
        if stage == 0, activeSegmentStart == nil { activeSegmentStart = ProcessInfo.processInfo.systemUptime }
    }
    func requestHint(store: AppStore, expectedAttemptID: UUID? = nil, expectedHintIndex: Int? = nil) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.requestHint(store: store, expectedAttemptID: expectedAttemptID, expectedHintIndex: expectedHintIndex)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard expectedAttemptID == nil || expectedAttemptID == pendingAttemptID,
              expectedHintIndex == nil || expectedHintIndex == hintRequestIndex else { return }
        guard canEditDraft, !awaitsTransferRelationship else { return }
        let count = runState?.nextHintIndex ?? coachingHintCount
        guard count < activeHintLadder.count else { revealSolution(store: store); return }
        let previous = runState
        let previousExpanded = showsCoaching
        let previousRevealed = hasRevealedCoaching
        if var value = runState {
            value.nextHintIndex += 1
            value.slots[value.slots.count - 1].assistance.append(.init(id: UUID(), kind: .hint,
                stage: value.nextHintIndex, activeOffset: activeDuration, generatorVersion: exercise.generatorVersion))
            runState = value
        }
        hasRevealedCoaching = true; showsCoaching = true
        guard checkpoint(store: store) else {
            runState = previous; showsCoaching = previousExpanded; hasRevealedCoaching = previousRevealed; return
        }
    }
    func skip(store: AppStore, expectedAttemptID: UUID? = nil) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.skip(store: store, expectedAttemptID: expectedAttemptID)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard expectedAttemptID == nil || expectedAttemptID == pendingAttemptID else { return }
        guard canSkip || pendingUnscored == .skipped else { return }
        saveUnscored(.skipped, store: store)
        if stage == 2, saveError == nil { advanceToNextSnapshot(store: store, ending: index + 1 >= result.questions.count) }
    }
    func revealSolution(store: AppStore) {
        if deferUntilDraftSaveCompletes({ [weak self, weak store] in
            guard let self, let store else { return }; self.revealSolution(store: store)
        }) { return }
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard canRevealSolution || pendingUnscored == .revealed else { return }
        saveUnscored(.revealed, store: store)
    }
    private func saveUnscored(_ outcome: NFGeneratedRunState.Outcome, store: AppStore) {
        let previousCommandAuthority = activeCommandAuthority
        activeCommandAuthority = activeCommandAuthority ?? retainedWriterAuthority
        defer { activeCommandAuthority = previousCommandAuthority }

        guard ownsWriter, isDurablyPrepared, !isReadOnlyRecovery, !hasExited,
              pendingUnscored == nil || pendingUnscored == outcome,
              let attemptID = pendingAttemptID else { return }
        stopTiming()
        let response = preparedResponse ?? makeResponse()
        lifecycle.commitUnscored(canMutate: { self.ownsWriter && !self.hasExited && !self.isReadOnlyRecovery },
            receipt: {
                guard let record = store.attempts.first(where: { $0.id == attemptID }) else { return .absent }
                return self.matchesUnscoredReceipt(record, outcome: outcome, response: response, store: store) ? .matching : .conflicting
            }, prepare: {
                self.prepareUnscoredIntent(outcome, response: response)
            }, persistPrepared: { self.checkpoint(store: store) }, save: {
                try store.withSessionCommand(try self.sessionWriterCommand(), sessionID: self.runID) {
                    try store.saveSkippedExercise(attemptID: attemptID, sessionID: self.attemptSessionID,
                        exercise: self.exercise, shownAt: self.shownAt, activeDuration: self.accumulatedActiveDuration,
                        source: .focused, revealedSolution: outcome == .revealed,
                        draftResponse: String(decoding: try JSONEncoder().encode(response), as: UTF8.self),
                        hintCount: self.capturedSupportCount, traceInspection: self.traceInspection,
                        dataInspection: self.dataInspection, scienceStudy: self.scienceStudy, transferRelationship: self.transferRelationship,
                        preserveDraftResponse: true, generationID: self.result.provenance.requestID, mathWork: self.mathWork)
                    #if DEBUG
                    self.receiptWriteAcknowledged?()
                    #endif
                }
            }, acknowledge: {
                self.pendingUnscored = outcome; self.preparedResponse = response
                if var state = self.runState {
                    state.pendingUnscored = outcome
                    state.slots[state.slots.count - 1].outcome = outcome
                    self.runState = state
                }
            }, persistFeedback: { self.checkpoint(store: store) }, failed: {
                self.saveError = "The activity could not be saved. Your original answer is retained."
            })
    }
    private var attemptSessionID: UUID { runState == nil ? result.provenance.requestID : runID }
    private func matchesUnscoredReceipt(_ record: AttemptRecord, outcome: NFGeneratedRunState.Outcome,
                                         response: NFExerciseResponse, store: AppStore) -> Bool {
        guard let snapshot = store.localSessions.archive.snapshots.first(where: { $0.attemptID == record.id }),
              snapshot.exercise == exercise, snapshot.mathWork == mathWork,
              snapshot.traceInspection == traceInspection, snapshot.dataInspection == dataInspection,
              snapshot.scienceStudy == scienceStudy, snapshot.transferRelationship == transferRelationship else { return false }
        return record.sessionID == attemptSessionID && record.generationID == result.provenance.requestID
            && record.itemID == exercise.id && record.templateID == exercise.templateID && record.seed == exercise.seed
            && record.prompt == exercise.prompt && record.wasSkipped && record.confidenceRaw == nil
            && record.gameID == exercise.lab.rawValue && record.evidenceClassRaw == exercise.evidenceClass.rawValue
            && record.sessionSourceRaw == SessionSource.focused.rawValue && record.assessmentBlockRaw == nil
            && record.scoringVersion == NFExerciseScoringEngine.scoringVersion && record.shownAt == shownAt
            && record.correctAnswerText == "Not evaluated" && !record.wasTimed
            && record.inputModeRaw == (outcome == .revealed ? "revealed" : "skipped")
            && record.responseFormatRaw == (outcome == .revealed ? "revealed" : "skipped")
            && record.errorCode == (outcome == .revealed ? "solution_revealed" : nil)
            && record.evidenceWeight == 0 && record.deterministicCredit == 0 && !record.isCorrect
            && record.hintCount == capturedSupportCount && record.activeDurationSeconds == accumulatedActiveDuration
            && record.sourceDocumentIDsRaw == exercise.provenance.sourceDocumentIDs.joined(separator: ",")
            && record.sourceChunkIDsRaw == exercise.provenance.sourceChunkIDs.joined(separator: ",")
            && (try? JSONDecoder().decode(NFExerciseResponse.self, from: Data(record.response.utf8))) == response
    }
}

extension AIGeneratedPracticeRuntime {
    @discardableResult func checkpointAsync(store: AppStore) async -> Bool {
        await draftSaveGate.waitUntilIdle()
        guard !Task.isCancelled, !hasExited, ownsWriter, !isReadOnlyRecovery, isDurablyPrepared else { return false }
        guard draftSaveGate.begin() else { return false }
        defer { draftSaveGate.finish() }
        invalidateConfidenceAfterEdit()
        do {
            let command = try sessionWriterCommand()
            guard let snapshot = currentSnapshot(store: store) else {
                throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
            }
            #if DEBUG
            try privateCheckpointWriteFailure?(snapshot)
            #endif
            let acknowledgement = try await store.localSessions.saveGeneratedSessionAsync(snapshot,
                command: command, expectedRevision: acknowledgedRevision,
                expectedPayloadDigest: acknowledgedLegacyPayloadDigest)
            try store.localSessions.validateSessionCommand(command, sessionID: runID)
            acknowledgeSnapshot(snapshot, store: store)
            guard !acknowledgement.verificationNeeded else {
                saveError = NFAppLocalization.localizedCatalogValue(
                    "Your latest work was written, but storage verification did not finish. Keep this session open and retry saving.",
                    locale: NFAppLocalization.preferredLocale)
                return false
            }
            saveError = nil
            return true
        } catch is CancellationError { return false }
        catch {
            if !hasExited {
                saveError = NFAppLocalization.localizedCatalogValue("We couldn't save this yet. Your answer is still here.",
                    locale: NFAppLocalization.preferredLocale)
            }
            return false
        }
    }

    private func deferUntilDraftSaveCompletes(_ action: @escaping () -> Void, followsAcceptedAdvance: Bool = false) -> Bool {
        guard draftSaveGate.isSaving else { return false }
        if draftSaveGate.hasQueuedAction { return true }
        let hadAnswerClock = activeSegmentStart != nil
        stopTiming()
        let identity = generatedDraftFingerprint(includePhase: false)
        let attempt = pendingAttemptID
        let command = try? sessionWriterCommand()
        return draftSaveGate.enqueue { [weak self] in
            guard let self, !self.hasExited else { return }
            if hadAnswerClock, !self.isPaused, self.stage == 0 { self.activeSegmentStart = ProcessInfo.processInfo.systemUptime }
            guard let command, (try? self.sessionWriterCommand()) == command,
                  (self.generatedDraftFingerprint(includePhase: false) == identity && self.pendingAttemptID == attempt)
                    || (followsAcceptedAdvance && self.canFollowAcceptedAdvance(command: command,
                        sourceFingerprint: identity, sourceAttemptID: attempt)) else {
                self.saveError = NFAppLocalization.localizedCatalogValue(
                    "Your answer changed while saving. Review it and try the action again.", locale: NFAppLocalization.preferredLocale)
                return
            }
            action()
        }
    }

    private func acknowledgeSnapshot(_ snapshot: NFGeneratedPracticeDraft, store: AppStore) {
        if snapshot.runState != nil { acknowledgedRevision = snapshot.runState?.revision }
        else {
            acknowledgedLegacyPayloadDigest = store.localSessions.archive.privateStudyRuns?.first(where: { $0.id == runID })
                .map { NFReservationSnapshot.digest($0.payload) }
        }
        if snapshot.index == index, snapshot.pendingAttemptID == pendingAttemptID { isDurablyPrepared = true }
        store.localSessionRevision += 1
    }
}

private enum NFGeneratedSubmissionPublication {
    case none
    case reference
    case feedback
    case unscored(NFGeneratedRunState.Outcome)
}

private struct NFPendingGeneratedSubmission {
    let draft: NFGeneratedPracticeDraft
    let command: NFSessionWriterCommand
    let publication: NFGeneratedSubmissionPublication
}

extension AIGeneratedPracticeRuntime {
    func submitAsync(store: AppStore) async {
        guard await waitForGeneratedSubmissionBoundary(), canSubmit else { return }
        if awaitsTransferRelationship { _ = lockTransferRelationship(store: store); return }
        if awaitsScienceEvidence { _ = lockScienceEvidence(store: store); return }
        if awaitsEstimateLock { _ = lockEstimate(store: store); return }
        guard stage == 0, !isPaused else { return }
        invalidateConfidenceAfterEdit()
        guard let command = try? sessionWriterCommand(), draftSaveGate.begin() else { return }
        isCommitInFlight = true
        stopTiming()
        defer { isCommitInFlight = false; draftSaveGate.finish() }
        if case .selfCheck = exercise.interaction {
            do {
                guard let draft = currentSnapshot(store: store, stageOverride: 4, referenceOverride: true) else {
                    throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
                }
                try await persistGeneratedSubmission(draft, publication: .reference, command: command, store: store)
            } catch { generatedSubmissionFailed(error) }
        } else { await persistAttemptAsync(store: store, command: command) }
    }

    func saveSelfCheckAsync(store: AppStore) async {
        guard await waitForGeneratedSubmissionBoundary(), canRateSelfCheck, canSubmit,
              let command = try? sessionWriterCommand(), draftSaveGate.begin() else { return }
        isCommitInFlight = true
        stopTiming()
        defer { isCommitInFlight = false; draftSaveGate.finish() }
        await persistAttemptAsync(store: store, command: command)
    }

    func retryCommitAsync(store: AppStore) async {
        if pendingGeneratedAdvance != nil { await retryAdvanceAsync(store: store); return }
        guard !hasUnexpectedPreparedResponseEdit else {
            generatedSubmissionFailed(NFLocalSessionRepository.RepositoryError.staleRevision); return
        }
        guard await waitForGeneratedSubmissionBoundary() else { return }
        if let pending = pendingGeneratedSubmission {
            guard await repairGeneratedSubmission(pending, store: store) else { return }
            if case .none = pending.publication {} else { return }
        } else if store.localSessions.archiveWriteVerificationNeeded {
            guard await checkpointAsync(store: store) else { return }
        }
        guard stage == 1 else { _ = await checkpointAsync(store: store); return }
        if let pendingUnscored {
            await saveUnscoredAsync(pendingUnscored, store: store)
            return
        }
        guard let command = try? sessionWriterCommand(), draftSaveGate.begin() else { return }
        isCommitInFlight = true
        stopTiming()
        defer { isCommitInFlight = false; draftSaveGate.finish() }
        await persistAttemptAsync(store: store, command: command)
    }

    func endSessionAsync(store: AppStore) async {
        guard await waitForGeneratedSubmissionBoundary(allowActiveSubmission: true, allowAcceptedAdvance: true) else { return }
        if pendingGeneratedAdvance != nil {
            await retryAdvanceAsync(store: store)
            guard pendingGeneratedAdvance == nil, saveError == nil else { return }
        }
        if stage == 1 || pendingGeneratedSubmission != nil {
            await retryCommitAsync(store: store)
            guard stage != 1, pendingGeneratedSubmission == nil, saveError == nil else { return }
        }
        guard stage != 3 else { return }
        await advanceGeneratedAsync(store: store, ending: true, learnerEnded: true)
    }

    func takeOverAsync(store: AppStore) async {
        takeOver(store: store, automaticallyRetryPrepared: false)
        if stage == 1, ownsWriter { await retryCommitAsync(store: store) }
    }

    private func waitForGeneratedSubmissionBoundary(allowActiveSubmission: Bool = false, allowAcceptedAdvance: Bool = false) async -> Bool {
        guard !hasExited, !isReadOnlyRecovery, isDurablyPrepared, ownsWriter, !Task.isCancelled,
              allowActiveSubmission || !isCommitInFlight, let command = try? sessionWriterCommand() else { return false }
        let capturedResponse = makeResponse()
        let capturedAttempt = pendingAttemptID
        let capturedIdentity = generatedDraftFingerprint(includePhase: false)
        if draftSaveGate.isSaving {
            guard !draftSaveGate.hasQueuedAction else { return false }
            stopTiming()
            guard draftSaveGate.enqueue({}) else { return false }
            await draftSaveGate.waitUntilIdle()
        }
        guard !hasExited, !isCommitInFlight, !Task.isCancelled,
              command == (try? sessionWriterCommand()),
              (capturedResponse == makeResponse() && capturedAttempt == pendingAttemptID)
                || (allowAcceptedAdvance && canFollowAcceptedAdvance(command: command,
                    sourceFingerprint: capturedIdentity, sourceAttemptID: capturedAttempt)) else { return false }
        return true
    }

    private func repairGeneratedSubmission(_ pending: NFPendingGeneratedSubmission, store: AppStore) async -> Bool {
        guard pending.command == (try? sessionWriterCommand()), draftSaveGate.begin() else { return false }
        isCommitInFlight = true
        stopTiming()
        defer { isCommitInFlight = false; draftSaveGate.finish() }
        do {
            try await persistGeneratedSubmission(pending.draft, publication: pending.publication,
                command: pending.command, store: store)
            return true
        } catch { generatedSubmissionFailed(error); return false }
    }

    private func persistGeneratedSubmission(_ captured: NFGeneratedPracticeDraft,
        publication: NFGeneratedSubmissionPublication = .none, command: NFSessionWriterCommand,
        store: AppStore) async throws {
        try store.localSessions.validateSessionCommand(command, sessionID: runID)
        var draft = captured
        // Repair advances only its monotonic revision. Content and publication
        // intent remain the exact values already accepted by the prior rename.
        if draft.runState != nil { draft.runState?.revision = try NFSessionWriterRevision.next(after: acknowledgedRevision) }
        #if DEBUG
        try privateCheckpointWriteFailure?(draft)
        #endif
        let acknowledgement = try await store.localSessions.saveGeneratedSessionAsync(draft,
            command: command, expectedRevision: acknowledgedRevision,
            expectedPayloadDigest: acknowledgedLegacyPayloadDigest)
        try store.localSessions.validateSessionCommand(command, sessionID: runID)
        acknowledgeSnapshot(draft, store: store)
        pendingGeneratedSubmission = .init(draft: draft, command: command, publication: publication)
        guard !hasUnexpectedPreparedResponseEdit else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
        guard !acknowledgement.verificationNeeded else { throw NFLocalSessionRepository.RepositoryError.busy }
        pendingGeneratedSubmission = nil
        switch publication {
        case .none: break
        case .unscored(let outcome):
            if var state = runState, let accepted = draft.runState {
                guard state.current.id == accepted.current.id else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
                state.slots[state.slots.count - 1].outcome = accepted.current.outcome
                state.pendingUnscored = outcome
                runState = state
            }
            pendingUnscored = outcome
            preparedResponse = draft.scoredResponse
            lastScore = nil
            stage = 2
        case .reference:
            selfCheckReferenceRevealed = true
            stage = 4
        case .feedback:
            if var state = runState, let accepted = draft.runState {
                // A pause delivered while awaiting storage retains its own
                // interruption count. Only the accepted outcome is published.
                guard state.current.id == accepted.current.id else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
                state.slots[state.slots.count - 1].outcome = accepted.current.outcome
                runState = state
            }
            correctness = draft.correctness
            lastScore = draft.lastScore
            stage = 2
        }
        saveError = nil
    }

    private func persistGeneratedFeedback(_ intent: NFSessionLifecycleCoordinator.CommitIntent,
        command: NFSessionWriterCommand, store: AppStore) async throws {
        guard var draft = currentSnapshot(store: store), draft.stage == 1,
              draft.pendingAttemptID == intent.attemptID, draft.scoredResponse == intent.response,
              draft.lastScore == intent.score else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
        let alreadyAcknowledged = draft.runState?.current.outcome != nil
        if intent.score.outcome != .selfReported && !alreadyAcknowledged { draft.correctness.append(intent.score.isCorrect) }
        if var state = draft.runState {
            state.slots[state.slots.count - 1].outcome = intent.score.outcome == .selfReported ? .selfReported : .scored
            draft.runState = state
        }
        draft.stage = 2
        try await persistGeneratedSubmission(draft, publication: .feedback, command: command, store: store)
    }

    private var hasUnexpectedPreparedResponseEdit: Bool {
        if let pendingGeneratedSubmission, pendingGeneratedSubmission.draft.response != makeResponse() { return true }
        return preparedResponse.map { $0 != makeResponse() } ?? false
    }

    private func generatedSubmissionFailed(_ error: Error) {
        guard !hasExited else { return }
        saveError = NFAppLocalization.localizedCatalogValue("Your answer remains on screen. Try saving it again.",
            locale: NFAppLocalization.preferredLocale)
    }
}

extension AIGeneratedPracticeRuntime {
    private func persistAttemptAsync(store: AppStore, command: NFSessionWriterCommand) async {
        guard !isReadOnlyRecovery, ownsWriter else { return }
        if let id = pendingAttemptID, store.attempts.contains(where: { $0.id == id }),
           let original = store.localSessions.archive.snapshots.first(where: { $0.attemptID == id }),
           (original.mathWork != mathWork || original.dataInspection != dataInspection || original.scienceStudy != scienceStudy || original.transferRelationship != transferRelationship) {
            unavailableReason = NFGeneratedPracticeCompatibility.unavailableMessage; isReadOnlyRecovery = true; return
        }
        var conflictIntent: NFSessionLifecycleCoordinator.CommitIntent?
        var needsClarificationSave = false
        let response = preparedResponse ?? makeResponse()
        let recovered: NFSessionLifecycleCoordinator.CommitIntent?
        if stage == 1 {
            guard let lastScore, let pendingAttemptID, preparedResponse == response else {
                unavailableReason = NFGeneratedPracticeCompatibility.unavailableMessage
                isReadOnlyRecovery = true
                return
            }
            recovered = .init(attemptID: pendingAttemptID, response: response, score: lastScore, confidence: confidence)
        } else { recovered = nil }
        stopTiming()
        await lifecycle.commitAsync(exercise: exercise, response: response, attemptID: pendingAttemptID,
            confidence: confidence, recoveredIntent: recovered,
            canMutate: { self.ownsWriter && !self.isReadOnlyRecovery && command == (try? self.sessionWriterCommand()) },
            receipt: { intent in
                guard let committed = store.attempts.first(where: { $0.id == intent.attemptID }) else { return .absent }
                return self.matchesCommittedReceipt(committed, response: intent.response, score: intent.score, confidence: intent.confidence, store: store)
                    ? .matching : .conflicting
            }, allowsNewCommit: {
                guard !store.isQuarantined(question: self.question, in: self.result) else {
                    self.saveError = NFAppLocalization.localizedCatalogValue("This question was reported and is unavailable for practice. Your saved work remains readable.", locale: NFAppLocalization.preferredLocale)
                    return false
                }
                return true
            }, publishPrepared: { intent in
                self.pendingAttemptID = intent.attemptID
                self.preparedResponse = intent.response
                self.lastScore = intent.score
                self.confidence = intent.confidence
            }, persistPrepared: {
                guard let draft = self.currentSnapshot(store: store) else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
                try await self.persistGeneratedSubmission(draft, command: command, store: store)
            },
            saveAttempt: { intent in
                try await store.saveAuthoredExerciseAttemptAsync(command: command, runID: self.runID, attemptID: intent.attemptID,
                        generationID: self.result.provenance.requestID, sessionID: self.attemptSessionID, question: self.question,
                        response: intent.response, score: intent.score, confidence: intent.confidence,
                        sourceDocumentIDs: self.result.provenance.sourceDocumentIDs,
                        shownAt: self.shownAt, activeDuration: self.accumulatedActiveDuration,
                        hintCount: self.capturedSupportCount, mathWork: self.mathWork, traceInspection: self.traceInspection, dataInspection: self.dataInspection, scienceStudy: self.scienceStudy, transferRelationship: self.transferRelationship)
                #if DEBUG
                self.receiptWriteAcknowledged?()
                #endif
            }, persistAndPublishFeedback: { intent in
                try await self.persistGeneratedFeedback(intent, command: command, store: store)
            },
            nonScorable: { score in
                self.saveError = nil
                if score.outcome == .invalidItem {
                    self.unavailableReason = score.feedback.explanation
                    self.isReadOnlyRecovery = true
                } else {
                    self.savedClarificationMessage = score.feedback.explanation
                    self.clarificationResponse = response
                    self.activeSegmentStart = nil
                    needsClarificationSave = true
                }
            }, conflictingReceipt: { intent in
                conflictIntent = intent
            }, failedSave: { error in self.generatedSubmissionFailed(error) })
        if needsClarificationSave {
            do {
                guard let draft = currentSnapshot(store: store) else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
                try await persistGeneratedSubmission(draft, command: command, store: store)
            } catch { generatedSubmissionFailed(error) }
            if !isPaused { activeSegmentStart = ProcessInfo.processInfo.systemUptime }
        }
        if let intent = conflictIntent {
            do {
                guard let draft = currentSnapshot(store: store) else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
                try await persistGeneratedSubmission(draft, command: command, store: store)
                try await store.recordAuthoredExerciseAttemptConflictAsync(command: command, runID: runID,
                    attemptID: intent.attemptID, generationID: result.provenance.requestID, sessionID: attemptSessionID,
                    question: question, response: intent.response, score: intent.score, confidence: intent.confidence,
                    sourceDocumentIDs: result.provenance.sourceDocumentIDs, shownAt: shownAt,
                    activeDuration: accumulatedActiveDuration, hintCount: capturedSupportCount)
                unavailableReason = NFGeneratedPracticeCompatibility.unavailableMessage
                isReadOnlyRecovery = true
            } catch { generatedSubmissionFailed(error) }
        }
    }
}

extension AIGeneratedPracticeRuntime {
    private func applyGeneratedDraftFields(_ draft: NFGeneratedPracticeDraft) {
        result = draft.result
        request = draft.request
        runID = draft.id
        runState = draft.runState
        terminalState = draft.terminalState
        terminalInventory = draft.terminalInventory
        pendingUnscored = draft.runState?.pendingUnscored ?? draft.pendingUnscored
        acknowledgedRevision = draft.runState?.revision
        index = draft.index
        stage = draft.stage
        confidence = draft.confidence
        selfCheckReferenceRevealed = draft.referenceRevealed
        hasRevealedCoaching = draft.hintRevealed
        traceInspection = draft.traceInspection
        showsCoaching = draft.hintExpanded ?? draft.hintRevealed
        mathWork = draft.mathWork
        dataInspection = draft.dataInspection
        scienceStudy = draft.scienceStudy
        transferRelationship = draft.transferRelationship
        correctness = draft.correctness
        lastScore = draft.lastScore
        preparedResponse = draft.scoredResponse
        savedClarificationMessage = draft.clarificationMessage
        clarificationResponse = draft.clarificationMessage == nil ? nil : draft.response
        pendingAttemptID = draft.pendingAttemptID
        shownAt = draft.shownAt
        accumulatedActiveDuration = draft.activeDuration
        activeSegmentStart = nil
        switch draft.response {
        case .numeric(let value): numericValue = value.value; numericUnit = value.unit ?? ""
        case .singleChoice(let id): singleChoiceID = id
        case .multipleChoice(let ids): multipleChoiceIDs = Set(ids)
        case .orderedSteps(let ids): orderedStepIDs = ids
        case .shortText(let text): shortText = text
        case .selfCheck(let value): selfCheckRating = draft.referenceRevealed ? value.rating : nil; selfCheckReflection = value.reflection ?? ""
        case .claimEvidence(let value):
            // Compatibility validation rejects duplicate claims before this
            // point; reduction also makes the restore primitive non-trapping.
            claimSelections = value.pairs.reduce(into: [:]) { $0[$1.claimID] = Set($1.evidenceIDs) }
        case .logicState(let value): logicState = value.finalState; violatedRuleID = value.violatedRuleID
        }
        confidenceResponseIdentity = confidence == nil ? nil : responseDraftIdentity
    }
}

/// A proposed transition is retained independently of the visible source item.
/// Its exact IDs survive failed writes; accepted-but-unverified bytes can only
/// be repaired as this same transition, never overwritten by the old editor.
@MainActor
private final class NFGeneratedAdvanceIntent {
    let source: NFGeneratedPracticeDraft
    var target: NFGeneratedPracticeDraft
    let command: NFSessionWriterCommand
    let learnerEnded: Bool
    let sourceFingerprint: String
    init(source: NFGeneratedPracticeDraft, target: NFGeneratedPracticeDraft,
         command: NFSessionWriterCommand, learnerEnded: Bool, sourceFingerprint: String) {
        self.source = source; self.target = target; self.command = command
        self.learnerEnded = learnerEnded; self.sourceFingerprint = sourceFingerprint
    }
}

private struct NFGeneratedCheckpointContinuation {
    let command: NFSessionWriterCommand
    let sourceFingerprint: String
    let sourceAttemptID: UUID?
    let targetFingerprint: String
    let targetAttemptID: UUID?
}

extension AIGeneratedPracticeRuntime {
    func nextAsync(store: AppStore, expectedAttemptID: UUID? = nil) async {
        guard expectedAttemptID == nil || expectedAttemptID == pendingAttemptID else { return }
        if pendingGeneratedAdvance != nil { await retryAdvanceAsync(store: store); return }
        guard await waitForGeneratedSubmissionBoundary(allowActiveSubmission: true), canAdvanceFeedback,
              expectedAttemptID == nil || expectedAttemptID == pendingAttemptID else { return }
        await advanceGeneratedAsync(store: store, ending: index + 1 >= result.questions.count)
    }

    private func advanceGeneratedAsync(store: AppStore, ending: Bool, learnerEnded: Bool = false) async {
        guard !hasExited, !isReadOnlyRecovery, ownsWriter, !isCommitInFlight,
              let command = try? sessionWriterCommand(), draftSaveGate.begin() else { return }
        isCommitInFlight = true
        stopTiming()
        defer { isCommitInFlight = false; draftSaveGate.finish() }
        do {
            guard pendingGeneratedAdvance == nil, let source = currentSnapshot(store: store) else {
                throw NFLocalSessionRepository.RepositoryError.staleRevision
            }
            let target = try makeAdvanceDraft(source: source, ending: ending, learnerEnded: learnerEnded)
            pendingGeneratedAdvance = .init(source: source, target: target, command: command,
                learnerEnded: learnerEnded, sourceFingerprint: generatedDraftFingerprint(includePhase: false))
            await acceptGeneratedAdvance(store: store)
        } catch { generatedSubmissionFailed(error) }
    }

    private func retryAdvanceAsync(store: AppStore) async {
        guard let pending = pendingGeneratedAdvance, !hasExited, !isReadOnlyRecovery,
              pending.command == (try? sessionWriterCommand()), !isCommitInFlight,
              await waitForGeneratedSubmissionBoundary(), draftSaveGate.begin() else { return }
        isCommitInFlight = true
        stopTiming()
        defer { isCommitInFlight = false; draftSaveGate.finish() }
        await acceptGeneratedAdvance(store: store)
    }

    private func acceptGeneratedAdvance(store: AppStore) async {
        guard let pending = pendingGeneratedAdvance else { return }
        await lifecycle.advanceAsync(command: pending.learnerEnded ? .endSession : .next,
            canMutate: {
                !self.hasExited && !self.isReadOnlyRecovery
                    && pending.command == (try? self.sessionWriterCommand())
                    && self.matchesAdvanceSource(pending.source)
            }, prepare: {
                pending.target.stage == 3 ? .summary(pending.target) : .item(pending.target)
            }, persist: { target in
                try await self.persistAdvanceDraft(target, intent: pending, store: store)
            }, publish: { accepted in
                self.publishAdvanceDraft(accepted, intent: pending)
            }, unavailable: { self.saveError = $0 }, failed: { self.generatedSubmissionFailed($0) })
    }

    @inline(never)
    private func makeAdvanceDraft(source: NFGeneratedPracticeDraft, ending: Bool,
        learnerEnded: Bool) throws -> NFGeneratedPracticeDraft {
        if ending {
            var terminal = source
            terminal.stage = 3
            terminal.terminalState = .init(endedEarly: learnerEnded, completedCount: completedActivityCount)
            if var state = terminal.runState {
                state.status = learnerEnded ? .endedEarly : .completed
                state.stopReason = learnerEnded ? .learnerEnded : .completedCount
                terminal.runState = state
            }
            return try terminal.releasingUnneededTerminalInventory()
        }
        guard result.questions.indices.contains(index + 1) else { throw NFLocalSessionRepository.RepositoryError.unavailableLaunch }
        let next = result.questions[index + 1].authoritativeExercise
        var state = source.runState
        if var value = state {
            value.slots.append(try NFGeneratedRunState.initial(exercise: next, index: index + 1).current)
            value.pendingUnscored = nil; value.nextHintIndex = 0
            value.status = .active
            state = value
        }
        let draft = NFGeneratedPracticeDraft(id: runID, ownerDeviceID: source.ownerDeviceID,
            result: source.result, request: source.request, index: index + 1, stage: 0,
            response: .initialDraft(for: next), confidence: nil, referenceRevealed: false,
            hintRevealed: false, correctness: source.correctness, lastScore: nil,
            pendingAttemptID: state?.current.attemptID ?? UUID(), shownAt: Date(), activeDuration: 0,
            mathWork: NFMathWorkPolicy.kind(for: next) == .estimateFirst ? .initial(for: next) : nil,
            dataInspection: .initial(for: next), scienceStudy: .initial(for: next),
            transferRelationship: .initial(for: next), runState: state)
        guard draft.valid else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
        return draft
    }

    private func persistAdvanceDraft(_ captured: NFGeneratedPracticeDraft, intent: NFGeneratedAdvanceIntent,
        store: AppStore) async throws -> NFGeneratedPracticeDraft {
        guard matchesAdvanceSource(intent.source) else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
        try store.localSessions.validateSessionCommand(intent.command, sessionID: runID)
        var draft = captured
        if draft.runState != nil { draft.runState?.revision = try NFSessionWriterRevision.next(after: acknowledgedRevision) }
        #if DEBUG
        try privateCheckpointWriteFailure?(draft)
        #endif
        let acknowledgement = try await store.localSessions.saveGeneratedSessionAsync(draft,
            command: intent.command, expectedRevision: acknowledgedRevision,
            expectedPayloadDigest: acknowledgedLegacyPayloadDigest)
        try store.localSessions.validateSessionCommand(intent.command, sessionID: runID)
        acknowledgeSnapshot(draft, store: store)
        intent.target = draft
        guard matchesAdvanceSource(intent.source) else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
        guard !acknowledgement.verificationNeeded else { throw NFLocalSessionRepository.RepositoryError.busy }
        return draft
    }

    private func publishAdvanceDraft(_ draft: NFGeneratedPracticeDraft, intent: NFGeneratedAdvanceIntent) {
        let interruptions = runState?.interruptionCount
        result = draft.result; request = draft.request
        index = draft.index
        prepareInteraction()
        applyGeneratedDraftFields(draft)
        if var state = runState, !state.isTerminal {
            state.interruptionCount = max(state.interruptionCount, interruptions ?? 0)
            state.status = isPaused ? .suspended : .active
            runState = state
        }
        isDurablyPrepared = true
        activeSegmentStart = nil
        pendingGeneratedAdvance = nil
        checkpointContinuation = .init(command: intent.command,
            sourceFingerprint: intent.sourceFingerprint, sourceAttemptID: intent.source.pendingAttemptID,
            targetFingerprint: generatedDraftFingerprint(includePhase: false), targetAttemptID: pendingAttemptID)
        saveError = nil
    }

    private func matchesAdvanceSource(_ draft: NFGeneratedPracticeDraft) -> Bool {
        runID == draft.id && index == draft.index && pendingAttemptID == draft.pendingAttemptID
            && makeResponse() == draft.response && confidence == draft.confidence
            && selfCheckReferenceRevealed == draft.referenceRevealed
            && hasRevealedCoaching == draft.hintRevealed
            && showsCoaching == (draft.hintExpanded ?? draft.hintRevealed)
            && mathWork == draft.mathWork && traceInspection == draft.traceInspection
            && dataInspection == draft.dataInspection && scienceStudy == draft.scienceStudy
            && transferRelationship == draft.transferRelationship
    }

    private func canFollowAcceptedAdvance(command: NFSessionWriterCommand,
        sourceFingerprint: String, sourceAttemptID: UUID?) -> Bool {
        guard let continuation = checkpointContinuation else { return false }
        return continuation.command == command && continuation.sourceFingerprint == sourceFingerprint
            && continuation.sourceAttemptID == sourceAttemptID
            && continuation.targetFingerprint == generatedDraftFingerprint(includePhase: false)
            && continuation.targetAttemptID == pendingAttemptID
    }
}

extension AIGeneratedPracticeRuntime {
    private func prepareUnscoredIntent(_ outcome: NFGeneratedRunState.Outcome, response: NFExerciseResponse) {
                pendingUnscored = outcome; preparedResponse = response
                if var state = runState {
                    state.pendingUnscored = outcome
                    if outcome == .revealed, !state.current.assistance.contains(where: { $0.kind == .workedSolution }) {
                        state.slots[state.slots.count - 1].assistance.append(.init(id: UUID(), kind: .workedSolution,
                            stage: state.nextHintIndex + 1, activeOffset: activeDuration,
                            generatorVersion: exercise.generatorVersion))
                    }
                    runState = state
                }
    }
}

extension AIGeneratedPracticeRuntime {
    func requestHintAsync(store: AppStore, expectedAttemptID: UUID? = nil, expectedHintIndex: Int? = nil) async {
        guard await waitForGeneratedSubmissionBoundary(), canEditDraft,
              expectedAttemptID == nil || expectedAttemptID == pendingAttemptID,
              expectedHintIndex == nil || expectedHintIndex == hintRequestIndex else { return }
        if hintRequestIndex >= activeHintLadder.count {
            await revealSolutionAsync(store: store)
        } else {
            // Intermediate hint persistence remains its named migration slice.
            requestHint(store: store, expectedAttemptID: expectedAttemptID, expectedHintIndex: expectedHintIndex)
        }
    }

    func skipAsync(store: AppStore, expectedAttemptID: UUID? = nil) async {
        guard await waitForGeneratedSubmissionBoundary(),
              expectedAttemptID == nil || expectedAttemptID == pendingAttemptID,
              canSkip || pendingUnscored == .skipped else { return }
        await saveUnscoredAsync(.skipped, store: store)
        if !Task.isCancelled, stage == 2, pendingUnscored == .skipped, saveError == nil {
            await nextAsync(store: store, expectedAttemptID: pendingAttemptID)
        }
    }

    func revealSolutionAsync(store: AppStore) async {
        guard await waitForGeneratedSubmissionBoundary(), canRevealSolution || pendingUnscored == .revealed else { return }
        await saveUnscoredAsync(.revealed, store: store)
    }

    private func saveUnscoredAsync(_ outcome: NFGeneratedRunState.Outcome, store: AppStore) async {
        guard ownsWriter, isDurablyPrepared, !isReadOnlyRecovery, !hasExited, !isCommitInFlight,
              pendingGeneratedAdvance == nil, pendingGeneratedSubmission == nil,
              outcome == .skipped || outcome == .revealed,
              pendingUnscored == nil || pendingUnscored == outcome,
              !hasUnexpectedPreparedResponseEdit, let attemptID = pendingAttemptID,
              let command = try? sessionWriterCommand(), draftSaveGate.begin() else { return }
        isCommitInFlight = true
        stopTiming()
        defer { isCommitInFlight = false; draftSaveGate.finish() }
        let response = preparedResponse ?? makeResponse()
        await lifecycle.commitUnscoredAsync(
            canMutate: {
                !self.hasExited && !self.isReadOnlyRecovery && command == (try? self.sessionWriterCommand())
                    && attemptID == self.pendingAttemptID && !self.hasUnexpectedPreparedResponseEdit
            }, receipt: {
                guard let record = store.attempts.first(where: { $0.id == attemptID }) else { return .absent }
                return self.matchesUnscoredReceipt(record, outcome: outcome, response: response, store: store) ? .matching : .conflicting
            }, prepare: {
                self.prepareUnscoredIntent(outcome, response: response)
            }, persistPrepared: {
                guard let draft = self.currentSnapshot(store: store) else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
                try await self.persistGeneratedSubmission(draft, command: command, store: store)
            }, save: {
                try await self.persistUnscoredReceipt(outcome, response: response, command: command, store: store)
            }, persistAndPublishFeedback: {
                try await self.persistUnscoredFeedback(outcome, command: command, store: store)
            }, conflictingReceipt: {
                do {
                    try await self.persistUnscoredReceipt(outcome, response: response, command: command,
                        store: store, conflictRecoveryOnly: true)
                } catch NFLocalSessionRepository.RepositoryError.conflictingAttempt {
                    self.unavailableReason = NFGeneratedPracticeCompatibility.unavailableMessage
                    self.isReadOnlyRecovery = true
                    return
                }
            }, failed: { self.generatedSubmissionFailed($0) })
    }

    private func persistUnscoredReceipt(_ outcome: NFGeneratedRunState.Outcome,
        response: NFExerciseResponse, command: NFSessionWriterCommand, store: AppStore,
        conflictRecoveryOnly: Bool = false) async throws {
        guard let attemptID = pendingAttemptID else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
        try await store.saveGeneratedSkippedExerciseAsync(command: command, runID: runID,
            attemptID: attemptID, sessionID: attemptSessionID, generationID: result.provenance.requestID,
            exercise: exercise, response: response, shownAt: shownAt, activeDuration: accumulatedActiveDuration,
            revealedSolution: outcome == .revealed, hintCount: capturedSupportCount, mathWork: mathWork,
            traceInspection: traceInspection, dataInspection: dataInspection,
            scienceStudy: scienceStudy, transferRelationship: transferRelationship,
            conflictRecoveryOnly: conflictRecoveryOnly)
        #if DEBUG
        if !conflictRecoveryOnly { receiptWriteAcknowledged?() }
        #endif
    }

    private func persistUnscoredFeedback(_ outcome: NFGeneratedRunState.Outcome,
        command: NFSessionWriterCommand, store: AppStore) async throws {
        guard var draft = currentSnapshot(store: store), draft.stage == 1,
              draft.pendingUnscored == outcome, draft.lastScore == nil,
              draft.scoredResponse == draft.response else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
        if var state = draft.runState {
            state.slots[state.slots.count - 1].outcome = outcome
            draft.runState = state
        }
        draft.stage = 2
        try await persistGeneratedSubmission(draft, publication: .unscored(outcome), command: command, store: store)
    }
}

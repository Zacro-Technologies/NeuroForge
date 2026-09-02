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

struct AIStudioView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var lab: TrainingLab = .logicDebugging
    @State private var field: STEMField = .general
    @State private var customTopic = ""
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
    @State private var practiceRestoresProgress = true
    @State private var showsQuestionReview = false
    @State private var selectedStarterSetID: String?
    @State private var showsStarterCatalog = false
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
                    restoresProgress: practiceRestoresProgress
                )
                    .environment(store)
            }
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
                remove: removeRecentSet
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
        Button("Review") { reopenRecentSet(record, startPractice: false) }
            .buttonStyle(.bordered)
        Button("Practice") { reopenRecentSet(record, startPractice: true) }
            .buttonStyle(.borderedProminent)
            .tint(NFTheme.controlTint(for: "indigo"))
            .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
    }

    private var recoverableGenerationRecords: [AIGenerationRecord] {
        Array(store.aiGenerations.lazy.filter { $0.recoverableResult() != nil }.prefix(5))
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
        guard let recovered = record.recoverableResult(),
              let recoveredRequest = recoveredRequest(for: record, result: recovered) else {
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
            let attemptedIDs = Set(attempts(for: record).map(\.itemID))
            let questionIDs = Set(recovered.questions.map(\.id))
            practiceRestoresProgress = !questionIDs.isSubset(of: attemptedIDs)
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
        do {
            try store.discardAIGenerationPayload(id: record.id)
        } catch {
            generationError = NFAppLocalization.localized(
                "The question set could not be removed. Try again.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Error after removing a recoverable generated question set."
            )
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
            Label("Customize", systemImage: "slider.horizontal.3").font(.title2.bold())

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                Picker("Reasoning lab", selection: $lab) {
                    ForEach(TrainingLab.allCases) { lab in Text(lab.title).tag(lab) }
                }.pickerStyle(.menu)

                Picker("Field", selection: $field) {
                    ForEach(STEMField.allCases) { field in Text(field.title).tag(field) }
                }.pickerStyle(.menu)

                Picker("Question form", selection: $style) {
                    ForEach(availableStyles) { style in Text(style.title).tag(style) }
                }.pickerStyle(.menu)

                Stepper(NFAppLocalization.formattedQuestionCount(count), value: $count, in: 1...10)
            }

            Text("Topic")
                .font(.subheadline.weight(.semibold))
            TextField("e.g. limiting reagents, induction proofs, or graph traversal", text: $customTopic)
                .textFieldStyle(.roundedBorder)
            TextField("Learning objective (optional)", text: $objective, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Difficulty").font(.subheadline.weight(.semibold)); Spacer(); Text(difficultyLabel).foregroundStyle(.secondary) }
                Slider(value: $difficulty, in: 0.15...0.9, step: 0.05).tint(NFTheme.rose)
            }

            if availableStyles.count < suggestedStyles.count {
                Label("Question forms are limited to those supported by the selected material.", systemImage: "checkmark.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .nfCard()
    }

    private var materialCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Use your material", systemImage: "doc.text.magnifyingglass").font(.title2.bold())
            Text(store.profileSnapshot.aiMode == .automatic
                ? "Optional. Sources set to Question Writer + offline can use approved excerpts; prose sources can also create questions offline."
                : "Optional. Select sources with complete prose statements to build cited recall practice offline.")
                .font(.subheadline).foregroundStyle(.secondary)

            if store.documents.isEmpty {
                HStack {
                    Text("No study material ready yet.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Import in Library") { store.requestDocumentImport(); dismiss() }.buttonStyle(.bordered)
                }
            } else {
                ForEach(store.documents) { document in
                    let selected = selectedDocumentIDs.contains(document.id)
                    let isEligible = documentIsEligibleForCurrentRoute(document)
                    Button {
                        if selected { selectedDocumentIDs.remove(document.id) } else { selectedDocumentIDs.insert(document.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected ? "checkmark.square.fill" : "square")
                                .foregroundStyle(selected ? NFTheme.indigoForeground : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(document.filename).font(.headline).lineLimit(1)
                                Text(documentStatus(document)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12).background(selected ? NFTheme.indigo.opacity(0.08) : .primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEligible)
                    .accessibilityLabel(document.filename)
                    .accessibilityValue(
                        isEligible
                            ? documentStatus(document)
                            : NFAppLocalization.localized("No material compatible with the selected route", locale: NFAppLocalization.preferredLocale, comment: "Source-study document status when an import has no chunks usable by the active authoring route.")
                    )
                    .nfSelectionAccessibility(selected)
                }
                if !store.documents.contains(where: documentIsEligibleForCurrentRoute) {
                    Text(store.profileSnapshot.aiMode == .automatic
                        ? "Import a source with extractable text, structured data, code, or locally recognized image text."
                        : "Choose a source containing complete prose statements for offline authoring.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .nfCard()
    }

    private var generateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Create your set", systemImage: "wand.and.stars").font(.title2.bold())
            Text(generationSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !selectedDocumentIDs.isEmpty {
                Label {
                    Text(shortcutAuthoringRequested
                        ? "Before the Shortcut opens, you’ll approve up to four excerpts. Original files stay on this device."
                        : "Selected material stays on this device and creates cited questions offline. To use approved excerpts with Question Writer, choose Question Writer + offline for each source in Library.")
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
                Button("Create offline instead") {
                    generationTask = Task { await generate(preferShortcut: false) }
                }
                .buttonStyle(.bordered)
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
            if resultNeedsSave {
                Label("Save this set before starting practice.", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Retry saving") { retrySavingCurrentSet() }
                    .buttonStyle(.borderedProminent)
                    .tint(NFTheme.controlTint(for: "indigo"))
                    .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
            }
            Button(practiceResult == nil ? "No usable questions in this set" : "Start practice") {
                if let result = practiceResult {
                    let attemptedIDs = Set(
                        store.attempts
                            .filter { $0.generationID == result.provenance.requestID }
                            .map(\.itemID)
                    )
                    practiceRestoresProgress = !Set(result.questions.map(\.id)).isSubset(of: attemptedIDs)
                }
                showPractice = true
            }
            .buttonStyle(.borderedProminent)
            .tint(NFTheme.controlTint(for: "indigo"))
            .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(practiceResult == nil || resultNeedsSave)
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
        guard !isGenerating else { return }
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
    let remove: (AIGenerationRecord) -> Void

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
                remove(record)
                pendingDeletionID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletionID = nil }
        } message: {
            Text("This removes the retained prompts and reference answers for the set. Its metadata and your attempt history remain in your private history and exports.")
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
                do {
                    try store.deleteAIGenerationAttempts(id: id)
                } catch {
                    historyError = NFAppLocalization.localized(
                        "The attempt history could not be deleted. Try again.",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Error shown in generated-set history after attempt deletion fails."
                    )
                }
                pendingAttemptDeletionID = nil
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
        let result = record.recoverableResult()
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
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label(
                                        attempt.isCorrect ? "Matched" : "Needs review",
                                        systemImage: attempt.isCorrect ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"
                                    )
                                    .foregroundStyle(attempt.isCorrect ? NFTheme.mintForeground : NFTheme.amberForeground)
                                    Spacer()
                                    Text(attempt.submittedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Text(attempt.prompt).font(.subheadline).lineLimit(3)
                                if !attempt.response.isEmpty {
                                    LabeledContent("Your answer", value: attempt.response)
                                        .font(.caption)
                                }
                                Text(NFAppLocalization.localized(
                                    "\(attempt.deterministicCredit.formatted(.percent.precision(.fractionLength(0)))) task credit · confidence: \(NFAIGenerationHistoryQuery.confidenceTitle(attempt.confidenceRaw))",
                                    comment: "Generated-practice attempt row with task credit and localized confidence."
                                ))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
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
    let result: NFAuthoringResult
    let request: NFAuthoringRequest
    private(set) var index = 0
    // 0 response, 1 confidence, 2 feedback, 3 summary. Self-check adds
    // stage 4 for reference comparison after confidence is recorded.
    private(set) var stage = 0
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
    var violatedRuleID: String?
    var showsCoaching = false
    private(set) var confidence: ConfidenceLevel?
    private(set) var correctness: [Bool] = []
    private(set) var lastScore: NFExerciseScoringResult?
    var saveError: String?
    private var pendingAttemptID: UUID?
    private var shownAt = Date()
    private var didRestoreDurableProgress = false

    init(result: NFAuthoringResult, request: NFAuthoringRequest) {
        self.result = result
        self.request = request
        prepareInteraction()
    }

    var question: NFAuthoredQuestion { result.questions[index] }
    var exercise: NFExercise { question.authoritativeExercise }
    var isComparingSelfCheck: Bool {
        guard stage == 4 else { return false }
        if case .selfCheck = exercise.interaction { return true }
        return false
    }
    var hasUnsavedWork: Bool {
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
        if case .selfCheck = exercise.interaction {
            if stage == 4 {
                return selfCheckReferenceRevealed && selfCheckRating != nil
            }
            return !selfCheckReflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return responseValidation.isValid
    }

    var responseValidation: NFExerciseResponseValidation {
        NFExerciseResponseValidator.validate(
            makeResponse(),
            for: exercise.interaction,
            localeIdentifier: exercise.localeIdentifier
        )
    }

    var responseValidationMessage: String? {
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

    func submit() {
        guard stage == 0, canSubmit else { return }
        stage = 1
    }

    func editResponse() {
        guard stage == 1 else { return }
        confidence = nil
        selfCheckReferenceRevealed = false
        selfCheckRating = nil
        stage = 0
    }

    func chooseConfidence(_ value: ConfidenceLevel, store: AppStore) {
        guard stage == 1 else { return }
        confidence = value
        if case .selfCheck = exercise.interaction {
            selfCheckReferenceRevealed = true
            stage = 4
            return
        }
        persistAttempt(store: store)
    }

    func saveSelfCheck(store: AppStore) {
        guard isComparingSelfCheck, canSubmit, confidence != nil else { return }
        persistAttempt(store: store)
    }

    private func persistAttempt(store: AppStore) {
        guard let confidence else { return }
        let response = makeResponse()
        let score = NFExerciseScoringEngine.score(response, for: exercise)
        let attemptID = pendingAttemptID ?? UUID()
        pendingAttemptID = attemptID
        do {
            try store.saveAuthoredExerciseAttempt(
                attemptID: attemptID,
                generationID: result.provenance.requestID,
                question: question,
                response: response,
                score: score,
                confidence: confidence,
                sourceDocumentIDs: result.provenance.sourceDocumentIDs,
                shownAt: shownAt,
                activeDuration: max(0, Date().timeIntervalSince(shownAt))
            )
            correctness.append(score.isCorrect)
            lastScore = score
            saveError = nil
            stage = 2
        } catch {
            saveError = NFAppLocalization.localized("Your answer remains on screen. Try saving it again.",
                locale: NFAppLocalization.preferredLocale,
                comment: "AI Practice Studio save error; the learner's typed answer remains visible for another save attempt."
            )
        }
    }

    func next() {
        if index + 1 >= result.questions.count { stage = 3; return }
        index += 1
        stage = 0
        prepareInteraction()
    }

    func restoreDurableProgress(from attempts: [AttemptRecord]) {
        guard !didRestoreDurableProgress else { return }
        didRestoreDurableProgress = true
        let generationID = result.provenance.requestID
        let matching = attempts.filter { attempt in
            (attempt.generationID == generationID || attempt.sessionID == generationID)
                && result.questions.contains(where: { $0.id == attempt.itemID })
                && !attempt.wasSkipped
        }
        let latestByQuestion = Dictionary(grouping: matching, by: \.itemID).compactMapValues {
            $0.max { lhs, rhs in
                if lhs.submittedAt == rhs.submittedAt { return lhs.id.uuidString < rhs.id.uuidString }
                return lhs.submittedAt < rhs.submittedAt
            }
        }
        correctness = result.questions.compactMap { latestByQuestion[$0.id]?.isCorrect }
        if let firstIncomplete = result.questions.firstIndex(where: { latestByQuestion[$0.id] == nil }) {
            index = firstIncomplete
            stage = 0
            prepareInteraction()
        } else {
            stage = 3
        }
    }

    func moveStep(from index: Int, offset: Int) {
        let destination = index + offset
        guard orderedStepIDs.indices.contains(index), orderedStepIDs.indices.contains(destination) else { return }
        orderedStepIDs.swapAt(index, destination)
    }

    private func prepareInteraction() {
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
        confidence = nil
        lastScore = nil
        pendingAttemptID = nil
        shownAt = Date()
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
                finalState: logicState,
                violatedRuleID: violatedRuleID
            ))
        }
    }
}

enum NFAIGeneratedPracticeCommandPolicy {
    static func resolve(stage: Int, canSubmit: Bool) -> NFSessionCommandCapabilities {
        switch stage {
        case 0, 4:
            return NFSessionCommandCapabilities(
                canAdvance: canSubmit,
                canTogglePause: false,
                canShowScratchpad: false
            )
        case 2:
            return NFSessionCommandCapabilities(
                canAdvance: true,
                canTogglePause: false,
                canShowScratchpad: false
            )
        default:
            return .inactive
        }
    }
}

private struct AIGeneratedPracticeView: View {
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
    @State private var runtime: AIGeneratedPracticeRuntime
    @State private var showReport = false
    @State private var confirmsLeavingDraft = false
    @FocusState private var responseFocus: ResponseFocus?
    private let restoresProgress: Bool

    private var commandCapabilities: NFSessionCommandCapabilities {
        NFAIGeneratedPracticeCommandPolicy.resolve(
            stage: runtime.stage,
            canSubmit: runtime.canSubmit
        )
    }

    init(
        result: NFAuthoringResult,
        request: NFAuthoringRequest,
        restoresProgress: Bool = true
    ) {
        _runtime = State(initialValue: AIGeneratedPracticeRuntime(result: result, request: request))
        self.restoresProgress = restoresProgress
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                Group {
                    switch runtime.stage {
                    case 0, 4: questionView
                    case 1: confidenceView
                    case 2: feedbackView
                    default: summaryView
                    }
                }
            }
            .navigationTitle("Question-set practice")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if runtime.hasUnsavedWork {
                            confirmsLeavingDraft = true
                        } else {
                            dismiss()
                        }
                    }
                }
                if runtime.stage != 3 {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showReport = true } label: {
                            Label("Report item", systemImage: "exclamationmark.bubble")
                        }
                    }
                }
            }
        }
        .nfDesktopPresentationFrame(minWidth: 400, idealWidth: 760, minHeight: 600, idealHeight: 800)
        .interactiveDismissDisabled(runtime.hasUnsavedWork)
        .onAppear {
            if restoresProgress {
                runtime.restoreDurableProgress(from: store.attempts)
            }
            sessionCommands.activate(
                requestID: runtime.request.id,
                capabilities: commandCapabilities
            )
            focusFirstResponseFieldIfNeeded()
        }
        .onDisappear {
            sessionCommands.deactivate(requestID: runtime.request.id)
        }
        .onChange(of: runtime.stage) { _, stage in
            if stage == 0 { focusFirstResponseFieldIfNeeded() }
            else { responseFocus = nil }
            sessionCommands.update(
                requestID: runtime.request.id,
                capabilities: commandCapabilities
            )
        }
        .onChange(of: runtime.canSubmit) { _, _ in
            sessionCommands.update(
                requestID: runtime.request.id,
                capabilities: commandCapabilities
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .neuroForgeAdvanceUniversalSession)) { notification in
            guard notification.object as? UUID == runtime.request.id,
                  commandCapabilities.canAdvance else { return }
            if runtime.stage == 2 {
                runtime.next()
            } else {
                submitCurrentResponse()
            }
        }
        .confirmationDialog(
            "Leave this question?",
            isPresented: $confirmsLeavingDraft,
            titleVisibility: .visible
        ) {
            Button("Keep working", role: .cancel) {}
            Button("Leave without saving", role: .destructive) { dismiss() }
        } message: {
            Text("Your current answer has not been saved. Completed answers will remain in your practice history.")
        }
        .alert("Save interrupted", isPresented: Binding(get: { runtime.saveError != nil }, set: { if !$0 { runtime.saveError = nil } })) { Button("OK", role: .cancel) {} } message: { Text(LocalizedStringKey(runtime.saveError ?? "")) }
        .sheet(isPresented: $showReport) {
            ReportAuthoredQuestionView(question: runtime.question, result: runtime.result)
                .environment(store)
        }
    }

    private var questionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        NFStatusPill(text: runtime.question.lab.shortTitle, symbol: runtime.question.lab.symbol, color: NFTheme.rose)
                        Spacer()
                        Text("\(runtime.index + 1) / \(runtime.result.questions.count)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if let presentation = runtime.question.presentationEnhancement {
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
                } else if !runtime.question.context.isEmpty {
                    NFFormattedLearningText(runtime.question.context, font: .subheadline)
                        .foregroundStyle(.secondary)
                }
                NFFormattedLearningText(
                    runtime.question.prompt,
                    font: .system(.title2, design: .rounded, weight: .bold)
                )
                .accessibilityHeading(.h1)
                authoredResponseView
                Button {
                    runtime.showsCoaching.toggle()
                } label: {
                    Label(
                        runtime.showsCoaching
                            ? NFAppLocalization.localized("Hide coaching hint", locale: NFAppLocalization.preferredLocale, comment: "Button that hides a practice-question coaching hint.")
                            : NFAppLocalization.localized("Show coaching hint", locale: NFAppLocalization.preferredLocale, comment: "Button that reveals a bounded practice-question coaching hint."),
                        systemImage: runtime.showsCoaching ? "lightbulb.slash" : "lightbulb"
                    )
                }
                .buttonStyle(.bordered)
                if runtime.showsCoaching {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NFAppLocalization.localized("Hint", locale: NFAppLocalization.preferredLocale, comment: "Heading for a personal-practice coaching hint."))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .accessibilityHeading(.h2)
                        NFFormattedLearningText(
                            runtime.question.presentationEnhancement?.coachingHint ?? runtime.question.hint
                        )
                    }
                    .nfCard(cornerRadius: 14, padding: 12)
                }
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
                    runtime.isComparingSelfCheck
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
                .disabled(!runtime.canSubmit)
                .keyboardShortcut(.defaultAction)
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
            }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Arrange the steps").font(.headline)
                ForEach(Array(runtime.orderedStepIDs.enumerated()), id: \.element) { index, id in
                    if let step = schema.steps.first(where: { $0.id == id }) {
                        ViewThatFits(in: .horizontal) {
                            HStack { orderedStepContent(step.text, index: index) }
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.caption.bold().monospacedDigit())
                                        .frame(width: 26, height: 26)
                                        .background(.secondary.opacity(0.12), in: Circle())
                                        .accessibilityHidden(true)
                                    Text(step.text)
                                }
                                HStack { orderedStepMoveButtons(index: index) }
                            }
                        }
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityElement(children: .contain)
                    }
                }
            }

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
                        : NFAppLocalization.localized("Answer from memory. You will choose confidence before seeing the reference.", locale: NFAppLocalization.preferredLocale, comment: "Guidance shown before confidence and reference reveal for a self-check question.")
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Your answer", text: $runtime.selfCheckReflection, axis: .vertical)
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
            VStack(alignment: .leading, spacing: 14) {
                ForEach(schema.claims) { claim in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(claim.text).font(.headline)
                        ForEach(schema.evidence) { evidence in
                            let selected = runtime.claimSelections[claim.id, default: []].contains(evidence.id)
                            Button {
                                if selected {
                                    runtime.claimSelections[claim.id, default: []].remove(evidence.id)
                                } else {
                                    runtime.claimSelections[claim.id, default: []].insert(evidence.id)
                                }
                            } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                                    Text(evidence.text)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                            .background(selected ? NFTheme.indigo.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .nfSelectionAccessibility(selected)
                        }
                    }
                    .nfCard(cornerRadius: 16, padding: 14)
                }
            }

        case let .logicState(schema):
            VStack(alignment: .leading, spacing: 14) {
                ForEach(NFEstimateExactContract.orderedResponseKeys(for: schema), id: \.self) { key in
                    TextField("Response for \(NFEstimateExactContract.localizedResponseLabel(for: key))", text: Binding(
                        get: { runtime.logicState[key, default: ""] },
                        set: { runtime.logicState[key] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .focused($responseFocus, equals: .logic(key))
                    .submitLabel(.next)
                    .onSubmit { focusNextLogicField(after: key, schema: schema) }
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
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
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

    @ViewBuilder
    private func orderedStepContent(_ text: String, index: Int) -> some View {
        Text("\(index + 1)")
            .font(.caption.bold().monospacedDigit())
            .frame(width: 26, height: 26)
            .background(.secondary.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
        Text(text)
        Spacer(minLength: 8)
        orderedStepMoveButtons(index: index)
    }

    @ViewBuilder
    private func orderedStepMoveButtons(index: Int) -> some View {
        Button { runtime.moveStep(from: index, offset: -1) } label: {
            Label("Move earlier", systemImage: "arrow.up")
                .labelStyle(.iconOnly)
        }
        .disabled(index == 0)
        .accessibilityHint("Moves this step earlier in the answer order")
        Button { runtime.moveStep(from: index, offset: 1) } label: {
            Label("Move later", systemImage: "arrow.down")
                .labelStyle(.iconOnly)
        }
        .disabled(index == runtime.orderedStepIDs.count - 1)
        .accessibilityHint("Moves this step later in the answer order")
    }

    private func selfCheckTitle(_ rating: NFSelfCheckRating) -> String {
        switch rating {
        case .matched: NFAppLocalization.localized("Matched", locale: NFAppLocalization.preferredLocale, comment: "Self-check rating indicating the learner's recall matched the reference.")
        case .partiallyMatched: NFAppLocalization.localized("Partially matched", locale: NFAppLocalization.preferredLocale, comment: "Self-check rating indicating partial agreement with the reference.")
        case .notYet: NFAppLocalization.localized("Not yet", locale: NFAppLocalization.preferredLocale, comment: "Self-check rating indicating recall did not yet match the reference.")
        }
    }

    private var confidenceView: some View {
        ScrollView {
            VStack(spacing: 18) {
                NFIconTile(symbol: "gauge.with.dots.needle.50percent", color: NFTheme.cyan, size: 66)
                Text("How confident are you?").font(.title.bold())
                ForEach(ConfidenceLevel.allCases) { level in
                    Button { runtime.chooseConfidence(level, store: store) } label: { HStack { ConfidenceGlyph(level: level); Text(level.title); Spacer(); Image(systemName: "chevron.right") }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain)
                }
                Button("Edit answer") { runtime.editResponse() }
                    .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth: 580)
            .frame(maxWidth: .infinity)
        }
    }

    private var feedbackView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let score = runtime.lastScore {
                    Label(
                        score.feedback.title,
                        systemImage: score.isCorrect ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"
                    )
                    .font(.title.bold())
                    .foregroundStyle(score.isCorrect ? NFTheme.mintForeground : NFTheme.amberForeground)
                    LabeledContent("Score", value: score.credit.formatted(.percent.precision(.fractionLength(0))))
                    .nfCard(cornerRadius: 16, padding: 14)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reference answer").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    NFFormattedLearningText(runtime.question.correctAnswer)
                }
                .nfCard(cornerRadius: 16, padding: 14)
                NFFormattedLearningText(runtime.question.explanation, font: .title3)
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
                Button(runtime.index + 1 == runtime.result.questions.count ? "View summary" : "Next challenge") {
                    runtime.next()
                }
                .buttonStyle(.borderedProminent)
                .tint(NFTheme.controlTint(for: "indigo"))
                .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
    }

    private var summaryView: some View {
        ScrollView {
            VStack(spacing: 18) {
                NFIconTile(symbol: "checkmark.seal.fill", color: NFTheme.mint, size: 78)
                Text("Practice complete").font(.largeTitle.bold())
                Text(NFAppLocalization.localized(
                    "\(runtime.correctness.filter { $0 }.count) of \(NFAppLocalization.formattedResponseCount(runtime.correctness.count)) matched the provided reference",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Generated-practice summary with matched-response count and localized total response count."
                ))
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
        if runtime.isComparingSelfCheck {
            runtime.saveSelfCheck(store: store)
        } else if runtime.stage == 0 {
            runtime.submit()
        }
    }

    private func focusFirstResponseFieldIfNeeded() {
        #if os(macOS)
        guard runtime.stage == 0 else { return }
        Task { @MainActor in
            await Task.yield()
            switch runtime.exercise.interaction {
            case .numeric: responseFocus = .numericValue
            case .shortText: responseFocus = .shortText
            case .selfCheck: responseFocus = .selfCheck
            case let .logicState(schema):
                responseFocus = NFEstimateExactContract.orderedResponseKeys(for: schema).first.map(ResponseFocus.logic)
            default: responseFocus = nil
            }
        }
        #endif
    }

    private func focusNextLogicField(after key: String, schema: NFLogicStateResponseSchema) {
        let keys = NFEstimateExactContract.orderedResponseKeys(for: schema)
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

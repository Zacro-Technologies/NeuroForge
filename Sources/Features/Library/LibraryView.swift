import SwiftUI
import UniformTypeIdentifiers

struct NFImportReadinessCounts: Equatable, Sendable {
    private(set) var readyCount = 0
    private(set) var needsReprocessingCount = 0

    mutating func record(indexState: String) {
        if indexState == "ready" {
            readyCount += 1
        } else {
            needsReprocessingCount += 1
        }
    }
}

enum NFInterruptedImportSummary: Equatable, Sendable {
    case noSavedSources
    case allSavedSourcesReady
    case needsReprocessing(count: Int, hasReadySources: Bool)

    static func classify(readyCount: Int, needsReprocessingCount: Int) -> Self {
        if needsReprocessingCount > 0 {
            return .needsReprocessing(
                count: needsReprocessingCount,
                hasReadySources: readyCount > 0
            )
        }
        return readyCount > 0 ? .allSavedSourcesReady : .noSavedSources
    }
}

enum NFDocumentPolicyMutationKind: Equatable, Sendable {
    case questionPrivacy
    case iCloudSync
}

/// A small value-state gate keeps the document AI and sync controls mutually
/// exclusive across their entire persistence and reconciliation lifecycle.
/// This prevents a rapid second change from racing a save already in flight.
struct NFDocumentPolicyMutationGate: Equatable, Sendable {
    private(set) var activeMutation: NFDocumentPolicyMutationKind?

    func beginning(_ mutation: NFDocumentPolicyMutationKind) -> Self? {
        guard activeMutation == nil else { return nil }
        return Self(activeMutation: mutation)
    }

    func finishing(_ mutation: NFDocumentPolicyMutationKind) -> Self {
        guard activeMutation == mutation else { return self }
        return Self(activeMutation: nil)
    }

    func isActive(_ mutation: NFDocumentPolicyMutationKind) -> Bool {
        activeMutation == mutation
    }
}

private struct NFImportBatchState {
    enum Status {
        case running
        case completed
        case cancelled
        case failed
    }

    var status: Status
    var totalCount: Int
    var processedCount: Int = 0
    var readyCount: Int = 0
    var needsReprocessingCount: Int = 0
    var currentFilename: String = ""
    var stage: NFDocumentImportStage = .copying
    var retryURLs: [URL] = []
}

struct NFDuplicateImportExistingSource: Equatable, Sendable {
    let id: UUID
    let filename: String
    let sizeBytes: Int64
    let localURL: URL
    let indexState: String
    let importedAt: Date
}

struct NFDuplicateImportInspection: Equatable, Sendable {
    let selectedFilename: String
    let selectedSizeBytes: Int64
    let fingerprint: String
    let existingSource: NFDuplicateImportExistingSource
}

enum NFDuplicateImportInspector {
    static func inspect(
        selectedURL: URL,
        existingSources: [NFDuplicateImportExistingSource]
    ) async throws -> NFDuplicateImportInspection? {
        try await Task.detached(priority: .userInitiated) {
            let didAccess = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess { selectedURL.stopAccessingSecurityScopedResource() }
            }

            let values = try selectedURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { return nil }
            let selectedSizeBytes = Int64(values.fileSize ?? 0)
            let candidateSources = existingSources.filter { $0.sizeBytes == selectedSizeBytes }
            guard !candidateSources.isEmpty else { return nil }

            let selectedFingerprint = try NFContentAddressedAssetHasher.sha256(
                fileURL: selectedURL,
                checkingCancellation: true
            )
            for source in candidateSources {
                try Task.checkCancellation()
                guard let existingFingerprint = try? NFContentAddressedAssetHasher.sha256(
                    fileURL: source.localURL,
                    checkingCancellation: true
                ), existingFingerprint == selectedFingerprint else { continue }
                return NFDuplicateImportInspection(
                    selectedFilename: selectedURL.lastPathComponent,
                    selectedSizeBytes: selectedSizeBytes,
                    fingerprint: selectedFingerprint,
                    existingSource: source
                )
            }
            return nil
        }.value
    }
}

enum NFDuplicateImportRecoveryChoice: Equatable, Sendable {
    case useExisting
    case replaceExisting
    case keepBoth
    case retryExisting
    case skip
}

enum NFDuplicateImportDisposition: Equatable, Sendable {
    case keepBoth
    case replace(existingDocumentID: UUID)
}

enum NFDuplicateImportReprocessingMethod: Equatable, Sendable {
    case localPDFOCR
    case extractText
}

enum NFDuplicateImportRecoveryPlan: Equatable, Sendable {
    case useExisting(documentID: UUID, remainingURLs: [URL])
    case importSelected(
        selectedURL: URL,
        disposition: NFDuplicateImportDisposition,
        remainingURLs: [URL]
    )
    case reprocessExisting(
        documentID: UUID,
        method: NFDuplicateImportReprocessingMethod,
        remainingURLs: [URL]
    )
    case skip(remainingURLs: [URL])
}

enum NFDuplicateImportRecoveryPlanningError: Error, Equatable, Sendable {
    case existingSourceUnavailable
}

/// Converts every user-facing duplicate choice into one explicit next step.
/// Requiring the existing document for choices that depend on it prevents a
/// stale duplicate sheet from silently degrading Replace into Keep Both.
enum NFDuplicateImportRecoveryPlanner {
    static func plan(
        choice: NFDuplicateImportRecoveryChoice,
        selectedURL: URL,
        existingSource: NFDuplicateImportExistingSource,
        remainingURLs: [URL],
        availableDocumentIDs: Set<UUID>
    ) throws -> NFDuplicateImportRecoveryPlan {
        switch choice {
        case .keepBoth:
            return .importSelected(
                selectedURL: selectedURL,
                disposition: .keepBoth,
                remainingURLs: remainingURLs
            )
        case .skip:
            return .skip(remainingURLs: remainingURLs)
        case .useExisting, .replaceExisting, .retryExisting:
            guard availableDocumentIDs.contains(existingSource.id) else {
                throw NFDuplicateImportRecoveryPlanningError.existingSourceUnavailable
            }
        }

        switch choice {
        case .useExisting:
            return .useExisting(
                documentID: existingSource.id,
                remainingURLs: remainingURLs
            )
        case .replaceExisting:
            return .importSelected(
                selectedURL: selectedURL,
                disposition: .replace(existingDocumentID: existingSource.id),
                remainingURLs: remainingURLs
            )
        case .retryExisting:
            return .reprocessExisting(
                documentID: existingSource.id,
                method: existingSource.localURL.pathExtension.lowercased() == "pdf"
                    ? .localPDFOCR
                    : .extractText,
                remainingURLs: remainingURLs
            )
        case .keepBoth, .skip:
            preconditionFailure("Choices independent of the existing source return above.")
        }
    }
}

/// Commits Replace as a small transaction: if the existing source cannot be
/// found or removed, the newly imported copy is rolled back before the error
/// reaches the recovery UI.
enum NFDuplicateImportReplacementTransaction {
    static func commit<ExistingSource, ImportedSource>(
        importedSource: ImportedSource,
        existingDocumentID: UUID,
        findExisting: (UUID) -> ExistingSource?,
        deleteExisting: (ExistingSource) throws -> Void,
        rollbackImported: (ImportedSource) throws -> Void
    ) throws {
        guard let existingSource = findExisting(existingDocumentID) else {
            try? rollbackImported(importedSource)
            throw NFDuplicateImportRecoveryPlanningError.existingSourceUnavailable
        }
        do {
            try deleteExisting(existingSource)
        } catch {
            try? rollbackImported(importedSource)
            throw error
        }
    }
}

private enum NFApprovedDuplicateImportAction {
    case keepBoth
    case replace(existingDocumentID: UUID)
}

private struct NFDuplicateImportReview: Identifiable {
    let id = UUID()
    let selectedURL: URL
    let inspection: NFDuplicateImportInspection
    let remainingURLs: [URL]
}

enum NFSourceReviewRotation {
    static let responseFormat = "sourceSelfCheck"

    static func isSourceReview(_ attempt: AttemptRecord) -> Bool {
        attempt.evidenceClassRaw == EvidenceClass.documentPractice.rawValue
            && [responseFormat, "selfCheck"].contains(attempt.responseFormatRaw)
            && !attempt.sourceDocumentIDsRaw.isEmpty && !attempt.sourceChunkIDsRaw.isEmpty
    }

    static func nextChunk(
        in chunks: [NFSourceChunk],
        attempts: [AttemptRecord],
        excluding excludedChunkID: String? = nil
    ) -> NFSourceChunk? {
        let ordered = chunks.sorted(by: precedes)
        guard !ordered.isEmpty else { return nil }

        let candidates: [NFSourceChunk]
        if let excludedChunkID, ordered.count > 1 {
            candidates = ordered.filter { $0.id != excludedChunkID }
        } else {
            candidates = ordered
        }

        let latestReviewDates = latestReviewDatesByChunk(from: attempts)
        if let unreviewed = candidates.first(where: { latestReviewDates[$0.id] == nil }) {
            return unreviewed
        }

        return candidates.min { lhs, rhs in
            let lhsDate = latestReviewDates[lhs.id] ?? .distantPast
            let rhsDate = latestReviewDates[rhs.id] ?? .distantPast
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return precedes(lhs, rhs)
        }
    }

    static func reviewedChunkIDs(from attempts: [AttemptRecord]) -> Set<String> {
        Set(latestReviewDatesByChunk(from: attempts).keys)
    }

    private static func latestReviewDatesByChunk(
        from attempts: [AttemptRecord]
    ) -> [String: Date] {
        attempts.reduce(into: [:]) { result, attempt in
            guard !attempt.wasSkipped,
                  attempt.evidenceClassRaw == EvidenceClass.documentPractice.rawValue,
                  isSourceReview(attempt) else { return }
            for chunkID in attempt.sourceChunkIDsRaw.split(separator: ",").map(String.init) {
                result[chunkID] = max(result[chunkID] ?? .distantPast, attempt.submittedAt)
            }
        }
    }

    private static func precedes(_ lhs: NFSourceChunk, _ rhs: NFSourceChunk) -> Bool {
        if lhs.documentID != rhs.documentID {
            return lhs.documentID.uuidString < rhs.documentID.uuidString
        }
        if lhs.ordinal != rhs.ordinal { return lhs.ordinal < rhs.ordinal }
        return lhs.id < rhs.id
    }
}

private struct NFSourceReviewRoute: Identifiable {
    let document: SourceDocumentRecord
    let chunkID: String
    let hasAlternative: Bool

    var id: String { "\(document.id.uuidString)|\(chunkID)" }
}

private enum NFSourceReviewPresentation: Identifiable {
    case practice(NFSourceReviewRoute)
    case saved(NFReadOnlyAttemptSnapshot)

    var id: String {
        switch self {
        case let .practice(route): "practice|\(route.id)"
        case let .saved(attempt): "saved|\(attempt.id.uuidString)"
        }
    }
}

/// Resolves an exact saved review only when every opaque identifier agrees.
/// A stale or forged route can therefore never fall through to a different
/// learner answer or a different personal source.
struct NFSourceReviewDestinationResolver {
    static func savedReview(
        for destination: NFSourceReviewDeepLinkDestination,
        documents: [SourceDocumentRecord],
        chunks: [SourceChunkRecord],
        attempts: [AttemptRecord]
    ) -> AttemptRecord? {
        guard let reviewID = destination.reviewID,
              let chunkID = destination.chunkID,
              documents.contains(where: { $0.id == destination.documentID }),
              chunks.contains(where: {
                  $0.id == chunkID && $0.documentID == destination.documentID
              }),
              let attempt = attempts.first(where: { $0.id == reviewID }),
              attempt.evidenceClassRaw == EvidenceClass.documentPractice.rawValue,
              NFSourceReviewRotation.isSourceReview(attempt) else {
            return nil
        }
        let documentIDs = Set(attempt.sourceDocumentIDsRaw
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) })
        let chunkIDs = Set(attempt.sourceChunkIDsRaw
            .split(separator: ",")
            .map(String.init))
        guard documentIDs.contains(destination.documentID),
              chunkIDs.contains(chunkID) else { return nil }
        return attempt
    }
}

private struct NFSourceReviewRecoveryNotice: Identifiable {
    enum Reason {
        case noSources
        case preparing
        case needsReprocessing
        case noReadableText
        case missingDestination
    }

    let id = UUID()
    let reason: Reason
    let documentID: UUID?
}

struct NFDocumentReadinessPresentation: Equatable, Sendable {
    let indexStatus: String
    let questionStatus: String

    static func make(
        indexState: String,
        chunkCount: Int,
        aiPolicy: DocumentAIPolicy,
        questionWriterEnabled: Bool
    ) -> Self {
        // Compatibility for callers that only distinguished Shortcut and offline authoring.
        make(indexState: indexState, chunkCount: chunkCount, aiPolicy: aiPolicy,
             aiMode: questionWriterEnabled ? .automatic : .onDeviceOnly)
    }

    static func make(
        indexState: String,
        chunkCount: Int,
        aiPolicy: DocumentAIPolicy,
        aiMode: AIMode
    ) -> Self {
        let indexStatus: String
        switch indexState {
        case "ready":
            indexStatus = NFAppLocalization.localized("Index ready", locale: NFAppLocalization.preferredLocale, comment: "Imported-source indexing status.")
        case "extracting":
            indexStatus = NFAppLocalization.localized("Index preparing", locale: NFAppLocalization.preferredLocale, comment: "Imported-source indexing status while processing.")
        default:
            indexStatus = NFAppLocalization.localized("Index needs reprocessing", locale: NFAppLocalization.preferredLocale, comment: "Imported-source indexing status after processing fails.")
        }

        let questionStatus: String
        if indexState != "ready" || chunkCount == 0 {
            questionStatus = NFAppLocalization.localized("Questions unavailable until indexing finishes", locale: NFAppLocalization.preferredLocale, comment: "Imported-source question availability while indexing is incomplete.")
        } else {
            switch aiPolicy {
            case .noAI:
                questionStatus = NFAppLocalization.localized("Source review only", locale: NFAppLocalization.preferredLocale, comment: "Imported-source availability when AI use is disabled.")
            case _ where aiMode == .disabled:
                questionStatus = NFAppLocalization.localized("AI off; offline study available", locale: NFAppLocalization.preferredLocale, comment: "Imported-source availability when the global AI preference is off.")
            case .privateCloudAllowed where aiMode == .automatic:
                questionStatus = NFAppLocalization.localized("Automatic AI allowed", locale: NFAppLocalization.preferredLocale, comment: "Imported-source permission to use the configured automatic AI route; this does not claim the provider is currently available.")
            case .privateCloudAllowed, .onDeviceOnly:
                questionStatus = NFAppLocalization.localized("On-device AI allowed", locale: NFAppLocalization.preferredLocale, comment: "Imported-source permission to use an available on-device model.")
            }
        }
        return Self(indexStatus: indexStatus, questionStatus: questionStatus)
    }
}

enum NFSourceAIAvailabilityPresentation {
    static func title(for policy: DocumentAIPolicy, locale: Locale = NFAppLocalization.preferredLocale) -> String {
        switch policy {
        case .privateCloudAllowed: NFAppLocalization.localized("Automatic AI", locale: locale, comment: "Source setting that permits the configured automatic AI route.")
        case .onDeviceOnly: NFAppLocalization.localized("On-device AI", locale: locale, comment: "Source setting that permits only on-device AI.")
        case .noAI: NFAppLocalization.localized("Source review only", locale: locale, comment: "Source setting that keeps reading and recall available without AI.")
        }
    }

    static func allowsNativeQuestions(aiMode: AIMode, sourcePolicy: DocumentAIPolicy) -> Bool {
        aiMode != .disabled && sourcePolicy != .noAI
    }

    static func allowsQuestionSet(
        aiMode: AIMode, sourcePolicy: DocumentAIPolicy, chunkCount: Int, isProcessing: Bool, hasProseRecall: Bool
    ) -> Bool {
        !isProcessing && chunkCount > 0 && sourcePolicy != .noAI
            && (allowsNativeQuestions(aiMode: aiMode, sourcePolicy: sourcePolicy) || hasProseRecall)
    }
}

struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @Environment(NFNavigationState.self) private var navigation
    @State private var searchText = ""
    @State private var importing = false
    @State private var importError: String?
    @State private var selectedReviewPresentation: NFSourceReviewPresentation?
    @State private var selectedDocumentInitialChunkID: String?
    @State private var sourceReviewRecoveryNotice: NFSourceReviewRecoveryNotice?
    @State private var pendingNextReviewAfterChunkID: String?
    @State private var importBatch: NFImportBatchState?
    @State private var importTask: Task<Void, Never>?
    @State private var duplicateImportReview: NFDuplicateImportReview?
    @State private var duplicateRecoveryInProgress = false
    @State private var duplicateRecoveryError: String?

    private var filteredDocuments: [SourceDocumentRecord] {
        store.searchDocuments(searchText)
    }

    var body: some View {
        NavigationStack(path: Binding(get: { navigation.sources }, set: { navigation.sources = $0 })) {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        NFSectionHeader(
                            "Turn reading into retrieval",
                            eyebrow: "Source library",
                            subtitle: "Import notes and documents, search inside them, and turn them into cited practice."
                        )
                        libraryHero
                        if importBatch != nil { importProgressCard }
                        reviewsCard
                        NavigationLink(value: NFSourceRoute.resources) {
                            Label("Saved and collections", systemImage: "folder.badge.plus")
                        }.buttonStyle(.bordered)
                        documentsSection
                        supportedTypes
                    }
                    .padding(20)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Sources")
            .searchable(text: $searchText, prompt: "Search filenames and source text")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        importing = true
                    } label: {
                        Label("Import", systemImage: "plus")
                    }
                    .disabled(importTask != nil)
                }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: supportedContentTypes,
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .navigationDestination(for: NFSourceRoute.self) { route in
                switch route {
                case .resources: NFStudyResourcesView()
                case .document(let documentID, let chunkID):
                    if let document = store.documents.first(where: { $0.id == documentID }) {
                        DocumentDetailView(document: document, initialSourceChunkID: chunkID)
                    } else {
                        ContentUnavailableView("Source unavailable", systemImage: "doc.questionmark", description: Text("The source may have been deleted. Your saved answers remain in History."))
                    }
                }
            }
            .sheet(item: $selectedReviewPresentation, onDismiss: presentPendingSourceReview) { presentation in
                switch presentation {
                case let .practice(route):
                    SourceReviewView(
                        document: route.document,
                        initialChunkID: route.chunkID,
                        onReviewAnother: route.hasAlternative ? { chunkID in
                            pendingNextReviewAfterChunkID = chunkID
                        } : nil
                    )
                        .environment(store)
                case let .saved(attempt):
                    NavigationStack {
                        NFAttemptReviewDetailView(attempt: attempt)
                    }
                }
            }
            .sheet(item: $duplicateImportReview) { review in
                NFDuplicateImportReviewView(
                    review: review,
                    retryInProgress: duplicateRecoveryInProgress,
                    retryError: duplicateRecoveryError,
                    onUseExisting: { resolveDuplicateUsingExisting(review) },
                    onReplaceExisting: { resolveDuplicateByReplacing(review) },
                    onKeepBoth: { resolveDuplicateByKeepingBoth(review) },
                    onRetryExisting: { retryExistingDuplicate(review) },
                    onCancel: { cancelDuplicateImport(review) }
                )
            }
            .alert("Import could not finish", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(LocalizedStringKey(importError ?? "Try an exported PDF or plain-text version."))
            }
            .alert(item: $sourceReviewRecoveryNotice) { notice in
                sourceReviewRecoveryAlert(notice)
            }
            .onAppear {
                removeOrphanedSourceReviewDrafts()
                presentRequestedImporterIfNeeded()
                presentRequestedLibraryDestinationIfNeeded()
            }
            .onChange(of: store.shouldPresentDocumentImporter) { _, _ in
                presentRequestedImporterIfNeeded()
            }
            .onChange(of: store.shouldOpenSourceReviews) { _, _ in
                scheduleRequestedLibraryDestinationPresentation()
            }
            .onChange(of: store.requestedLibraryDocumentID) { _, _ in
                scheduleRequestedLibraryDestinationPresentation()
            }
            .onChange(of: store.requestedSourceChunkID) { _, _ in
                scheduleRequestedLibraryDestinationPresentation()
            }
            .onChange(of: store.requestedSourceReviewID) { _, _ in
                scheduleRequestedLibraryDestinationPresentation()
            }
        }
    }

    private var libraryHero: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                libraryHeroIcon
                libraryHeroSummary
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 20) {
                libraryHeroIcon
                libraryHeroSummary
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nfCard(cornerRadius: 26)
    }

    private var libraryHeroIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [NFTheme.cyan.opacity(0.24), NFTheme.indigo.opacity(0.13)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(NFTheme.cyanForeground)
        }
        .frame(width: 100, height: 100)
        .accessibilityHidden(true)
    }

    private var libraryHeroSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(librarySourceCountTitle)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 8) {
                NFStatusPill(text: "Stored in NeuroForge", symbol: "internaldrive.fill", color: NFTheme.mint)
                NFStatusPill(text: "Search inside sources", symbol: "text.magnifyingglass", color: NFTheme.cyan)
            }
        }
    }

    @ViewBuilder
    private var importProgressCard: some View {
        if let batch = importBatch {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    NFIconTile(
                        symbol: batchNeedsAttention(batch) ? "exclamationmark.triangle.fill" : batch.status == .completed ? "checkmark.circle.fill" : "arrow.down.doc.fill",
                        color: batchNeedsAttention(batch) ? NFTheme.amber : NFTheme.cyan,
                        size: 46
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(importBatchTitle(batch))
                            .font(.headline)
                        Text(importBatchDetail(batch))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }

                ProgressView(
                    value: Double(batch.processedCount),
                    total: Double(max(1, batch.totalCount))
                )
                .tint(batch.status == .failed ? NFTheme.amber : NFTheme.cyan)

                HStack {
                    Text(
                        NFAppLocalization.localized("\(batch.processedCount) of \(batch.totalCount) complete",
                            locale: NFAppLocalization.preferredLocale,
                            comment: "Short progress for a multi-source local import; placeholders are the completed and total source counts."
                        )
                    )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    switch batch.status {
                    case .running:
                        Button("Cancel") { importTask?.cancel() }
                            .buttonStyle(.bordered)
                    case .failed, .cancelled:
                        Button("Retry unfinished") { startImport(batch.retryURLs) }
                            .buttonStyle(.borderedProminent)
                            .tint(NFTheme.controlTint(for: "indigo"))
                            .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                            .disabled(batch.retryURLs.isEmpty)
                        Button("Dismiss") { importBatch = nil }
                            .buttonStyle(.bordered)
                    case .completed:
                        Button("Dismiss") { importBatch = nil }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .nfCard(cornerRadius: 20, padding: 16)
            .accessibilityElement(children: .contain)
        }
    }

    private var librarySourceCountTitle: String {
        let count = store.documents.count
        switch count {
        case 0:
            return NFAppLocalization.localized("Turn your material into practice.", locale: NFAppLocalization.preferredLocale, comment: "Library hero title when no study sources have been imported.")
        case 1:
            return NFAppLocalization.localized("\(count) local source stored.", locale: NFAppLocalization.preferredLocale, comment: "Library hero title when exactly one study source is stored; the placeholder is the source count.")
        default:
            return NFAppLocalization.localized("\(count) local sources stored.", locale: NFAppLocalization.preferredLocale, comment: "Library hero title when multiple study sources are stored; the placeholder is the source count.")
        }
    }

    private var reviewsCard: some View {
        Button {
            if store.documents.isEmpty {
                importing = true
            } else {
                presentNextSourceReview()
            }
        } label: {
            HStack(spacing: 14) {
                NFIconTile(symbol: "clock.arrow.circlepath", color: NFTheme.indigo, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Source review")
                        .font(.headline)
                    Text(store.documents.isEmpty ? "Import a source to create questions from it." : "Recall before reopening the source")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: store.documents.isEmpty ? "plus.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(NFTheme.indigoForeground)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .nfCard(cornerRadius: 20, padding: 16)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Documents").font(.title2.bold())
                Spacer()
                if !store.documents.isEmpty {
                    Text("Stored locally")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if filteredDocuments.isEmpty {
                ContentUnavailableView {
                    Label(searchText.isEmpty ? "No documents yet" : "No matches", systemImage: "doc.text")
                } description: {
                    Text(searchText.isEmpty ? "Import local notes, web or rich text, data, notebooks, code, tables, PDFs, or images." : "Try another phrase from the filename or document content.")
                } actions: {
                    if searchText.isEmpty {
                        Button("Import a document") { importing = true }
                            .buttonStyle(.borderedProminent)
                            .tint(NFTheme.controlTint(for: "indigo"))
                            .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                    }
                }
                .frame(minHeight: 240)
                .nfCard()
            } else {
                ForEach(filteredDocuments) { document in
                    Button {
                        selectedDocumentInitialChunkID = nil
                        navigation.sources = [.document(document.id, chunkID: selectedDocumentInitialChunkID)]
                    } label: {
                        DocumentRow(document: document)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var supportedTypes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supported import formats")
                .font(.headline)
            FlowLayout(spacing: 8) {
                ForEach(supportedImportTypeLabels, id: \.id) { type in
                    Text(type.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.secondary.opacity(0.1), in: Capsule())
                }
            }
            DisclosureGroup("Import and text recognition") {
                Text("Import files up to 50 MB for offline reading and practice. Code and structured data are read as text and never run. Scanned PDFs use local OCR when you choose it; images use local OCR during import. New sources use Automatic AI. You can choose On-device AI or Source review only for each source.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
        .nfCard()
    }

    private var supportedImportTypeLabels: [(id: String, label: String)] {
        [
            ("pdf", NFAppLocalization.localized("PDF", locale: NFAppLocalization.preferredLocale, comment: "Supported study-material import format.")),
            ("text", NFAppLocalization.localized("Text", locale: NFAppLocalization.preferredLocale, comment: "Supported study-material import format.")),
            ("markdown", NFAppLocalization.localized("Markdown", locale: NFAppLocalization.preferredLocale, comment: "Supported study-material import format.")),
            ("latex", NFAppLocalization.localized("LaTeX", locale: NFAppLocalization.preferredLocale, comment: "Supported study-material import format.")),
            ("web-rich-text", NFAppLocalization.localized("HTML & RTF", locale: NFAppLocalization.preferredLocale, comment: "Supported study-material import formats.")),
            ("structured-data", NFAppLocalization.localized("Data & notebooks", locale: NFAppLocalization.preferredLocale, comment: "Supported study-material import formats including JSON, YAML, XML, TOML, and Jupyter notebooks.")),
            ("source-code", NFAppLocalization.localized("Source code", locale: NFAppLocalization.preferredLocale, comment: "Supported study-material import format.")),
            ("tables", NFAppLocalization.localized("CSV & TSV", locale: NFAppLocalization.preferredLocale, comment: "Supported study-material import formats.")),
            ("images", NFAppLocalization.localized("Images + OCR", locale: NFAppLocalization.preferredLocale, comment: "Supported image imports using local optical character recognition."))
        ]
    }

    private var supportedContentTypes: [UTType] {
        NFDocumentImportTypeRegistry.contentTypes
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            startImport(try result.get())
        } catch {
            importError = NFDiagnosticRedactor.userMessage(for: error, context: .documentImport)
        }
    }

    private func startImport(
        _ urls: [URL],
        approvedDuplicateActions: [String: NFApprovedDuplicateImportAction] = [:]
    ) {
        guard !urls.isEmpty else { return }
        importTask?.cancel()
        importBatch = NFImportBatchState(status: .running, totalCount: urls.count)
        importTask = Task { @MainActor in
            var failedURLs: [URL] = []
            var processedCount = 0
            var readinessCounts = NFImportReadinessCounts()

            for (urlIndex, url) in urls.enumerated() {
                if Task.isCancelled { break }
                importBatch?.currentFilename = url.lastPathComponent
                importBatch?.stage = .copying
                var replacementCopyID: UUID?
                do {
                    let duplicateAction = approvedDuplicateActions[url.standardizedFileURL.path]
                    if duplicateAction == nil {
                        let existingSources = store.documents.map {
                            NFDuplicateImportExistingSource(
                                id: $0.id,
                                filename: $0.filename,
                                sizeBytes: $0.sizeBytes,
                                localURL: URL(fileURLWithPath: $0.localPath),
                                indexState: $0.indexState,
                                importedAt: $0.importedAt
                            )
                        }
                        if let inspection = try await NFDuplicateImportInspector.inspect(
                            selectedURL: url,
                            existingSources: existingSources
                        ) {
                            duplicateRecoveryError = nil
                            duplicateImportReview = NFDuplicateImportReview(
                                selectedURL: url,
                                inspection: inspection,
                                remainingURLs: failedURLs + Array(urls.dropFirst(urlIndex + 1))
                            )
                            importBatch = nil
                            importTask = nil
                            return
                        }
                    }

                    if case .replace = duplicateAction {
                        // Fail before creating a replacement copy when an old
                        // private restore prevents deleting the selected source.
                        try await store.withLinkedRestoreArtifactDeletion { }
                    }
                    let document = try await store.importDocumentAsync(from: url) { stage in
                        importBatch?.stage = stage
                    }
                    if case let .replace(existingDocumentID) = duplicateAction {
                        replacementCopyID = document.id
                        try await store.withLinkedRestoreArtifactDeletion {
                            try NFDuplicateImportReplacementTransaction.commit(
                                importedSource: document,
                                existingDocumentID: existingDocumentID,
                                findExisting: { documentID in
                                    store.documents.first(where: { $0.id == documentID })
                                },
                                deleteExisting: { try store.deleteDocument($0) },
                                rollbackImported: { try store.deleteDocument($0) }
                            )
                        }
                    }
                    if store.shouldOpenSourceReviews {
                        store.requestedLibraryDocumentID = document.id
                    }
                    readinessCounts.record(indexState: document.indexState)
                } catch is CancellationError {
                    break
                } catch {
                    if let cleanupError = error as? NFRestoreLinkedDeletionError {
                        var message = cleanupError.errorDescription ?? ""
                        if let replacementCopyID, store.documents.contains(where: { $0.id == replacementCopyID }) {
                            message += "\n" + NFAppLocalization.localized("The newly imported copy is also retained. Retry replacement after cleanup finishes.")
                        }
                        store.notice = AppNotice(title: NFAppLocalization.localized("Deletion incomplete"), message: message)
                    }
                    failedURLs.append(url)
                }
                processedCount += 1
                importBatch?.processedCount = processedCount
                importBatch?.readyCount = readinessCounts.readyCount
                importBatch?.needsReprocessingCount = readinessCounts.needsReprocessingCount
            }

            if Task.isCancelled {
                let unfinished = Array(urls.dropFirst(processedCount))
                importBatch?.status = .cancelled
                importBatch?.retryURLs = failedURLs + unfinished
            } else if !failedURLs.isEmpty {
                importBatch?.status = .failed
                importBatch?.retryURLs = failedURLs
            } else {
                importBatch?.status = .completed
                importBatch?.processedCount = urls.count
                importBatch?.readyCount = readinessCounts.readyCount
                importBatch?.needsReprocessingCount = readinessCounts.needsReprocessingCount
                importBatch?.stage = .complete
            }
            importTask = nil
            if store.shouldOpenSourceReviews,
               duplicateImportReview == nil,
               !store.documents.isEmpty {
                scheduleRequestedLibraryDestinationPresentation()
            }
        }
    }

    private func importBatchTitle(_ batch: NFImportBatchState) -> String {
        switch batch.status {
        case .running:
            batch.currentFilename.isEmpty
                ? NFAppLocalization.localized("Preparing document import", locale: NFAppLocalization.preferredLocale, comment: "Document-import batch progress title before the first file starts.")
                : batch.currentFilename
        case .completed:
            if batch.needsReprocessingCount == 0 {
                NFAppLocalization.localized("Import complete", locale: NFAppLocalization.preferredLocale, comment: "Document-import batch completion title.")
            } else if batch.totalCount == 1 {
                NFAppLocalization.localized("Source needs reprocessing", locale: NFAppLocalization.preferredLocale, comment: "Document-import title when one saved source needs text processing attention.")
            } else {
                NFAppLocalization.localized("Some sources need reprocessing", locale: NFAppLocalization.preferredLocale, comment: "Document-import title when multiple saved sources need text processing attention.")
            }
        case .cancelled:
            NFAppLocalization.localized("Import cancelled safely", locale: NFAppLocalization.preferredLocale, comment: "Document-import batch cancellation title.")
        case .failed:
            NFAppLocalization.localized("Some files need another try", locale: NFAppLocalization.preferredLocale, comment: "Document-import batch partial-failure title.")
        }
    }

    private func importBatchDetail(_ batch: NFImportBatchState) -> String {
        switch batch.status {
        case .running:
            batch.stage.title
        case .completed:
            completedImportDetail(batch)
        case .cancelled:
            interruptedImportDetail(batch)
        case .failed:
            interruptedImportDetail(batch)
        }
    }

    private func batchNeedsAttention(_ batch: NFImportBatchState) -> Bool {
        batch.status == .failed || batch.needsReprocessingCount > 0
    }

    private func completedImportDetail(_ batch: NFImportBatchState) -> String {
        if batch.needsReprocessingCount == 0 {
            return batch.readyCount == 1
                ? NFAppLocalization.localized("Your source is ready for study.", locale: NFAppLocalization.preferredLocale, comment: "Document-import completion detail for one source.")
                : NFAppLocalization.localized("\(batch.readyCount) sources are ready for study.", locale: NFAppLocalization.preferredLocale, comment: "Document-import completion detail for multiple sources; the placeholder is the source count.")
        }
        if batch.readyCount == 0 {
            return batch.needsReprocessingCount == 1
                ? NFAppLocalization.localized("Your source was saved locally but needs reprocessing.", locale: NFAppLocalization.preferredLocale, comment: "Document-import detail when one saved source needs text processing attention.")
                : NFAppLocalization.localized("\(batch.needsReprocessingCount) sources were saved locally but need reprocessing.", locale: NFAppLocalization.preferredLocale, comment: "Document-import detail when multiple saved sources need text processing attention; the placeholder is the source count.")
        }
        return batch.needsReprocessingCount == 1
            ? NFAppLocalization.localized("\(batch.readyCount) ready for study. One saved source needs reprocessing.", locale: NFAppLocalization.preferredLocale, comment: "Mixed document-import detail with one source needing text processing; the placeholder is the ready count.")
            : NFAppLocalization.localized("\(batch.readyCount) ready for study. \(batch.needsReprocessingCount) saved sources need reprocessing.", locale: NFAppLocalization.preferredLocale, comment: "Mixed document-import detail; placeholders are ready and needs-reprocessing source counts.")
    }

    private func interruptedImportDetail(_ batch: NFImportBatchState) -> String {
        switch NFInterruptedImportSummary.classify(
            readyCount: batch.readyCount,
            needsReprocessingCount: batch.needsReprocessingCount
        ) {
        case .noSavedSources:
            NFAppLocalization.localized("No sources were saved. Unfinished imports can be retried.", locale: NFAppLocalization.preferredLocale, comment: "Interrupted document-import detail when no source was saved.")
        case .allSavedSourcesReady:
            NFAppLocalization.localized("Completed sources are ready. Unfinished imports can be retried.", locale: NFAppLocalization.preferredLocale, comment: "Interrupted document-import detail when all saved sources are ready.")
        case let .needsReprocessing(count, hasReadySources):
            if count == 1, hasReadySources {
                NFAppLocalization.localized("One saved source needs reprocessing. Other completed sources are ready; unfinished imports can be retried.", locale: NFAppLocalization.preferredLocale, comment: "Interrupted mixed document-import detail when one saved source needs reprocessing.")
            } else if count == 1 {
                NFAppLocalization.localized("One saved source needs reprocessing. Unfinished imports can be retried.", locale: NFAppLocalization.preferredLocale, comment: "Interrupted document-import detail when one saved source needs reprocessing.")
            } else if hasReadySources {
                NFAppLocalization.localized("\(count) saved sources need reprocessing. Other completed sources are ready; unfinished imports can be retried.", locale: NFAppLocalization.preferredLocale, comment: "Interrupted mixed document-import detail when multiple saved sources need reprocessing; the placeholder is the source count.")
            } else {
                NFAppLocalization.localized("\(count) saved sources need reprocessing. Unfinished imports can be retried.", locale: NFAppLocalization.preferredLocale, comment: "Interrupted document-import detail when multiple saved sources need reprocessing; the placeholder is the source count.")
            }
        }
    }

    private func presentRequestedImporterIfNeeded() {
        guard store.shouldPresentDocumentImporter else { return }
        store.consumeDocumentImportRequest()
        importing = true
    }

    private func scheduleRequestedLibraryDestinationPresentation() {
        Task { @MainActor in
            await Task.yield()
            presentRequestedLibraryDestinationIfNeeded()
        }
    }

    private func presentRequestedLibraryDestinationIfNeeded() {
        let requestedDocumentID = store.requestedLibraryDocumentID
        let requestedChunkID = store.requestedSourceChunkID
        let requestedReviewID = store.requestedSourceReviewID

        if store.shouldOpenSourceReviews {
            if store.documents.isEmpty,
               (importing || store.shouldPresentDocumentImporter || importTask != nil || duplicateImportReview != nil) {
                return
            }
            store.consumeSourceReviewRequest()
            store.requestedLibraryDocumentID = nil
            store.requestedSourceChunkID = nil
            store.requestedSourceReviewID = nil
            if let requestedReviewID {
                guard let requestedDocumentID,
                      let requestedChunkID,
                      let destination = NFSourceReviewDeepLinkDestination(
                          documentID: requestedDocumentID,
                          chunkID: requestedChunkID,
                          reviewID: requestedReviewID
                      ),
                      let attempt = NFSourceReviewDestinationResolver.savedReview(
                          for: destination,
                          documents: store.documents,
                          chunks: store.sourceChunks,
                          attempts: store.attempts
                      ) else {
                    sourceReviewRecoveryNotice = NFSourceReviewRecoveryNotice(
                        reason: .missingDestination,
                        documentID: requestedDocumentID
                    )
                    return
                }
                pendingNextReviewAfterChunkID = nil
                selectedReviewPresentation = .saved(NFReadOnlyAttemptSnapshot(attempt: attempt))
                return
            }
            presentNextSourceReview(
                documentID: requestedDocumentID,
                preferredChunkID: requestedChunkID
            )
            return
        }

        guard requestedDocumentID != nil || requestedChunkID != nil else { return }
        store.requestedLibraryDocumentID = nil
        store.requestedSourceChunkID = nil
        store.requestedSourceReviewID = nil

        let resolvedDocumentID = requestedDocumentID
            ?? requestedChunkID.flatMap { chunkID in
                store.sourceChunks.first(where: { $0.id == chunkID })?.documentID
            }
        guard let resolvedDocumentID,
              let document = store.documents.first(where: { $0.id == resolvedDocumentID }) else {
            sourceReviewRecoveryNotice = NFSourceReviewRecoveryNotice(
                reason: .missingDestination,
                documentID: nil
            )
            return
        }
        if let requestedChunkID,
           !store.chunks(for: document).contains(where: { $0.id == requestedChunkID }) {
            sourceReviewRecoveryNotice = NFSourceReviewRecoveryNotice(
                reason: .missingDestination,
                documentID: document.id
            )
            return
        }
        selectedDocumentInitialChunkID = requestedChunkID
        navigation.sources = [.document(document.id, chunkID: selectedDocumentInitialChunkID)]
    }

    private func presentNextSourceReview(
        excluding excludedChunkID: String? = nil,
        documentID: UUID? = nil,
        preferredChunkID: String? = nil
    ) {
        let candidateDocuments = documentID.map { requestedID in
            store.documents.filter { $0.id == requestedID }
        } ?? store.documents
        let chunks = candidateDocuments.flatMap { store.chunks(for: $0) }
        let preferredChunk = preferredChunkID.flatMap { preferredID in
            chunks.first(where: { $0.id == preferredID })
        }
        guard let chunk = preferredChunk ?? NFSourceReviewRotation.nextChunk(
            in: chunks,
            attempts: store.attempts,
            excluding: excludedChunkID
        ) else {
            presentSourceReviewRecovery(for: candidateDocuments)
            return
        }
        guard let document = store.documents.first(where: { $0.id == chunk.documentID }) else { return }
        selectedReviewPresentation = .practice(NFSourceReviewRoute(
            document: document,
            chunkID: chunk.id,
            hasAlternative: chunks.count > 1
        ))
    }

    private func presentSourceReviewRecovery(for documents: [SourceDocumentRecord]) {
        guard !documents.isEmpty else {
            sourceReviewRecoveryNotice = NFSourceReviewRecoveryNotice(
                reason: .noSources,
                documentID: nil
            )
            return
        }
        if let document = documents.first(where: { $0.indexState == "extracting" }) {
            sourceReviewRecoveryNotice = NFSourceReviewRecoveryNotice(
                reason: .preparing,
                documentID: document.id
            )
        } else if let document = documents.first(where: { $0.indexState != "ready" }) {
            sourceReviewRecoveryNotice = NFSourceReviewRecoveryNotice(
                reason: .needsReprocessing,
                documentID: document.id
            )
        } else {
            sourceReviewRecoveryNotice = NFSourceReviewRecoveryNotice(
                reason: .noReadableText,
                documentID: documents.first?.id
            )
        }
    }

    private func sourceReviewRecoveryAlert(_ notice: NFSourceReviewRecoveryNotice) -> Alert {
        let openDocument: () -> Void = {
            guard let documentID = notice.documentID,
                  let document = store.documents.first(where: { $0.id == documentID }) else { return }
            selectedDocumentInitialChunkID = nil
            navigation.sources = [.document(document.id, chunkID: selectedDocumentInitialChunkID)]
        }

        switch notice.reason {
        case .noSources:
            return Alert(
                title: Text("Import a source first"),
                message: Text("Source review needs readable text from a source you choose."),
                primaryButton: .default(Text("Import source")) { importing = true },
                secondaryButton: .cancel()
            )
        case .preparing:
            return Alert(
                title: Text("Source is still preparing"),
                message: Text("Text extraction or local OCR has not finished. Open the source to check its indexing status."),
                primaryButton: .default(Text("Open source"), action: openDocument),
                secondaryButton: .cancel()
            )
        case .needsReprocessing:
            return Alert(
                title: Text("Source needs reprocessing"),
                message: Text("No review excerpt is available because text extraction failed. Open the source to retry extraction or run local OCR."),
                primaryButton: .default(Text("Open source"), action: openDocument),
                secondaryButton: .cancel()
            )
        case .noReadableText:
            return Alert(
                title: Text("No reviewable text found"),
                message: Text("The source is stored, but it has no readable excerpt for source review. Open it to inspect the extracted text or import a text-based copy."),
                primaryButton: .default(Text("Open source"), action: openDocument),
                secondaryButton: .cancel()
            )
        case .missingDestination:
            return Alert(
                title: Text("Source item is no longer available"),
                message: Text("The linked source or excerpt may have been deleted or reprocessed. You can continue from the current Sources library."),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func presentPendingSourceReview() {
        guard let completedChunkID = pendingNextReviewAfterChunkID else { return }
        pendingNextReviewAfterChunkID = nil
        presentNextSourceReview(excluding: completedChunkID)
    }

    private func resolveDuplicateUsingExisting(_ review: NFDuplicateImportReview) {
        performDuplicateRecovery(.useExisting, review: review)
    }

    private func resolveDuplicateByReplacing(_ review: NFDuplicateImportReview) {
        performDuplicateRecovery(.replaceExisting, review: review)
    }

    private func resolveDuplicateByKeepingBoth(_ review: NFDuplicateImportReview) {
        performDuplicateRecovery(.keepBoth, review: review)
    }

    private func retryExistingDuplicate(_ review: NFDuplicateImportReview) {
        performDuplicateRecovery(.retryExisting, review: review)
    }

    private func cancelDuplicateImport(_ review: NFDuplicateImportReview) {
        performDuplicateRecovery(.skip, review: review)
    }

    private func performDuplicateRecovery(
        _ choice: NFDuplicateImportRecoveryChoice,
        review: NFDuplicateImportReview
    ) {
        let plan: NFDuplicateImportRecoveryPlan
        do {
            plan = try NFDuplicateImportRecoveryPlanner.plan(
                choice: choice,
                selectedURL: review.selectedURL,
                existingSource: review.inspection.existingSource,
                remainingURLs: review.remainingURLs,
                availableDocumentIDs: Set(store.documents.map(\.id))
            )
        } catch {
            duplicateRecoveryError = NFAppLocalization.localized(
                "The existing source is no longer available.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Duplicate-import recovery when the earlier source was deleted."
            )
            return
        }

        switch plan {
        case let .useExisting(documentID, remainingURLs):
            duplicateImportReview = nil
            duplicateRecoveryError = nil
            if store.shouldOpenSourceReviews {
                store.requestedLibraryDocumentID = documentID
            } else if let document = store.documents.first(where: { $0.id == documentID }) {
                selectedDocumentInitialChunkID = nil
                navigation.sources = [.document(document.id, chunkID: selectedDocumentInitialChunkID)]
            }
            continueAfterDuplicateDecision(remainingURLs)

        case let .importSelected(selectedURL, disposition, remainingURLs):
            duplicateImportReview = nil
            duplicateRecoveryError = nil
            let approvedAction: NFApprovedDuplicateImportAction
            switch disposition {
            case .keepBoth:
                approvedAction = .keepBoth
            case let .replace(existingDocumentID):
                approvedAction = .replace(existingDocumentID: existingDocumentID)
            }
            startImport(
                [selectedURL] + remainingURLs,
                approvedDuplicateActions: [selectedURL.standardizedFileURL.path: approvedAction]
            )

        case let .reprocessExisting(documentID, method, _):
            guard !duplicateRecoveryInProgress,
                  let document = store.documents.first(where: { $0.id == documentID }) else {
                duplicateRecoveryError = NFAppLocalization.localized(
                    "The existing source is no longer available.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Duplicate-import recovery when the earlier source was deleted."
                )
                return
            }
            duplicateRecoveryInProgress = true
            duplicateRecoveryError = nil
            Task { @MainActor in
                defer { duplicateRecoveryInProgress = false }
                do {
                    switch method {
                    case .localPDFOCR:
                        try await store.runLocalOCR(for: document)
                    case .extractText:
                        try await store.retryDocumentExtraction(for: document)
                    }
                    performDuplicateRecovery(.useExisting, review: review)
                } catch {
                    duplicateRecoveryError = NFDiagnosticRedactor.userMessage(
                        for: error,
                        context: method == .localPDFOCR ? .localOCR : .documentExtraction
                    )
                }
            }

        case let .skip(remainingURLs):
            duplicateImportReview = nil
            duplicateRecoveryError = nil
            continueAfterDuplicateDecision(remainingURLs)
        }
    }

    private func continueAfterDuplicateDecision(_ remainingURLs: [URL]) {
        if remainingURLs.isEmpty {
            if store.shouldOpenSourceReviews {
                scheduleRequestedLibraryDestinationPresentation()
            }
        } else {
            startImport(remainingURLs)
        }
    }

    private func removeOrphanedSourceReviewDrafts() {
        let documentIDs = Set(store.documents.map { $0.id.uuidString.lowercased() })
        let orphanedDrafts = store.sessionCheckpoints.filter { checkpoint in
            guard let planID = checkpoint.planID,
                  NFSourceReviewDraftIdentity.isDraftPlanID(planID) else { return false }
            let documentID = String(planID.dropFirst(NFSourceReviewDraftIdentity.planPrefix.count))
            return !documentIDs.contains(documentID)
        }
        guard !orphanedDrafts.isEmpty else { return }
        for checkpoint in orphanedDrafts { store.context.delete(checkpoint) }
        do {
            try store.context.save()
            store.reload()
        } catch {
            store.context.rollback()
            store.reload()
        }
    }
}

private struct NFDuplicateImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let review: NFDuplicateImportReview
    let retryInProgress: Bool
    let retryError: String?
    let onUseExisting: () -> Void
    let onReplaceExisting: () -> Void
    let onKeepBoth: () -> Void
    let onRetryExisting: () -> Void
    let onCancel: () -> Void
    @State private var isShowingReplaceConfirmation = false
    @State private var isShowingKeepBothConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        NFSectionHeader(
                            "Duplicate source found",
                            eyebrow: "Import paused safely",
                            subtitle: "The selected file and an existing source have the same full SHA-256 fingerprint. Choose how NeuroForge should continue before any duplicate study evidence is created."
                        )

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Selected file")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            LabeledContent("Filename", value: review.inspection.selectedFilename)
                            LabeledContent(
                                "Size",
                                value: ByteCountFormatter.string(
                                    fromByteCount: review.inspection.selectedSizeBytes,
                                    countStyle: .file
                                )
                            )
                        }
                        .nfCard()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Matching source already in NeuroForge")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            LabeledContent("Filename", value: review.inspection.existingSource.filename)
                            LabeledContent("Imported", value: importedDate)
                            LabeledContent("Index status", value: existingIndexStatus)
                        }
                        .nfCard()

                        DisclosureGroup("Compare fingerprint") {
                            Text(review.inspection.fingerprint)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 8)
                                .accessibilityLabel("Matching SHA-256 fingerprint")
                                .accessibilityValue(review.inspection.fingerprint)
                        }
                        .nfCard()

                        if let retryError {
                            Label(retryError, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(NFTheme.roseForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 10) {
                            Button(action: onUseExisting) {
                                Label("Use existing source", systemImage: "doc.text.magnifyingglass")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(NFTheme.controlTint(for: "indigo"))
                            .foregroundStyle(NFTheme.controlForeground(for: "indigo"))

                            if review.inspection.existingSource.indexState != "ready" {
                                Button(action: onRetryExisting) {
                                    Label(
                                        retryInProgress ? "Reprocessing existing source…" : existingRecoveryTitle,
                                        systemImage: "arrow.clockwise.circle"
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(retryInProgress)
                            }

                            Button {
                                isShowingReplaceConfirmation = true
                            } label: {
                                Label("Replace existing source", systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(retryInProgress)

                            Button {
                                isShowingKeepBothConfirmation = true
                            } label: {
                                Label("Keep both as separate sources", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(retryInProgress)
                        }
                        .controlSize(.large)
                    }
                    .padding(20)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Duplicate import")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip this file", action: onCancel)
                        .disabled(retryInProgress)
                }
            }
        }
        .interactiveDismissDisabled()
        .confirmationDialog(
            "Replace the existing source?",
            isPresented: $isShowingReplaceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace source and its linked history", role: .destructive, action: onReplaceExisting)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("NeuroForge imports and verifies the selected file first. It then removes the existing managed copy, excerpts, source-created questions, practice history, reports, and AI provenance. The original outside NeuroForge is unchanged.")
        }
        .confirmationDialog(
            "Keep two identical sources?",
            isPresented: $isShowingKeepBothConfirmation,
            titleVisibility: .visible
        ) {
            Button("Keep both", action: onKeepBoth)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This intentionally creates a separate source with the same content. Future source review and generated questions may overlap.")
        }
    }

    private var importedDate: String {
        let formatter = DateFormatter()
        formatter.locale = NFAppLocalization.preferredLocale
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: review.inspection.existingSource.importedAt)
    }

    private var existingIndexStatus: String {
        switch review.inspection.existingSource.indexState {
        case "ready":
            NFAppLocalization.localized("Index ready", locale: NFAppLocalization.preferredLocale, comment: "Duplicate-import existing-source index status.")
        case "extracting":
            NFAppLocalization.localized("Index preparing", locale: NFAppLocalization.preferredLocale, comment: "Duplicate-import existing-source index status.")
        default:
            NFAppLocalization.localized("Index needs reprocessing", locale: NFAppLocalization.preferredLocale, comment: "Duplicate-import existing-source index status.")
        }
    }

    private var existingRecoveryTitle: String {
        review.inspection.existingSource.localURL.pathExtension.lowercased() == "pdf"
            ? NFAppLocalization.localized("Run local OCR on existing source", locale: NFAppLocalization.preferredLocale, comment: "Duplicate-import recovery for an existing PDF source.")
            : NFAppLocalization.localized("Retry existing source index", locale: NFAppLocalization.preferredLocale, comment: "Duplicate-import recovery for an existing source.")
    }
}

private struct DocumentRow: View {
    @Environment(AppStore.self) private var store
    let document: SourceDocumentRecord

    var body: some View {
        HStack(spacing: 14) {
            NFIconTile(symbol: documentSymbol, color: NFTheme.cyan, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(document.filename)
                    .font(.headline)
                    .lineLimit(1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ByteCountFormatter.string(fromByteCount: document.sizeBytes, countStyle: .file)) · \(importedDate)")
                    Text(readinessPresentation.indexStatus)
                    Text(readinessPresentation.questionStatus)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                NFStatusPill(
                    text: documentPillText,
                    symbol: documentPillSymbol,
                    color: documentPillColor
                )
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.06))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var documentSymbol: String {
        if document.typeIdentifier.contains("pdf") { return "doc.richtext.fill" }
        if document.typeIdentifier.contains("comma") { return "tablecells.fill" }
        if document.typeIdentifier.contains("source") { return "chevron.left.forwardslash.chevron.right" }
        return "doc.text.fill"
    }

    private var readinessPresentation: NFDocumentReadinessPresentation {
        NFDocumentReadinessPresentation.make(
            indexState: document.indexState,
            chunkCount: document.chunkCount,
            aiPolicy: DocumentAIPolicy(rawValue: document.aiPolicyRaw) ?? .noAI,
            aiMode: store.profileSnapshot.aiMode
        )
    }

    private var importedDate: String {
        let formatter = DateFormatter()
        formatter.locale = NFAppLocalization.preferredLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: document.importedAt)
    }

    private var documentPillText: String {
        switch document.indexState {
        case "ready": "Ready offline"
        case "extracting": "Preparing"
        default: "Stored locally"
        }
    }

    private var documentPillSymbol: String {
        switch document.indexState {
        case "ready": "checkmark.shield.fill"
        case "extracting": "arrow.triangle.2.circlepath"
        default: "internaldrive.fill"
        }
    }

    private var documentPillColor: Color {
        switch document.indexState {
        case "ready": NFTheme.mint
        case "extracting": NFTheme.cyan
        default: NFTheme.amber
        }
    }
}

struct DocumentDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(NFSystemIntegrationCoordinator.self) private var systemIntegrations
    @Environment(\.dismiss) private var dismiss
    let document: SourceDocumentRecord
    let initialSourceChunkID: String?
    @State private var syncPolicy: NFDocumentSyncPolicy = .localOnly
    @State private var aiPolicy: DocumentAIPolicy = .noAI
    @State private var policyMutationGate = NFDocumentPolicyMutationGate()
    @State private var policyError: String?
    @State private var syncPolicyTask: Task<Void, Never>?
    @AccessibilityFocusState private var policyErrorIsFocused: Bool
    @State private var showDeleteConfirmation = false
    @State private var showSourceReview = false
    @State private var showSourceViewer = false
    @State private var showAIStudio = false
    @State private var showFileDetails = false
    @State private var deleteError: String?
    @State private var ocrInProgress = false
    @State private var ocrError: String?
    @State private var extractionInProgress = false
    @State private var extractionError: String?
    @State private var csvPreview: NFCSVSchemaPreview?
    @State private var selectedCSVColumnIDs: Set<String> = []
    @State private var csvPreviewLoading = false
    @State private var csvSelectionSaving = false
    @State private var csvSelectionError: String?

    init(document: SourceDocumentRecord, initialSourceChunkID: String? = nil) {
        self.document = document
        self.initialSourceChunkID = initialSourceChunkID
        _syncPolicy = State(
            initialValue: NFDocumentSyncPolicy(rawValue: document.syncPolicy) ?? .localOnly
        )
        _aiPolicy = State(
            initialValue: DocumentAIPolicy(rawValue: document.aiPolicyRaw) ?? .noAI
        )
        _showSourceViewer = State(initialValue: initialSourceChunkID != nil)
    }

    private var aiPolicyChangeInProgress: Bool {
        policyMutationGate.isActive(.questionPrivacy)
    }

    private var syncPolicyChangeInProgress: Bool {
        policyMutationGate.isActive(.iCloudSync)
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 16) {
                        NFIconTile(symbol: "doc.text.fill", color: NFTheme.cyan, size: 62)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(document.filename)
                                .font(.system(.title, design: .rounded, weight: .bold))
                            Text(LocalizedStringKey(documentStudyStatus))
                                .foregroundStyle(documentStudyStatusColor)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Practice from this source").font(.title2.bold())
                        Text(LocalizedStringKey(documentCanUseNativeAI
                            ? "Recall from memory or create short-answer practice with AI feedback."
                            : "Review what you remember, then compare with the source."))
                            .foregroundStyle(.secondary)
                        Button {
                            showSourceReview = true
                        } label: {
                            Label("Review from memory", systemImage: "rectangle.stack.badge.play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NFTheme.controlTint(for: "indigo"))
                        .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                        .controlSize(.large)
                        .disabled(document.chunkCount == 0 || isDocumentProcessing)

                        ViewThatFits(in: .horizontal) {
                            HStack { sourceQuestionButton; browseSourceButton }
                            VStack(spacing: 10) { sourceQuestionButton; browseSourceButton }
                        }

                        if document.chunkCount > 0, !documentHasProseRecall {
                            Text(LocalizedStringKey(documentCanUseNativeAI
                                ? "AI short-answer sets can use readable code, tables, and other source text. Model availability is checked when you create the set."
                                : "Source review works with this format. Enable AI for this source and in Settings to create short-answer questions."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if isPDF && document.indexState == "extractionFailed" {
                            Button {
                                runOCR()
                            } label: {
                                Label(
                                    ocrInProgress ? "Recognizing every page…" : "Run local OCR",
                                    systemImage: "viewfinder.circle"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(isDocumentProcessing)
                        }

                        if document.indexState == "extractionFailed" {
                            Button {
                                retryExtraction()
                            } label: {
                                Label(
                                    extractionInProgress
                                        ? "Retrying local extraction…"
                                        : (isImage ? "Run local OCR" : "Retry text extraction"),
                                    systemImage: "arrow.clockwise.circle"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(extractionInProgress || ocrInProgress)
                        }
                    }
                    .nfCard()

                    VStack(spacing: 12) {
                        LabeledContent("Imported", value: importedDate)
                        LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: document.sizeBytes, countStyle: .file))
                        LabeledContent("Index", value: readinessPresentation.indexStatus)
                        LabeledContent("Question creation", value: readinessPresentation.questionStatus)
                        DisclosureGroup("File details", isExpanded: $showFileDetails) {
                            VStack(spacing: 12) {
                                LabeledContent("Stored copy", value: NFAppLocalization.localized("App storage", locale: NFAppLocalization.preferredLocale, comment: "Location of the imported copy used for offline access."))
                                LabeledContent("Study sections", value: document.chunkCount.formatted())
                                LabeledContent("Extracted text", value: NFAppLocalization.formattedCharacterCount(document.characterCount))
                                if let safeDiagnostic = NFDiagnosticRedactor.localizedPersistedMessage(
                                    document.indexError,
                                    context: document.indexError?.hasPrefix("document.ocr.") == true ? .localOCR : .documentExtraction
                                ) {
                                    LabeledContent("Processing note", value: safeDiagnostic)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .nfCard()

                    if isCSV {
                        csvColumnSelectionCard
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        Text("Source AI availability")
                            .font(.title2.bold())
                        Text("Choose how AI can help you study this source. On-device AI supports offline learning when a suitable model is available.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("Source AI use", selection: Binding(
                            get: { aiPolicy.rawValue },
                            set: { rawValue in
                                guard let policy = DocumentAIPolicy(rawValue: rawValue) else {
                                    return
                                }
                                commitAIPolicy(policy)
                            }
                        )) {
                            Text(NFSourceAIAvailabilityPresentation.title(for: .privateCloudAllowed))
                                .tag(DocumentAIPolicy.privateCloudAllowed.rawValue)
                            Text(NFSourceAIAvailabilityPresentation.title(for: .onDeviceOnly))
                                .tag(DocumentAIPolicy.onDeviceOnly.rawValue)
                            Text(NFSourceAIAvailabilityPresentation.title(for: .noAI))
                                .tag(DocumentAIPolicy.noAI.rawValue)
                        }
                        .disabled(aiPolicyChangeInProgress || syncPolicyChangeInProgress)

                        if aiPolicyChangeInProgress {
                            ProgressView("Saving source AI setting…")
                                .controlSize(.small)
                        }

                        Text(sourceAIAvailabilitySummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        DisclosureGroup("How this choice uses your source") {
                            Label(sourceAIAvailabilityExplanation, systemImage: sourceAIAvailabilitySymbol)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                    }
                    .nfCard()

                    VStack(alignment: .leading, spacing: 13) {
                        Text("iCloud sync")
                            .font(.title2.bold())
                        Toggle(isOn: Binding(
                            get: { syncPolicy == .privateOriginal },
                            set: { enabled in
                                let policy: NFDocumentSyncPolicy = enabled ? .privateOriginal : .localOnly
                                commitSyncPolicy(policy)
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Sync original with iCloud")
                                    .font(.headline)
                                Text("Only the app-managed original can sync; the extracted index stays local.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(
                            !systemIntegrations.syncCapability.supportsPrivateSyncAttempt
                                && syncPolicy == .localOnly
                                || syncPolicyChangeInProgress
                                || aiPolicyChangeInProgress
                        )

                        if syncPolicyChangeInProgress {
                            ProgressView("Saving iCloud preference…")
                                .controlSize(.small)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: documentSyncSymbol)
                                .foregroundStyle(documentSyncColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(documentSyncTitle)
                                    .font(.subheadline.weight(.semibold))
                                Text(documentSyncDetail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        DisclosureGroup("What stays local") {
                            Text("The extracted index is stored locally for offline use. Relevant excerpts may be sent to your configured AI service when this source and Settings allow Automatic AI.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }

                        if let policyError {
                            Label(policyError, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(NFTheme.roseForeground)
                                .accessibilityFocused($policyErrorIsFocused)
                        }
                    }
                    .nfCard()

                    HStack {
                        if !document.localPath.isEmpty {
                            ShareLink(item: URL(fileURLWithPath: document.localPath)) {
                                Label("Export original", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete document", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDocumentProcessing)
                    }
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Document")
        .task(id: document.id) {
            await loadCSVPreviewIfNeeded()
        }
        .sheet(isPresented: $showSourceReview) {
            SourceReviewView(document: document, initialChunkID: nil, onReviewAnother: nil)
                .environment(store)
        }
        .sheet(isPresented: $showSourceViewer) {
            SourceChunkBrowserView(
                document: document,
                initialChunkID: initialSourceChunkID
            )
                .environment(store)
        }
        .sheet(isPresented: $showAIStudio) {
            AIStudioView(initialDocumentID: document.id)
                .environment(store)
        }
        .confirmationDialog(
            syncPolicy == .privateOriginal ? "Delete this synced document everywhere?" : "Delete this local document?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if syncPolicy == .privateOriginal {
                Button("Delete from iCloud and this device", role: .destructive) {
                    Task { @MainActor in
                        do {
                            try await systemIntegrations.deleteDocumentEverywhere(document, store: store)
                            dismiss()
                        } catch {
                            deleteError = (error as? NFRestoreLinkedDeletionError)?.errorDescription
                                ?? (error as? NFPrivateSyncDeletionError)?.errorDescription
                                ?? NFAppLocalization.localized("NeuroForge kept the local document because iCloud deletion could not finish. Retry when sync is available.",
                                    locale: NFAppLocalization.preferredLocale,
                                    comment: "Fallback error after a synced-document deletion cannot be queued."
                                )
                        }
                    }
                }
            } else {
                Button("Delete source data from this device", role: .destructive) {
                    Task { @MainActor in
                        do {
                            try await store.withLinkedRestoreArtifactDeletion { try store.deleteDocument(document) }
                            dismiss()
                        } catch {
                            deleteError = (error as? NFRestoreLinkedDeletionError)?.errorDescription
                                ?? NFAppLocalization.localized("NeuroForge could not verify complete deletion. Retry from this screen; the original file outside the app was not changed.",
                                    locale: NFAppLocalization.preferredLocale,
                                    comment: "Error after local study-document deletion cannot be verified.")
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(syncPolicy == .privateOriginal
                 ? "This removes NeuroForge’s managed original from private iCloud and this device, plus extracted sections, source-created questions and practice history, reports, and AI provenance. The original outside NeuroForge is unchanged. If you are offline, verified iCloud deletion finishes when sync resumes."
                 : "This removes NeuroForge’s managed copy from this device, plus extracted sections, source-created questions and practice history, reports, and AI provenance. The original file outside NeuroForge is unchanged; private iCloud data is not affected."))
        }
        .alert("Deletion could not finish", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(deleteError ?? "Retry deletion from this screen."))
        }
        .alert("Local OCR could not finish", isPresented: Binding(
            get: { ocrError != nil },
            set: { if !$0 { ocrError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(ocrError ?? "Try a clearer scan or an exported text-based PDF."))
        }
        .alert("Text extraction could not finish", isPresented: Binding(
            get: { extractionError != nil },
            set: { if !$0 { extractionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(extractionError ?? "The local copy remains available. Retry or use local OCR for a scanned PDF."))
        }
    }

    private var documentStudyStatus: String {
        switch document.indexState {
        case "ready":
            NFAppLocalization.localized("Ready for study", locale: NFAppLocalization.preferredLocale, comment: "Document status when imported material can be used for practice.")
        case "extracting":
            NFAppLocalization.localized("Preparing study material", locale: NFAppLocalization.preferredLocale, comment: "Document status while imported text is being prepared.")
        default:
            NFAppLocalization.localized("Needs reprocessing", locale: NFAppLocalization.preferredLocale, comment: "Document status when text preparation must be retried.")
        }
    }

    private var documentStudyStatusColor: Color {
        switch document.indexState {
        case "ready": NFTheme.mintForeground
        case "extracting": NFTheme.cyanForeground
        default: NFTheme.amberForeground
        }
    }

    private var readinessPresentation: NFDocumentReadinessPresentation {
        NFDocumentReadinessPresentation.make(
            indexState: document.indexState,
            chunkCount: document.chunkCount,
            aiPolicy: aiPolicy,
            aiMode: store.profileSnapshot.aiMode
        )
    }

    private var sourceAIAvailabilitySummary: String {
        switch aiPolicy {
        case .privateCloudAllowed:
            NFAppLocalization.localized("Relevant excerpts can be used by your configured AI service.", locale: NFAppLocalization.preferredLocale, comment: "Concise source setting summary permitting normal configured AI use.")
        case .onDeviceOnly:
            NFAppLocalization.localized("AI work uses a suitable on-device model, so it can run without a connection.", locale: NFAppLocalization.preferredLocale, comment: "Concise source setting summary explaining the offline purpose of on-device AI.")
        case .noAI:
            NFAppLocalization.localized("Browse and review this source without AI.", locale: NFAppLocalization.preferredLocale, comment: "Concise source setting summary when AI is disabled for the source.")
        }
    }

    private var importedDate: String {
        let formatter = DateFormatter()
        formatter.locale = NFAppLocalization.preferredLocale
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: document.importedAt)
    }

    private var isDocumentProcessing: Bool {
        ocrInProgress
            || extractionInProgress
            || csvSelectionSaving
            || aiPolicyChangeInProgress
            || syncPolicyChangeInProgress
            || document.indexState == "extracting"
    }

    private var isPDF: Bool {
        document.typeIdentifier.contains("pdf") || URL(fileURLWithPath: document.localPath).pathExtension.lowercased() == "pdf"
    }

    private var isCSV: Bool {
        document.typeIdentifier.contains("comma-separated")
            || document.typeIdentifier.contains("comma")
            || document.typeIdentifier.contains("tab-separated")
            || ["csv", "tsv"].contains(URL(fileURLWithPath: document.localPath).pathExtension.lowercased())
    }

    private var isImage: Bool {
        NFDocumentImportTypeRegistry.isImage(filename: document.filename)
            || NFDocumentImportTypeRegistry.isImage(filename: document.localPath)
    }

    private var documentHasProseRecall: Bool {
        store.chunks(for: document).contains { chunk in
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
    }

    private var sourceQuestionButton: some View {
        Button { showAIStudio = true } label: {
            Label("Create question set", systemImage: "text.book.closed.fill")
                .frame(maxWidth: .infinity)

        }
        .buttonStyle(.bordered)
        .tint(NFTheme.roseForeground)
        .disabled(!NFSourceAIAvailabilityPresentation.allowsQuestionSet(
            aiMode: store.profileSnapshot.aiMode, sourcePolicy: documentAIPolicy,
            chunkCount: document.chunkCount, isProcessing: isDocumentProcessing, hasProseRecall: documentHasProseRecall))
    }

    private var documentCanUseNativeAI: Bool {
        NFSourceAIAvailabilityPresentation.allowsNativeQuestions(
            aiMode: store.profileSnapshot.aiMode, sourcePolicy: documentAIPolicy)
    }

    private var documentAIPolicy: DocumentAIPolicy {
        aiPolicy
    }

    private var sourceAIAvailabilityExplanation: LocalizedStringKey {
        switch documentAIPolicy {
        case .privateCloudAllowed:
            "AI can use relevant excerpts for short-answer questions, grading, and explanations. Automatic mode uses your configured cloud provider or a suitable on-device model. Source reading stays available offline. The optional Question Writer Shortcut still asks before sending excerpts."
        case .onDeviceOnly:
            "This source uses on-device AI for questions, grading, and explanations. If a suitable local model is unavailable, source review and reading remain available. This choice is respected even when a cloud provider is configured."
        case .noAI:
            "AI does not use this source for questions, grading, or explanations. Source review and browsing remain available offline."
        }
    }

    private var sourceAIAvailabilitySymbol: String {
        switch documentAIPolicy {
        case .privateCloudAllowed: "sparkles"
        case .onDeviceOnly: "internaldrive.fill"
        case .noAI: "book.closed.fill"
        }
    }

    private var browseSourceButton: some View {
        Button { showSourceViewer = true } label: {
            Label("Read source", systemImage: "text.magnifyingglass")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(document.chunkCount == 0 || isDocumentProcessing)
    }

    private func commitAIPolicy(_ requestedPolicy: DocumentAIPolicy) {
        guard requestedPolicy != aiPolicy,
              let activeGate = policyMutationGate.beginning(.questionPrivacy) else { return }
        let priorPolicy = aiPolicy
        policyMutationGate = activeGate
        defer {
            policyMutationGate = policyMutationGate.finishing(.questionPrivacy)
        }
        policyError = nil
        let didCommit = store.updateDocumentAIPolicy(document, policy: requestedPolicy)
        if didCommit {
            aiPolicy = requestedPolicy
        } else {
            aiPolicy = priorPolicy
            policyError = store.lastErrorMessage ?? NFAppLocalization.localized(
                "The source AI setting was not saved. The previous choice is still active.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Per-document AI availability persistence error."
            )
            policyErrorIsFocused = true
        }
    }

    private func commitSyncPolicy(_ requestedPolicy: NFDocumentSyncPolicy) {
        guard requestedPolicy != syncPolicy,
              let activeGate = policyMutationGate.beginning(.iCloudSync) else { return }
        let priorPolicy = syncPolicy
        policyMutationGate = activeGate
        policyError = nil

        syncPolicyTask = Task { @MainActor in
            defer {
                policyMutationGate = policyMutationGate.finishing(.iCloudSync)
                syncPolicyTask = nil
            }

            let didCommit = store.updateDocumentSyncPolicy(document, policy: requestedPolicy)
            guard didCommit else {
                syncPolicy = priorPolicy
                policyError = store.lastErrorMessage ?? NFAppLocalization.localized(
                    "The iCloud choice was not saved. The previous storage choice is still active.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Per-document iCloud-policy persistence error."
                )
                policyErrorIsFocused = true
                return
            }

            syncPolicy = requestedPolicy
            if requestedPolicy == .localOnly {
                await systemIntegrations.removeDocumentFromPrivateSync(
                    documentID: document.id,
                    store: store
                )
            } else {
                await systemIntegrations.reconcilePrivateDocumentSync(
                    store: store,
                    synchronize: true
                )
            }

            if systemIntegrations.documentSyncStates[document.id] == .error {
                policyError = NFAppLocalization.localized(
                    "The storage choice was saved, but iCloud needs attention. Your local copy remains available.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Per-document iCloud transport error after its policy was saved."
                )
                policyErrorIsFocused = true
            }
        }
    }

    @ViewBuilder
    private var csvColumnSelectionCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Table column selection")
                .font(.title2.bold())
            if csvPreviewLoading, csvPreview == nil {
                ProgressView("Reading table schema…")
            } else if let preview = csvPreview {
                Text(NFAppLocalization.localized(
                    "\(NFAppLocalization.formattedDataRowCount(preview.rowCount)) · \(NFAppLocalization.formattedDetectedColumnCount(preview.columns.count))",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "CSV preview dimensions with localized data-row and detected-column counts."
                ))
                    .font(.subheadline.weight(.semibold))
                Text("Choose which columns local source review can use. Your original table file is unchanged.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Select all") {
                        selectedCSVColumnIDs = Set(preview.columns.map(\.id))
                    }
                    .buttonStyle(.borderless)
                    .disabled(csvSelectionSaving)
                    Button("Clear selection") {
                        selectedCSVColumnIDs.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .disabled(csvSelectionSaving)
                }

                ForEach(preview.columns) { column in
                    Toggle(isOn: Binding(
                        get: { selectedCSVColumnIDs.contains(column.id) },
                        set: { selected in
                            if selected {
                                selectedCSVColumnIDs.insert(column.id)
                            } else {
                                selectedCSVColumnIDs.remove(column.id)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(column.name)
                                .font(.headline)
                            Text(csvColumnSummary(column))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(csvSelectionSaving)

                Button {
                    applyCSVColumnSelection(preview)
                } label: {
                    Label(
                        csvSelectionSaving
                            ? NFAppLocalization.localized("Applying column selection…", locale: NFAppLocalization.preferredLocale, comment: "CSV re-indexing progress button label.")
                            : NFAppLocalization.localized("Apply column selection", locale: NFAppLocalization.preferredLocale, comment: "Apply selected CSV columns to the local derived index."),
                        systemImage: "tablecells.badge.ellipsis"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(NFTheme.controlTint(for: "indigo"))
                .foregroundStyle(NFTheme.controlForeground(for: "indigo"))
                .disabled(selectedCSVColumnIDs.isEmpty || isDocumentProcessing)
            } else {
                Text("Table preview is unavailable. All columns remain available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let csvSelectionError {
                Text(csvSelectionError)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(NFTheme.roseForeground)
            }
        }
        .nfCard()
    }

    private func csvColumnSummary(_ column: NFCSVColumnDescriptor) -> String {
        let type = switch column.inferredType {
        case .integer: NFAppLocalization.localized("Integer", locale: NFAppLocalization.preferredLocale, comment: "Inferred CSV column type.")
        case .number: NFAppLocalization.localized("Number", locale: NFAppLocalization.preferredLocale, comment: "Inferred CSV column type.")
        case .boolean: NFAppLocalization.localized("Boolean", locale: NFAppLocalization.preferredLocale, comment: "Inferred CSV column type.")
        case .date: NFAppLocalization.localized("Date", locale: NFAppLocalization.preferredLocale, comment: "Inferred CSV column type.")
        case .text: NFAppLocalization.localized("Text", locale: NFAppLocalization.preferredLocale, comment: "Inferred CSV column type.")
        case .mixed: NFAppLocalization.localized("Mixed", locale: NFAppLocalization.preferredLocale, comment: "Inferred CSV column type.")
        }
        if let minimum = column.numericMinimum,
           let maximum = column.numericMaximum,
           let mean = column.numericMean {
            return NFAppLocalization.localized("\(type) · range \(minimum.formatted(.number.precision(.fractionLength(0...3))))–\(maximum.formatted(.number.precision(.fractionLength(0...3)))) · mean \(mean.formatted(.number.precision(.fractionLength(0...3)))) · \(NFAppLocalization.formattedValueCount(column.nonEmptyCount))",
                locale: NFAppLocalization.preferredLocale,
                comment: "CSV numeric column summary: inferred type, minimum, maximum, mean, and non-empty value count."
            )
        }
        let minimumLength = column.minimumTextLength ?? 0
        let maximumLength = column.maximumTextLength ?? 0
        return NFAppLocalization.localized("\(type) · \(NFAppLocalization.formattedValueCount(column.nonEmptyCount)) · \(NFAppLocalization.formattedDistinctValueCount(column.distinctCount)) · length \(minimumLength)–\(maximumLength)",
            locale: NFAppLocalization.preferredLocale,
            comment: "CSV text or mixed column summary: inferred type, non-empty value count, distinct count, and shortest-to-longest value length."
        )
    }

    @MainActor
    private func loadCSVPreviewIfNeeded() async {
        guard isCSV, csvPreview == nil, !csvPreviewLoading else { return }
        csvPreviewLoading = true
        defer { csvPreviewLoading = false }
        do {
            let preview = try await store.csvPreview(for: document)
            csvPreview = preview
            let persisted = Set(document.csvSelectedColumnIDs)
            let available = Set(preview.columns.map(\.id))
            selectedCSVColumnIDs = persisted.isEmpty ? available : persisted.intersection(available)
            csvSelectionError = nil
        } catch {
            csvSelectionError = NFDiagnosticRedactor.userMessage(for: error, context: .documentExtraction)
        }
    }

    private func applyCSVColumnSelection(_ preview: NFCSVSchemaPreview) {
        guard !selectedCSVColumnIDs.isEmpty, !isDocumentProcessing else { return }
        let orderedIDs = preview.columns.map(\.id).filter(selectedCSVColumnIDs.contains)
        csvSelectionSaving = true
        Task { @MainActor in
            defer { csvSelectionSaving = false }
            do {
                try await store.updateCSVColumnSelection(
                    for: document,
                    selection: NFCSVColumnSelection(columnIDs: orderedIDs)
                )
                csvSelectionError = nil
            } catch {
                csvSelectionError = NFDiagnosticRedactor.userMessage(for: error, context: .documentExtraction)
            }
        }
    }

    private var documentSyncState: NFDocumentPrivateSyncState {
        systemIntegrations.documentSyncStates[document.id]
            ?? (syncPolicy == .localOnly ? .localOnly : .unavailable)
    }

    private var documentSyncTitle: String {
        switch documentSyncState {
        case .localOnly: NFAppLocalization.localized("Local only", locale: NFAppLocalization.preferredLocale, comment: "Per-document storage status.")
        case .unavailable: NFAppLocalization.localized("Private sync unavailable", locale: NFAppLocalization.preferredLocale, comment: "Per-document private iCloud status when capability is absent.")
        case .queued: NFAppLocalization.localized("Private change queued", locale: NFAppLocalization.preferredLocale, comment: "Per-document private iCloud queue status.")
        case .uploaded: NFAppLocalization.localized("Original uploaded", locale: NFAppLocalization.preferredLocale, comment: "Per-document private iCloud success status.")
        case .paused: NFAppLocalization.localized("Private sync paused", locale: NFAppLocalization.preferredLocale, comment: "Per-document private iCloud status for account or network pause.")
        case .error: NFAppLocalization.localized("Private sync needs attention", locale: NFAppLocalization.preferredLocale, comment: "Per-document private iCloud failure status.")
        }
    }

    private var documentSyncDetail: String {
        switch documentSyncState {
        case .localOnly:
            NFAppLocalization.localized("This original stays on this device.", locale: NFAppLocalization.preferredLocale, comment: "Per-document local-only storage explanation.")
        case .unavailable:
            NFAppLocalization.localized("iCloud sync is not available in this build or on this device.", locale: NFAppLocalization.preferredLocale, comment: "Per-document private iCloud capability guidance.")
        case .queued:
            NFAppLocalization.localized("Waiting to sync. You can keep using the local copy.", locale: NFAppLocalization.preferredLocale, comment: "Per-document private iCloud queued-state explanation.")
        case .uploaded:
            NFAppLocalization.localized("The original is up to date in your private iCloud.", locale: NFAppLocalization.preferredLocale, comment: "Per-document private iCloud completion explanation.")
        case .paused:
            NFAppLocalization.localized("Sync is paused. Your local copy is safe.", locale: NFAppLocalization.preferredLocale, comment: "Per-document private iCloud paused-state explanation.")
        case .error:
            NFAppLocalization.localized("Your local copy is safe. Open Settings to retry sync.", locale: NFAppLocalization.preferredLocale, comment: "Per-document private iCloud failure explanation.")
        }
    }

    private var documentSyncSymbol: String {
        switch documentSyncState {
        case .localOnly: "internaldrive.fill"
        case .unavailable: "icloud.slash"
        case .queued: "icloud.and.arrow.up"
        case .uploaded: "checkmark.icloud.fill"
        case .paused: "pause.circle.fill"
        case .error: "exclamationmark.icloud.fill"
        }
    }

    private var documentSyncColor: Color {
        switch documentSyncState {
        case .localOnly, .unavailable: .secondary
        case .queued, .paused: NFTheme.amberForeground
        case .uploaded: NFTheme.mintForeground
        case .error: NFTheme.roseForeground
        }
    }

    private func runOCR() {
        guard !isDocumentProcessing, document.indexState == "extractionFailed" else { return }
        ocrInProgress = true
        Task { @MainActor in
            defer { ocrInProgress = false }
            do {
                try await store.runLocalOCR(for: document)
            } catch {
                ocrError = NFDiagnosticRedactor.userMessage(for: error, context: .localOCR)
            }
        }
    }

    private func retryExtraction() {
        guard !isDocumentProcessing, document.indexState == "extractionFailed" else { return }
        extractionInProgress = true
        Task { @MainActor in
            defer { extractionInProgress = false }
            do {
                try await store.retryDocumentExtraction(for: document)
            } catch is CancellationError {
                extractionError = NFAppLocalization.localized("Extraction was cancelled. The app-managed original remains available.", locale: NFAppLocalization.preferredLocale, comment: "Document extraction cancellation message.")
            } catch {
                extractionError = NFDiagnosticRedactor.userMessage(for: error, context: .documentExtraction)
            }
        }
    }

}

private enum SourceReviewStage: String {
    case recall
    case confidence
    case selfCheck
}

struct NFSourceReviewDraftSnapshot: Equatable, Sendable {
    let response: String
    let confidence: ConfidenceLevel?
    let stageRawValue: String

    var hasAuthoredContent: Bool {
        !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || confidence != nil
            || stageRawValue != SourceReviewStage.recall.rawValue
    }

    var checkpointEvents: [String] {
        [
            "sourceReviewStage=\(stageRawValue)",
            "confidence=\(confidence?.rawValue ?? "")"
        ]
    }

    init(response: String, confidence: ConfidenceLevel?, stageRawValue: String) {
        self.response = response
        self.confidence = confidence
        self.stageRawValue = stageRawValue
    }

    init(checkpoint: SessionCheckpointRecord) {
        let events = Dictionary(checkpoint.assessmentEventsRaw
            .split(separator: ",")
            .compactMap { event -> (String, String)? in
                let parts = event.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return nil }
                return (String(parts[0]), String(parts[1]))
            }, uniquingKeysWith: { _, latest in latest })
        response = checkpoint.response
        confidence = events["confidence"].flatMap(ConfidenceLevel.init(rawValue:))
        stageRawValue = events["sourceReviewStage"] ?? SourceReviewStage.recall.rawValue
    }
}

enum NFSourceReviewDraftIdentity {
    static let planPrefix = "source-review-draft|"

    static func planID(documentID: UUID) -> String {
        "\(planPrefix)\(documentID.uuidString.lowercased())"
    }

    static func isDraftPlanID(_ value: String?) -> Bool {
        value?.hasPrefix(planPrefix) == true
    }
}

/// Personal source recall uses the same durable item lifecycle as every other
/// exercise. The only answer reference is the immutable, device-local snapshot.
@MainActor
enum NFSourceReviewExactAdapter {
    static let templateFamily = "source.review.exact"
    static let legacyRecoveryReason = "This older draft did not save its original excerpt. Your answer remains available for review, but it cannot be compared with a changed source."

    static func makeRequest(
        chunk: NFSourceChunk, localeIdentifier: String,
        sessionID: UUID = UUID(), slotID: UUID = UUID(), attemptID: UUID = UUID(), at date: Date = Date()
    ) throws -> SessionRequest {
        let locale = Locale(identifier: localeIdentifier)
        func localized(_ key: String) -> String {
            NFAppLocalization.localizedCatalogValue(key, locale: locale)
        }
        let title = localized("Source recall")
        let prompt = localized("Recall the main ideas from the cited excerpt in your own words.")
        let instructions = localized("Write what you remember before revealing the saved excerpt. Then compare it with your answer and choose your own rating.")
        let comparison = localized("This is a personal comparison with your source. It does not change skill scores.")
        let documentID = chunk.documentID.uuidString
        let citation = NFExerciseCitation(
            id: "source-review.\(chunk.id)", documentID: documentID, sourceChunkID: chunk.id,
            title: chunk.sourceName, locator: .section(chunk.citationLabel),
            supportDescription: localized("Saved source excerpt"), excerptDigest: chunk.contentHash)
        let exercise = NFExercise(
            id: "\(templateFamily).\(slotID.uuidString)", schemaVersion: 1, generatorVersion: 1,
            templateID: templateFamily, templateFamily: templateFamily, templateVersion: 1,
            seed: 0, lab: .retrieval, purpose: .documentPractice, evidenceClass: .documentPractice,
            localeIdentifier: localeIdentifier, title: title, prompt: prompt,
            contextText: "\(chunk.sourceName) · \(chunk.citationLabel)", instructions: instructions,
            sourceContext: NFExerciseSourceContext(materialTitle: chunk.sourceName,
                sourceDocumentIDs: [documentID], sourceChunkIDs: [chunk.id], targetSkills: [TrainingLab.retrieval.skillID]),
            interaction: .selfCheck(.init(referenceAnswer: chunk.text,
                criteria: [localized("Compare the main ideas and details with the saved excerpt.")], asksForReflection: true)),
            difficulty: .init(overall: 0.5, reasoningSteps: 1, abstraction: 0.5,
                representationShift: 0, priorKnowledge: 0.5, timePressure: 0),
            skillWeights: [TrainingLab.retrieval.skillID: 1],
            strategies: [.init(id: "source-recall", title: title, summary: instructions,
                orderedSteps: [instructions], whenToUse: title)],
            representations: [.prose], citations: [citation],
            provenance: .init(contentTier: .deterministicGenerated, generatorID: templateFamily,
                generatorVersion: 1, modelIdentifier: nil, promptVersion: nil,
                sourceDocumentIDs: [documentID], sourceChunkIDs: [chunk.id],
                contentDigest: "source:\(chunk.contentHash)", validatorVersion: NFExerciseSchemaValidator.validatorVersion,
                isSourceGrounded: true),
            rubric: .init(criteria: [.init(id: "personal-comparison", description: comparison, weight: 1)],
                fullCreditThreshold: 1, permitsPartialCredit: false),
            feedback: .init(timing: .immediate, correctTitle: localized("Self-check saved"),
                correctExplanation: comparison, retryTitle: localized("Self-check saved"),
                retryExplanation: comparison, decisiveStep: comparison, hintLadder: [], errorExplanations: [:]),
            accessibility: .init(promptAccessibilityLabel: prompt, visualAlternative: nil,
                requiresVisualSpatialProcessing: false, supportsVoiceOver: true, supportsKeyboardOnly: true, usesMotion: false),
            assessmentProtected: false, expectedDurationSeconds: 120, timingEligible: false,
            responseEditPolicy: .lockedAfterSubmit, tags: ["source-review", "personal-study", "self-check"])
        try NFExerciseSchemaValidator.validate(exercise)
        var request = SessionRequest(lab: .retrieval, source: .focused, seed: 0,
            localeIdentifier: localeIdentifier, evidenceClass: .documentPractice, requestedItemCount: 1,
            planID: NFSourceReviewDraftIdentity.planID(documentID: chunk.documentID), planBlockID: chunk.id,
            isTimed: false)
        request.id = sessionID
        request.localSessionID = sessionID
        request.localCheckpoint = try .initial(request: request, exercise: exercise,
            slotID: slotID, attemptID: attemptID, at: date)
        request.freshlyAcceptedLaunch = true
        return request
    }

    static func belongsToSource(_ run: NFLocalSessionEnvelope, documentID: UUID, chunkID: String?) -> Bool {
        guard run.request.planID == NFSourceReviewDraftIdentity.planID(documentID: documentID),
              chunkID == nil || run.request.planBlockID == chunkID else { return false }
        return run.status == .suspended || run.status == .migrationRecovery
    }

    static func resumeRequest(_ run: NFLocalSessionEnvelope, ownerDeviceID: UUID) throws -> SessionRequest {
        guard run.ownerDeviceID == ownerDeviceID else { throw NFLocalSessionRepository.RepositoryError.wrongOwner }
        guard run.status == .suspended,
              run.schemaVersion == 1, run.checkpoint.schemaVersion == 1,
              let exercise = run.checkpoint.exercise,
              exercise.templateFamily == templateFamily,
              exercise.evidenceClass == .documentPractice,
              !exercise.assessmentProtected,
              case .selfCheck = exercise.interaction,
              exercise.provenance.sourceDocumentIDs.count == 1,
              exercise.provenance.sourceChunkIDs == [run.request.planBlockID ?? ""],
              run.request.planID == exercise.provenance.sourceDocumentIDs.first
                .flatMap(UUID.init(uuidString:)).map(NFSourceReviewDraftIdentity.planID(documentID:)),
              try NFLocalItemCheckpoint.digest(exercise) == run.checkpoint.exerciseDigest else {
            throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
        }
        try NFExerciseSchemaValidator.validate(exercise)
        var request = run.request
        request.localSessionID = run.id
        request.localCheckpoint = run.checkpoint
        request.freshlyAcceptedLaunch = nil
        return request
    }

    static func recoveryResponse(_ response: NFExerciseResponse) -> String {
        if case let .selfCheck(submission) = response { return submission.reflection ?? "" }
        return ""
    }
}

private struct SourceReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let document: SourceDocumentRecord
    let initialChunkID: String?
    let onReviewAnother: ((String) -> Void)?
    @State private var request: SessionRequest?
    @State private var recoveryReason: String?
    @State private var recoveredResponse = ""
    @State private var hasLegacyRecovery = false
    @State private var didLoad = false

    var body: some View {
        Group {
            if let request {
                UniversalSessionView(request: request)
                    .id(request.id)
                    .toolbar {
                        if let chunkID = request.planBlockID,
                           store.localSessions.archive.sessions.contains(where: { $0.id == request.id && $0.status == .completed }),
                           onReviewAnother != nil || store.chunks(for: document).count > 1 {
                            ToolbarItem(placement: .primaryAction) {
                                Button("Review another excerpt") {
                                    if let onReviewAnother {
                                        onReviewAnother(chunkID)
                                        dismiss()
                                    } else {
                                        startFresh(excluding: chunkID)
                                    }
                                }
                            }
                        }
                    }
            } else {
                NavigationStack {
                    recoveryView
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { dismiss() }
                            }
                        }
                }
            }
        }
        .task { load() }
    }

    private var recoveryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ContentUnavailableView("Saved work unavailable", systemImage: "doc.text.magnifyingglass",
                    description: Text(verbatim: NFAppLocalization.localizedCatalogValue(
                        recoveryReason ?? "Citation excerpt unavailable", locale: NFAppLocalization.preferredLocale)))
                if !recoveredResponse.isEmpty {
                    Text("Your response").font(.headline)
                    Text(verbatim: recoveredResponse).textSelection(.enabled)
                        .accessibilityIdentifier("source-recovery-response")
                }
                if hasLegacyRecovery {
                    Button("Start a new source review") { startFresh() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                if !document.localPath.isEmpty {
                    ShareLink(item: URL(fileURLWithPath: document.localPath)) {
                        Label("Open or export original", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .background { AppBackground() }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let run = store.localSessions.archive.sessions
            .filter({ NFSourceReviewExactAdapter.belongsToSource($0, documentID: document.id, chunkID: initialChunkID) })
            .max(by: { $0.updatedAt < $1.updatedAt }) {
            do { request = try NFSourceReviewExactAdapter.resumeRequest(run, ownerDeviceID: store.localSessions.ownerDeviceID) }
            catch {
                recoveryReason = error.localizedDescription
                recoveredResponse = NFSourceReviewExactAdapter.recoveryResponse(run.checkpoint.response)
            }
            return
        }
        if let legacy = store.sessionCheckpoints
            .filter({ !$0.isComplete && $0.planID == NFSourceReviewDraftIdentity.planID(documentID: document.id)
                && (initialChunkID == nil || $0.planBlockID == initialChunkID) })
            .max(by: { $0.updatedAt < $1.updatedAt }) {
            recoveryReason = NFSourceReviewExactAdapter.legacyRecoveryReason
            recoveredResponse = NFSourceReviewDraftSnapshot(checkpoint: legacy).response
            hasLegacyRecovery = true
            return
        }
        startFresh()
    }

    private func startFresh(excluding chunkID: String? = nil) {
        let chunks = store.chunks(for: document)
        let selected: NFSourceChunk?
        if let initialChunkID, chunkID == nil {
            selected = chunks.first { $0.id == initialChunkID }
        } else {
            selected = NFSourceReviewRotation.nextChunk(in: chunks, attempts: store.attempts, excluding: chunkID)
        }
        guard let selected else {
            recoveryReason = "Citation excerpt unavailable"
            return
        }
        do {
            request = try NFSourceReviewExactAdapter.makeRequest(chunk: selected,
                localeIdentifier: NFAppLocalization.preferredLocale.identifier)
            recoveryReason = nil
            recoveredResponse = ""
            hasLegacyRecovery = false
        } catch { recoveryReason = error.localizedDescription }
    }
}

enum NFSourceReadingBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedListItem(depth: Int, text: String)
    case orderedListItem(depth: Int, marker: String, text: String)
    case taskListItem(depth: Int, isChecked: Bool, text: String)
    case blockquote(String)
    case table(headers: [String], rows: [[String]])
    case code(language: String?, source: String)
    case displayMath(source: String)
    case thematicBreak
}

/// Turns imported source text into learner-facing reading units. This is kept
/// separate from `NFFormattedLearningText`: a source document needs semantic
/// navigation (headings, list items, and table rows), while a question usually
/// benefits from the compact mixed-content renderer.
enum NFSourceReadingParser {
    private struct ListItem {
        enum Kind {
            case unordered
            case ordered(marker: String)
            case task(isChecked: Bool)
        }

        let depth: Int
        let kind: Kind
        var text: String
    }

    static func parse(
        _ text: String,
        sourceLanguage: String? = nil,
        contentTypeTags: [String] = []
    ) -> [NFSourceReadingBlock] {
        guard !text.isEmpty else { return [] }

        let tags = Set(contentTypeTags.map { $0.lowercased() })
        let normalizedLanguage = sourceLanguage?.lowercased()
        if normalizedLanguage == "latex" || !tags.isDisjoint(with: ["latex", "math", "equation"]) {
            return [.displayMath(source: NFLearningTextParser.strippingMathDelimiters(text))]
        }
        if sourceLanguage != nil || !tags.isDisjoint(with: ["source-code", "code", "fenced-code"]) {
            return learningBlocks(
                NFLearningTextParser.parse(
                    text,
                    sourceLanguage: sourceLanguage,
                    contentTypeTags: contentTypeTags
                )
            )
        }
        if !tags.isDisjoint(with: ["csv", "rows", "schema-summary"]) && !tags.contains("markdown") {
            return [.code(language: "table", source: text)]
        }
        if tags.contains("plain-text") && !tags.contains("markdown") {
            return plainTextBlocks(text)
        }
        return markdownBlocks(text)
    }

    static func inlineMarkdown(_ source: String) -> AttributedString? {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        guard var attributed = try? AttributedString(markdown: source, options: options) else {
            return nil
        }
        // Imported source text is readable content, never navigation authority.
        attributed.link = nil
        return attributed
    }

    static func accessibilityText(_ source: String) -> String {
        if let attributed = inlineMarkdown(source) {
            return String(attributed.characters)
        }
        return source
    }

    private static func markdownBlocks(_ source: String) -> [NFSourceReadingBlock] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [NFSourceReadingBlock] = []
        var paragraphLines: [String] = []
        var pendingListItem: ListItem?
        var index = 0

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            result.append(.paragraph(paragraphLines.joined(separator: "\n")))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushListItem() {
            guard let item = pendingListItem else { return }
            switch item.kind {
            case .unordered:
                result.append(.unorderedListItem(depth: item.depth, text: item.text))
            case let .ordered(marker):
                result.append(.orderedListItem(depth: item.depth, marker: marker, text: item.text))
            case let .task(isChecked):
                result.append(.taskListItem(depth: item.depth, isChecked: isChecked, text: item.text))
            }
            pendingListItem = nil
        }

        func flushText() {
            flushListItem()
            flushParagraph()
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fence = fenceOpening(trimmed) {
                flushText()
                var codeLines: [String] = []
                index += 1
                while index < lines.count, !isFenceClosing(lines[index], marker: fence.marker) {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                result.append(.code(
                    language: fence.language,
                    source: codeLines.joined(separator: "\n")
                ))
                continue
            }

            if let math = displayMath(startingAt: index, lines: lines) {
                flushText()
                result.append(.displayMath(source: math.source))
                index = math.nextIndex
                continue
            }

            if let table = markdownTable(startingAt: index, lines: lines) {
                flushText()
                result.append(.table(headers: table.headers, rows: table.rows))
                index = table.nextIndex
                continue
            }

            if let heading = atxHeading(line) {
                flushText()
                result.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if index + 1 < lines.count,
               !trimmed.isEmpty,
               let level = setextHeadingLevel(lines[index + 1]) {
                flushText()
                result.append(.heading(level: level, text: trimmed))
                index += 2
                continue
            }

            if isThematicBreak(line) {
                flushText()
                result.append(.thematicBreak)
                index += 1
                continue
            }

            if let item = listItem(line) {
                flushParagraph()
                flushListItem()
                pendingListItem = item
                index += 1
                continue
            }

            if let quote = blockquote(line) {
                flushText()
                var quoteLines = [quote]
                index += 1
                while index < lines.count, let continuation = blockquote(lines[index]) {
                    quoteLines.append(continuation)
                    index += 1
                }
                result.append(.blockquote(quoteLines.joined(separator: "\n")))
                continue
            }

            if trimmed.isEmpty {
                flushText()
                index += 1
                continue
            }

            if pendingListItem != nil, leadingWhitespaceCount(line) > 0 {
                pendingListItem?.text += "\n" + trimmed
            } else {
                flushListItem()
                paragraphLines.append(line)
            }
            index += 1
        }

        flushText()
        return result
    }

    private static func plainTextBlocks(_ source: String) -> [NFSourceReadingBlock] {
        source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(NFSourceReadingBlock.paragraph)
    }

    private static func learningBlocks(_ blocks: [NFLearningTextBlock]) -> [NFSourceReadingBlock] {
        blocks.flatMap { block -> [NFSourceReadingBlock] in
            switch block {
            case let .markdown(source): markdownBlocks(source)
            case let .plainText(source): plainTextBlocks(source)
            case let .code(language, source): [.code(language: language, source: source)]
            case let .displayMath(source): [.displayMath(source: source)]
            }
        }
    }

    private static func atxHeading(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefix = trimmed.prefix { $0 == "#" }
        guard (1...6).contains(prefix.count),
              trimmed.dropFirst(prefix.count).first?.isWhitespace == true else { return nil }
        var title = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        while title.last == "#" { title.removeLast() }
        title = title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : (prefix.count, title)
    }

    private static func setextHeadingLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }
        if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let marker = compact.first,
              marker == "-" || marker == "*" || marker == "_" else { return false }
        return compact.allSatisfy { $0 == marker }
    }

    private static func listItem(_ line: String) -> ListItem? {
        let indentation = leadingWhitespaceCount(line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let depth = max(0, indentation / 2)

        if trimmed.count >= 2,
           let marker = trimmed.first,
           "-*+".contains(marker),
           trimmed.dropFirst().first?.isWhitespace == true {
            let text = String(trimmed.dropFirst(2))
            if text.count >= 3, text.first == "[",
               let closing = text.firstIndex(of: "]"),
               closing == text.index(text.startIndex, offsetBy: 2) {
                let state = text[text.index(after: text.startIndex)]
                let contentStart = text.index(after: closing)
                let content = String(text[contentStart...]).trimmingCharacters(in: .whitespaces)
                if state == " " || state == "x" || state == "X" {
                    return ListItem(
                        depth: depth,
                        kind: .task(isChecked: state == "x" || state == "X"),
                        text: content
                    )
                }
            }
            return ListItem(depth: depth, kind: .unordered, text: text)
        }

        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let afterDigits = trimmed.dropFirst(digits.count)
        guard let punctuation = afterDigits.first,
              punctuation == "." || punctuation == ")",
              afterDigits.dropFirst().first?.isWhitespace == true else { return nil }
        let marker = String(digits) + String(punctuation)
        let text = String(afterDigits.dropFirst(2))
        return ListItem(depth: depth, kind: .ordered(marker: marker), text: text)
    }

    private static func blockquote(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == ">" else { return nil }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func fenceOpening(_ line: String) -> (marker: String, language: String?)? {
        guard line.hasPrefix("```") || line.hasPrefix("~~~") else { return nil }
        let markerCharacter = line.first!
        let marker = String(line.prefix { $0 == markerCharacter })
        guard marker.count >= 3 else { return nil }
        let language = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        return (marker, language.isEmpty ? nil : language)
    }

    private static func isFenceClosing(_ line: String, marker: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == marker.first else { return false }
        return trimmed.prefix { $0 == marker.first }.count >= marker.count
    }

    private static func displayMath(
        startingAt index: Int,
        lines: [String]
    ) -> (source: String, nextIndex: Int)? {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("$$") {
            let remainder = String(trimmed.dropFirst(2))
            if let closing = remainder.range(of: "$$") {
                let source = String(remainder[..<closing.lowerBound]).trimmingCharacters(in: .whitespaces)
                return source.isEmpty ? nil : (source, index + 1)
            }
            var mathLines = remainder.isEmpty ? [] : [remainder]
            var cursor = index + 1
            while cursor < lines.count {
                let candidate = lines[cursor]
                if let closing = candidate.range(of: "$$") {
                    mathLines.append(String(candidate[..<closing.lowerBound]))
                    return (mathLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), cursor + 1)
                }
                mathLines.append(candidate)
                cursor += 1
            }
            return nil
        }
        if trimmed.hasPrefix("\\[") {
            let remainder = String(trimmed.dropFirst(2))
            if let closing = remainder.range(of: "\\]") {
                let source = String(remainder[..<closing.lowerBound]).trimmingCharacters(in: .whitespaces)
                return source.isEmpty ? nil : (source, index + 1)
            }
            var mathLines = remainder.isEmpty ? [] : [remainder]
            var cursor = index + 1
            while cursor < lines.count {
                let candidate = lines[cursor]
                if let closing = candidate.range(of: "\\]") {
                    mathLines.append(String(candidate[..<closing.lowerBound]))
                    return (mathLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), cursor + 1)
                }
                mathLines.append(candidate)
                cursor += 1
            }
        }
        return nil
    }

    private static func markdownTable(
        startingAt index: Int,
        lines: [String]
    ) -> (headers: [String], rows: [[String]], nextIndex: Int)? {
        guard index + 1 < lines.count else { return nil }
        let headers = markdownTableCells(lines[index])
        let delimiter = markdownTableCells(lines[index + 1])
        guard headers.count >= 2,
              delimiter.count == headers.count,
              delimiter.allSatisfy(isTableDelimiterCell) else { return nil }

        var rows: [[String]] = []
        var cursor = index + 2
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.contains("|") else { break }
            var cells = markdownTableCells(lines[cursor])
            if cells.count < headers.count {
                cells.append(contentsOf: repeatElement("", count: headers.count - cells.count))
            } else if cells.count > headers.count {
                cells = Array(cells.prefix(headers.count))
            }
            rows.append(cells)
            cursor += 1
        }
        return (headers, rows, cursor)
    }

    private static func markdownTableCells(_ line: String) -> [String] {
        var source = line.trimmingCharacters(in: .whitespaces)
        if source.first == "|" { source.removeFirst() }
        if source.last == "|" { source.removeLast() }

        var cells: [String] = []
        var current = ""
        var escaped = false
        var inCode = false
        for character in source {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "`" {
                inCode.toggle()
                current.append(character)
            } else if character == "|" && !inCode {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func isTableDelimiterCell(_ cell: String) -> Bool {
        var candidate = cell.trimmingCharacters(in: .whitespaces)
        if candidate.first == ":" { candidate.removeFirst() }
        if candidate.last == ":" { candidate.removeLast() }
        return candidate.count >= 3 && candidate.allSatisfy { $0 == "-" }
    }

    private static func leadingWhitespaceCount(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { count, character in
            count + (character == "\t" ? 4 : 1)
        }
    }
}

struct NFSourceTableAccessibilityModel: Equatable, Sendable {
    let headers: [String]
    let rows: [[String]]

    var summary: String {
        NFAppLocalization.localized(
            "Table with \(NFAppLocalization.formattedColumnCount(headers.count)) and \(NFAppLocalization.formattedDataRowCount(rows.count)).",
            locale: NFAppLocalization.preferredLocale,
            comment: "Accessible source-table summary with localized column and data-row counts."
        )
    }

    func rowLabel(at rowIndex: Int) -> String {
        NFAppLocalization.localized(
            "Row \(rowIndex + 1) of \(rows.count)",
            locale: NFAppLocalization.preferredLocale,
            comment: "Accessible source-table row position; placeholders are current and total row counts."
        )
    }

    func cellLabel(rowIndex: Int, columnIndex: Int) -> String {
        let header = headers.indices.contains(columnIndex)
            ? NFSourceReadingParser.accessibilityText(headers[columnIndex])
            : NFAppLocalization.localized("Unlabeled column", locale: NFAppLocalization.preferredLocale, comment: "Fallback accessible source-table column name.")
        let cell = rows.indices.contains(rowIndex) && rows[rowIndex].indices.contains(columnIndex)
            ? NFSourceReadingParser.accessibilityText(rows[rowIndex][columnIndex])
            : NFAppLocalization.localized("Empty", locale: NFAppLocalization.preferredLocale, comment: "Accessible source-table empty-cell value.")
        return NFAppLocalization.localized(
            "Row \(rowIndex + 1) of \(rows.count), column \(columnIndex + 1) of \(headers.count). \(header): \(cell)",
            locale: NFAppLocalization.preferredLocale,
            comment: "Accessible source-table cell with row/column position, header, and value."
        )
    }
}

private struct NFSourceReadingText: View {
    private let blocks: [NFSourceReadingBlock]

    init(_ text: String, sourceLanguage: String?, contentTypeTags: [String]) {
        blocks = NFSourceReadingParser.parse(
            text,
            sourceLanguage: sourceLanguage,
            contentTypeTags: contentTypeTags
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: NFSourceReadingBlock) -> some View {
        switch block {
        case let .heading(level, text):
            inlineText(text)
                .font(headingFont(level))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: NFSourceReadingParser.accessibilityText(text)))
                .accessibilityAddTraits(.isHeader)

        case let .paragraph(text):
            inlineText(text)
                .font(.body)
                .lineSpacing(4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: NFSourceReadingParser.accessibilityText(text)))

        case let .unorderedListItem(depth, text):
            listRow(marker: "•", depth: depth, text: text, accessibilityPrefix: "Bullet")

        case let .orderedListItem(depth, marker, text):
            listRow(marker: marker, depth: depth, text: text, accessibilityPrefix: marker)

        case let .taskListItem(depth, isChecked, text):
            listRow(
                marker: isChecked ? "☑" : "☐",
                depth: depth,
                text: text,
                accessibilityPrefix: isChecked ? "Completed item" : "Open item"
            )

        case let .blockquote(text):
            HStack(alignment: .top, spacing: 12) {
                Capsule()
                    .fill(NFTheme.indigo.opacity(0.55))
                    .frame(width: 4)
                    .accessibilityHidden(true)
                inlineText(text)
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "Quote. \(NFSourceReadingParser.accessibilityText(text))"))

        case let .table(headers, rows):
            tableView(headers: headers, rows: rows)

        case let .code(language, source):
            VStack(alignment: .leading, spacing: 8) {
                if let language, !language.isEmpty {
                    Text(verbatim: language.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                ScrollView(.horizontal) {
                    Text(verbatim: source)
                        .font(.system(.body, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: false)
                        .textSelection(.enabled)
                        .padding(.vertical, 2)
                }
            }
            .nfCard(cornerRadius: 14, padding: 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: codeAccessibilityLabel(language: language, source: source)))

        case let .displayMath(source):
            NFLaTeXEquationView(source: source)
                .padding(.vertical, 3)
                .nfCard(cornerRadius: 14, padding: 12)

        case .thematicBreak:
            Divider()
                .padding(.vertical, 2)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func inlineText(_ source: String) -> some View {
        if let attributed = NFSourceReadingParser.inlineMarkdown(source) {
            Text(attributed)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else {
            Text(verbatim: source)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func listRow(
        marker: String,
        depth: Int,
        text: String,
        accessibilityPrefix: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: marker)
                .font(.body.weight(.semibold))
                .foregroundStyle(NFTheme.indigoForeground)
                .frame(minWidth: 24, alignment: .trailing)
                .accessibilityHidden(true)
            inlineText(text)
                .font(.body)
                .lineSpacing(3)
        }
        .padding(.leading, CGFloat(min(4, depth)) * 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(accessibilityPrefix). \(NFSourceReadingParser.accessibilityText(text))"))
    }

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        let accessibilityModel = NFSourceTableAccessibilityModel(headers: headers, rows: rows)
        return ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        inlineText(header)
                            .font(.subheadline.weight(.bold))
                            .frame(minWidth: 110, maxWidth: 240, alignment: .topLeading)
                    }
                }

                Divider()
                    .gridCellUnsizedAxes(.horizontal)

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            inlineText(cell)
                                .font(.body)
                                .frame(minWidth: 110, maxWidth: 240, alignment: .topLeading)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(12)
        }
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.primary.opacity(0.08))
        }
        .accessibilityRepresentation {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: accessibilityModel.summary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(rows.indices, id: \.self) { rowIndex in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: accessibilityModel.rowLabel(at: rowIndex))
                            .accessibilityAddTraits(.isHeader)
                        ForEach(headers.indices, id: \.self) { columnIndex in
                            Text(verbatim: accessibilityModel.cellLabel(
                                rowIndex: rowIndex,
                                columnIndex: columnIndex
                            ))
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title.bold()
        case 2: .title2.bold()
        case 3: .title3.bold()
        default: .headline
        }
    }

    private func codeAccessibilityLabel(language: String?, source: String) -> String {
        guard let language, !language.isEmpty else { return "Code. \(source)" }
        return "\(language) code. \(source)"
    }

}

private struct SourceChunkBrowserView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let document: SourceDocumentRecord
    let initialChunkID: String?
    @State private var searchText = ""
    @AccessibilityFocusState private var focusedChunkID: String?

    init(document: SourceDocumentRecord, initialChunkID: String? = nil) {
        self.document = document
        self.initialChunkID = initialChunkID
    }

    private var chunks: [NFSourceChunk] {
        let all = store.chunks(for: document)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            NFSectionHeader(
                                "Source text",
                                eyebrow: document.filename,
                                subtitle: "Search the exact excerpts used for review and practice."
                            )
                            ForEach(chunks) { chunk in
                                VStack(alignment: .leading, spacing: 10) {
                                    Label(chunk.locator.displayText, systemImage: "mappin.and.ellipse")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(NFTheme.cyanForeground)
                                    NFSourceReadingText(
                                        chunk.text,
                                        sourceLanguage: chunk.language,
                                        contentTypeTags: chunk.contentTypeTags
                                    )
                                        .textSelection(.enabled)
                                }
                                .nfCard(cornerRadius: 16, padding: 14)
                                .overlay {
                                    if chunk.id == initialChunkID {
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(NFTheme.indigoForeground, lineWidth: 2)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .id(chunk.id)
                                .accessibilityFocused($focusedChunkID, equals: chunk.id)
                            }
                            if chunks.isEmpty {
                                ContentUnavailableView("No matching excerpt", systemImage: "text.magnifyingglass", description: Text("Try another phrase from this source."))
                                    .frame(minHeight: 260)
                            }
                        }
                        .padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
                    }
                    .onAppear {
                        guard let initialChunkID else { return }
                        proxy.scrollTo(initialChunkID, anchor: .top)
                        Task { @MainActor in
                            await Task.yield()
                            focusedChunkID = initialChunkID
                        }
                    }
                }
            }
            .navigationTitle("Source viewer")
            .searchable(text: $searchText, prompt: "Search this source")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .nfDesktopPresentationFrame(minWidth: 420, idealWidth: 820, minHeight: 600, idealHeight: 820)
    }
}

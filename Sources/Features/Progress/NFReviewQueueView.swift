import SwiftUI

/// A citation sheet keeps the acknowledged attempt identity even if the live
/// session later advances. It never carries source text or a draft answer.
struct NFCommittedCitationRoute: Equatable, Identifiable {
    let attemptID: UUID
    let citationID: String
    let sessionID: UUID
    let exerciseDigest: String
    var id: String { [attemptID.uuidString, sessionID.uuidString, exerciseDigest, citationID].joined(separator: "|") }

    /// History uses the exact exercise and session identity retained by its
    /// originating detail, never a fresh lookup under a potentially reused UUID.
    static func savedHistory(attemptID: UUID, citationID: String, sessionID: UUID,
                             exercise: NFExercise) -> Self {
        .init(attemptID: attemptID, citationID: citationID, sessionID: sessionID,
            exerciseDigest: (try? NFLocalItemCheckpoint.digest(exercise)) ?? "")
    }
}

struct NFCommittedFeedbackCitations: Equatable {
    let attemptID: UUID
    let sessionID: UUID
    let exerciseDigest: String
    let citations: [NFExerciseCitation]

    func route(for citationID: String) -> NFCommittedCitationRoute? {
        guard citations.filter({ $0.id == citationID }).count == 1 else { return nil }
        return .init(attemptID: attemptID, citationID: citationID,
            sessionID: sessionID, exerciseDigest: exerciseDigest)
    }
}

/// Bounded, stable prefixes let native controls reveal more rows without
/// constructing every saved or deferred row in the initial view hierarchy.
enum NFReviewQueuePagination {
    static let pageSize = 50
    static func visibleCount(requested: Int, total: Int) -> Int {
        min(max(0, total), max(pageSize, requested))
    }
    static func nextCount(current: Int, total: Int) -> Int {
        let current = visibleCount(requested: current, total: total)
        return current + min(pageSize, max(0, total - current))
    }
    static func visible<Element>(_ values: [Element], through count: Int) -> ArraySlice<Element> {
        values.prefix(visibleCount(requested: count, total: values.count))
    }
}

struct NFReviewQueueSavedPresentation: Equatable, Identifiable {
    let id: UUID
    let title: String
    let detail: String
    let symbol: String
    let isProtected: Bool
}

extension AppStore {
    func reviewQueueSavedPresentation(for attempt: AttemptRecord) -> NFReviewQueueSavedPresentation {
        let value = historyPresentation(for: .init(attempt: attempt))
        let protected = value.source == .protectedAssessment
        return .init(id: value.id,
            title: protected ? NFAppLocalization.localizedCatalogValue("Protected skill check", locale: NFAppLocalization.preferredLocale) : value.prompt,
            detail: value.activityTitle + " · " + value.resultTitle,
            symbol: protected ? "lock.shield.fill" : value.source.symbol,
            isProtected: protected)
    }

    func reviewTopic(for entry: NFReviewDueEntry) -> String {
        let state = entry.origin.state
        return NFDefaultContentCatalog.activities(for: state.lab).first {
            state.id.hasSuffix("." + $0.templateSlug) || state.templateFamily == $0.mechanicID
        }?.localizedTitle ?? state.lab.title
    }

    func reviewExpectedSeconds(for entry: NFReviewDueEntry) -> Int {
        guard let record = attempts.first(where: { $0.id == entry.origin.anchorAttemptID }),
              historyPresentation(for: .init(attempt: record)).source != .protectedAssessment,
              let snapshot = exerciseSnapshot(for: record.id), !snapshot.assessmentProtected else { return 60 }
        return min(180, max(15, snapshot.expectedDurationSeconds))
    }
}

struct NFReviewQueueView: View {
    @Environment(AppStore.self) private var store
    @State private var visibleDueCount = NFReviewQueuePagination.pageSize
    @State private var visibleDeferredCount = NFReviewQueuePagination.pageSize
    @State private var visibleSavedCount = NFReviewQueuePagination.pageSize
    @State private var actionError: String?
    @State private var savedMessage: String?

    private var savedForLater: [AttemptRecord] {
        let identifiers = Set(store.privateStudyMetadata.annotations.filter(\.bookmarked).map(\.id))
        return store.attempts.filter { identifiers.contains($0.id) }.sorted {
            $0.submittedAt == $1.submittedAt ? $0.id.uuidString < $1.id.uuidString : $0.submittedAt > $1.submittedAt
        }
    }

    private var recentlyRepaired: [AttemptRecord] {
        let sessions = Set(store.localSessions.archive.sessions.filter { $0.request.repairOriginAttemptID != nil }.map(\.id))
        return Array(store.attempts.filter { sessions.contains($0.sessionID) }.sorted { $0.submittedAt > $1.submittedAt }.prefix(10))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            queue(at: timeline.date)
        }
        .alert("Review not changed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    private func queue(at date: Date) -> some View {
        let entries = store.reviewDueEntries(at: date, calendar: .current)
        let accepted = store.acceptedReviewMemoryItemIDs
        let ready = entries.filter { $0.isDue(at: date) && !accepted.contains($0.id) }
        let deferred = entries.filter { $0.isDeferred(at: date) }
        let saved = savedForLater
        return VStack(alignment: .leading, spacing: 20) {
            Text("Due now").font(.title2.bold())
            if store.privateStudyMetadataUnavailableReason != nil {
                Text("Your saved review preferences are unavailable. Regular reminders remain active, and your original saved data is unchanged.")
                    .foregroundStyle(.secondary).accessibilityIdentifier("review-preferences-unavailable")
            }
            if let savedMessage {
                Text(savedMessage).foregroundStyle(.secondary).accessibilityIdentifier("review-deferral-saved")
            }
            if ready.isEmpty {
                if accepted.isEmpty { Label("You're up to date.", systemImage: "checkmark.circle") }
                Text("Scheduled reviews appear here when they are ready.").foregroundStyle(.secondary)
            } else {
                Text(NFAppLocalization.formattedQuestionCount(ready.count))
                    .accessibilityIdentifier("review-due-count")
                Button("Start review") { _ = store.requestReviewsDue() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("review-start")
                Text("Each review session includes up to five questions from one activity. The remaining reviews stay in your queue.")
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(Array(NFReviewQueuePagination.visible(ready, through: visibleDueCount))) { entry in
                    dueCard(entry, at: date)
                }
                if ready.count > visibleDueCount {
                    Button("Show more reviews") {
                        visibleDueCount = NFReviewQueuePagination.nextCount(current: visibleDueCount, total: ready.count)
                    }.accessibilityIdentifier("review-show-more-due")
                }
            }
            if !accepted.isEmpty {
                Text("Your saved review is ready to continue from Today.").foregroundStyle(.secondary)
                Button("Continue saved review") { store.selectedDestination = .today }
                    .buttonStyle(.bordered)
            }
            Text("Saved for later").font(.title2.bold())
            ForEach(Array(NFReviewQueuePagination.visible(deferred, through: visibleDeferredCount))) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.reviewTopic(for: entry)).font(.headline)
                    Text("Another question for this skill").foregroundStyle(.secondary)
                    Text("Deferred until \(NFAppLocalization.formattedDate(entry.dueAt, date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                }.nfCard().accessibilityIdentifier("review-deferred-" + entry.id)
            }
            if deferred.count > visibleDeferredCount {
                Button("Show more") {
                    visibleDeferredCount = NFReviewQueuePagination.nextCount(current: visibleDeferredCount, total: deferred.count)
                }.accessibilityIdentifier("review-show-more-deferred")
            }
            if saved.isEmpty, deferred.isEmpty, store.privateStudyMetadataUnavailableReason == nil {
                Text("Bookmark an answer in History to return to its explanation.").foregroundStyle(.secondary)
            }
            ForEach(Array(NFReviewQueuePagination.visible(saved, through: visibleSavedCount))) { attempt in
                savedRow(attempt, canRemoveBookmark: true)
            }
            if saved.count > visibleSavedCount {
                Button("Show more") {
                    visibleSavedCount = NFReviewQueuePagination.nextCount(current: visibleSavedCount, total: saved.count)
                }.accessibilityIdentifier("review-show-more-saved")
            }
            Text("Recently repaired").font(.title2.bold())
            if recentlyRepaired.isEmpty {
                Text("Fresh similar questions you complete after feedback appear here.").foregroundStyle(.secondary)
            }
            ForEach(recentlyRepaired) { attempt in
                savedRow(attempt, canRemoveBookmark: false)
            }
            NavigationLink(value: NFProgressRoute.history(nil)) {
                Label("Find a prior explanation", systemImage: "clock.arrow.circlepath")
            }.buttonStyle(.bordered)
        }
    }

    private func dueCard(_ entry: NFReviewDueEntry, at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.reviewTopic(for: entry)).font(.headline)
            Text(entry.origin.state.lab.title).font(.subheadline)
            Text("Due after your earlier practice. Another question will check this skill.").foregroundStyle(.secondary)
            Text("About \(NFAppLocalization.formattedMinutes(max(1, Int(ceil(Double(store.reviewExpectedSeconds(for: entry)) / 60)))))")
                .font(.footnote)
            Button("Defer until tomorrow") {
                do {
                    let records = try store.deferReviews(memoryItemIDs: [entry.id], at: Date(), calendar: .current)
                    if let until = records.first?.deferredUntil {
                        savedMessage = NFAppLocalization.localized("Review deferred until \(NFAppLocalization.formattedDate(until, date: .abbreviated, time: .shortened)).",
                            locale: NFAppLocalization.preferredLocale, comment: "Successful local review deferral confirmation with the saved learner-day return time.")
                    }
                } catch { show(error) }
            }
            .buttonStyle(.bordered)
            .disabled(store.privateStudyMetadataUnavailableReason != nil)
            .accessibilityIdentifier("review-defer-" + entry.id)
            NavigationLink(value: NFProgressRoute.attempt(entry.origin.anchorAttemptID)) {
                Text("Review the earlier explanation or report a problem")
            }.font(.footnote)
        }.nfCard()
    }

    private func savedRow(_ attempt: AttemptRecord, canRemoveBookmark: Bool) -> some View {
        let value = store.reviewQueueSavedPresentation(for: attempt)
        return VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: NFProgressRoute.attempt(value.id)) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(value.title, systemImage: value.symbol).lineLimit(3)
                    Text(value.detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if canRemoveBookmark {
                Button("Remove bookmark") {
                    guard var annotation = store.privateStudyMetadata.annotations.first(where: { $0.id == value.id }) else { return }
                    annotation.bookmarked = false
                    do { try store.saveStudyAnnotation(annotation) } catch { show(error) }
                }.buttonStyle(.bordered)
            }
        }.nfCard()
    }

    private func show(_ error: Error) {
        actionError = (error as? NFReviewDeferralError)?.errorDescription
            ?? NFAppLocalization.localizedCatalogValue("The review preference could not be saved. Your schedule is unchanged.", locale: NFAppLocalization.preferredLocale)
    }
}

/// Read-only supplements are made only from the retained question and receipt.
/// Current content generators and replacement sources never supply missing hints.
struct NFHistoryContextProjection: Equatable, Sendable {
    let context: String?
    let representations: [NFExerciseRepresentation]
    let initialLogicState: [String: String]
    let usedHints: [String]
    let hasUnavailableHints: Bool
    let citations: [NFExerciseCitation]

    static func make(exercise: NFExercise?, hintCount: Int, isProtected: Bool, mathWork: NFMathWorkDraft? = nil) -> Self {
        guard !isProtected, exercise?.assessmentProtected != true else {
            return .init(context: nil, representations: [], initialLogicState: [:], usedHints: [], hasUnavailableHints: false, citations: [])
        }
        let initialState: [String: String]
        if let exercise, case .logicState(let schema) = exercise.interaction { initialState = schema.initialState }
        else { initialState = [:] }
        let count = max(0, hintCount)
        let hintLadder: [String]
        if let mathWork { hintLadder = exercise.map { mathWork.isCompatible(with: $0) } == true ? mathWork.hintLadder : [] }
        else { hintLadder = exercise?.feedback.hintLadder ?? [] }
        let hints = Array(hintLadder.prefix(count))
        return .init(context: exercise?.independentContextText,
            representations: exercise?.independentRepresentations ?? [], initialLogicState: initialState, usedHints: hints,
            hasUnavailableHints: hints.count < count || hints.contains(where: { $0.isEmpty }),
            citations: exercise?.citations ?? [])
    }
}

struct NFHistorySourceDocument: Equatable, Sendable {
    let id: UUID
    let extractionVersion: Int
}

struct NFHistoryCitationPresentation: Equatable, Sendable {
    enum Availability: Equatable, Sendable { case available, missingSource, changedSource, unverifiedRevision, unavailableCitation, protectedContent }
    let availability: Availability
    let citation: NFExerciseCitation?
    let matchedExtractionVersion: Int?
    let currentExcerpt: String?
    let savedExcerpt: String?
}

enum NFHistoryCitationPolicy {
    static func resolve(exercise: NFExercise?, citationID: String, documents: [NFHistorySourceDocument],
                        chunks: [NFSourceChunk], isProtected: Bool) -> NFHistoryCitationPresentation {
        // Do not construct citation titles, references, digests or excerpts for
        // protected receipts, including imported marker-only protection.
        guard !isProtected, exercise?.assessmentProtected != true else {
            return .init(availability: .protectedContent, citation: nil,
                matchedExtractionVersion: nil, currentExcerpt: nil, savedExcerpt: nil)
        }
        guard let exercise, exercise.citations.filter({ $0.id == citationID }).count == 1,
              let citation = exercise.citations.first(where: { $0.id == citationID }) else {
            return .init(availability: .unavailableCitation, citation: nil,
                matchedExtractionVersion: nil, currentExcerpt: nil, savedExcerpt: nil)
        }
        let savedExcerpt: String?
        if exercise.templateFamily == "source.review.exact", exercise.citations.count == 1,
           exercise.sourceContext.sourceDocumentIDs.contains(citation.documentID),
           let chunkID = citation.sourceChunkID, exercise.sourceContext.sourceChunkIDs.contains(chunkID),
           case .selfCheck(let schema) = exercise.interaction,
           matches(schema.referenceAnswer, digest: citation.excerptDigest) {
            savedExcerpt = schema.referenceAnswer
        } else { savedExcerpt = nil }
        func result(_ availability: NFHistoryCitationPresentation.Availability) -> NFHistoryCitationPresentation {
            .init(availability: availability, citation: citation, matchedExtractionVersion: nil,
                currentExcerpt: nil, savedExcerpt: savedExcerpt)
        }
        guard let documentID = UUID(uuidString: citation.documentID),
              documents.filter({ $0.id == documentID }).count == 1,
              let document = documents.first(where: { $0.id == documentID }),
              let chunkID = citation.sourceChunkID else { return result(.missingSource) }
        let matchingChunks = chunks.filter { $0.id == chunkID && $0.documentID == documentID }
        guard matchingChunks.count == 1, let chunk = matchingChunks.first else {
            return result(.missingSource)
        }
        guard supportedDigest(citation.excerptDigest), supportedDigest(chunk.contentHash),
              chunk.documentVersion > 0, document.extractionVersion > 0 else { return result(.unverifiedRevision) }
        guard document.extractionVersion == chunk.documentVersion,
              matches(chunk.text, digest: citation.excerptDigest),
              matches(chunk.text, digest: chunk.contentHash) else { return result(.changedSource) }
        return .init(availability: .available, citation: citation,
            matchedExtractionVersion: chunk.documentVersion, currentExcerpt: chunk.text, savedExcerpt: savedExcerpt)
    }

    /// SourceGrounding's explicit shipped digest contract. Unknown algorithms
    /// cannot be used as permission to substitute current text for a saved source.
    static func supportedDigest(_ digest: String?) -> Bool {
        guard let digest, (1...16).contains(digest.count) else { return false }
        return digest.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }
    static func matches(_ text: String, digest: String?) -> Bool {
        guard supportedDigest(digest), let digest else { return false }
        return digest.lowercased() == String(AdaptiveEngine.fnv1a64(text), radix: 16)
    }
}

struct NFHistoryStimulusView: View {
    @Environment(AppStore.self) private var store
    let exercise: NFExercise
    let attemptID: UUID
    let sessionID: UUID
    @State private var selectedCitation: NFCommittedCitationRoute?
    private var isRestricted: Bool {
        guard let record = store.attempts.first(where: { $0.id == attemptID }) else { return true }
        return exercise.assessmentProtected || store.historyPresentation(for: .init(attempt: record)).source == .protectedAssessment
    }

    var body: some View {
        let context = NFHistoryContextProjection.make(exercise: exercise, hintCount: 0, isProtected: isRestricted)
        VStack(alignment: .leading, spacing: 16) {
            if let text = context.context, !text.isEmpty { Text(text).textSelection(.enabled) }
            if !isRestricted, exercise.requiresRetrievalAssetContract {
                if let asset = NFRetrievalAssetContract.make(exercise: exercise) { NFRetrievalAssetStimulusView(asset: asset) }
                else { Text("This saved reconstruction needs a compatible version. The original question and response remain saved.").font(.subheadline) }
            }
            ForEach(Array((!exercise.requiresRetrievalAssetContract ? context.representations : []).enumerated()), id: \.offset) { _, representation in
                switch representation {
                case .table(let headers, let rows, let summary):
                    VStack(alignment: .leading, spacing: 10) {
                        Text(summary).font(.subheadline)
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Row \(index + 1)").font(.footnote.bold())
                                ForEach(Array(row.enumerated()), id: \.offset) { column, value in
                                    LabeledContent(column < headers.count ? headers[column] : "", value: value)
                                }
                            }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                case .code(_, let source, let summary):
                    Text(summary).font(.subheadline)
                    Text(source).font(.body.monospaced()).textSelection(.enabled)
                case .equation(let latex, let spoken):
                    NFLaTeXEquationView(source: latex).accessibilityLabel(spoken)
                case .spatial(let metadata): NFSpatialDiagramView(metadata: metadata, localeIdentifier: exercise.localeIdentifier, prefersReducedMotion: true,
                    exercise: exercise, learningPhase: isRestricted ? .independent : .committedFeedback)
                case .logicState(let metadata):
                    VStack(alignment: .leading, spacing: 12) {
                        if !context.initialLogicState.isEmpty {
                            Text("Original starting state").font(.headline)
                            ForEach(context.initialLogicState.keys.sorted(), id: \.self) { key in
                                LabeledContent(key, value: context.initialLogicState[key] ?? "")
                            }
                        }
                        Text("Original variables").font(.headline)
                        ForEach(metadata.variables.keys.sorted(), id: \.self) { key in
                            LabeledContent(key, value: metadata.variables[key] ?? "")
                        }
                        if !metadata.transitions.isEmpty {
                            Text("Original transitions").font(.headline)
                            ForEach(Array(metadata.transitions.enumerated()), id: \.offset) { index, transition in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Step \(index + 1)").font(.subheadline.bold())
                                    Text(transition.condition).textSelection(.enabled)
                                    Text(transition.mutation).font(.body.monospaced()).textSelection(.enabled)
                                }
                            }
                        }
                        if !metadata.invariants.isEmpty {
                            Text("Original rules").font(.headline)
                            ForEach(metadata.invariants.keys.sorted(), id: \.self) { key in
                                LabeledContent(key, value: metadata.invariants[key] ?? "")
                            }
                        }
                    }.accessibilityIdentifier("history-original-logic-state")
                case .prose: EmptyView()
                }
            }
            if !context.citations.isEmpty {
                Text("Source citations").font(.headline)
                ForEach(context.citations) { citation in
                    Button {
                        selectedCitation = .savedHistory(attemptID: attemptID, citationID: citation.id,
                            sessionID: sessionID, exercise: exercise)
                    } label: {
                        Label(citation.title, systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .sheet(item: $selectedCitation) { route in
            NFHistoryCitationView(route: route)
        }
    }
}

@MainActor
extension AppStore {
    func historyCitationPresentation(route: NFCommittedCitationRoute) -> NFHistoryCitationPresentation {
        historyCitationPresentation(attemptID: route.attemptID, citationID: route.citationID,
            expectedSessionID: route.sessionID, expectedExerciseDigest: route.exerciseDigest)
    }

    func historyCitationPresentation(attemptID: UUID, citationID: String,
                                     expectedSessionID: UUID? = nil,
                                     expectedExerciseDigest: String? = nil) -> NFHistoryCitationPresentation {
        guard let attempt = attempts.first(where: { $0.id == attemptID }) else {
            return NFHistoryCitationPolicy.resolve(exercise: nil, citationID: citationID,
                documents: [], chunks: [], isProtected: false)
        }
        let protected = historyPresentation(for: .init(attempt: attempt)).source == .protectedAssessment
        guard !protected else {
            return NFHistoryCitationPolicy.resolve(exercise: nil, citationID: citationID,
                documents: [], chunks: [], isProtected: true)
        }
        let exercise = exerciseSnapshot(for: attemptID)
        // Deletion and later import may legitimately reuse an attempt UUID.
        // A retained live route must not reattach to that different contract.
        // Protection above remains first, before identity or title inspection.
        guard expectedSessionID == nil || attempt.sessionID == expectedSessionID,
              expectedExerciseDigest == nil || exercise.flatMap({ try? NFLocalItemCheckpoint.digest($0) }) == expectedExerciseDigest else {
            return NFHistoryCitationPolicy.resolve(exercise: nil, citationID: citationID,
                documents: [], chunks: [], isProtected: false)
        }
        let citation = exercise?.citations.first { $0.id == citationID }
        let documentID = citation.flatMap { UUID(uuidString: $0.documentID) }
        return NFHistoryCitationPolicy.resolve(exercise: exercise, citationID: citationID,
            documents: documents.filter { $0.id == documentID }.map { .init(id: $0.id, extractionVersion: $0.extractionVersion) },
            chunks: sourceChunks.filter { $0.id == citation?.sourceChunkID && $0.documentID == documentID }.map(\.snapshot),
            isProtected: false)
    }
}

struct NFHistoryCitationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let attemptID: UUID
    let citationID: String
    let expectedSessionID: UUID?
    let expectedExerciseDigest: String?

    private init(attemptID: UUID, citationID: String, expectedSessionID: UUID?,
                 expectedExerciseDigest: String?) {
        self.attemptID = attemptID; self.citationID = citationID
        self.expectedSessionID = expectedSessionID; self.expectedExerciseDigest = expectedExerciseDigest
    }

    init(route: NFCommittedCitationRoute) {
        self.init(attemptID: route.attemptID, citationID: route.citationID,
            expectedSessionID: route.sessionID, expectedExerciseDigest: route.exerciseDigest)
    }

    private var presentation: NFHistoryCitationPresentation {
        store.historyCitationPresentation(attemptID: attemptID, citationID: citationID,
            expectedSessionID: expectedSessionID, expectedExerciseDigest: expectedExerciseDigest)
    }

    var body: some View {
        let value = presentation
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let citation = value.citation {
                        Text(citation.title).font(.title2.bold())
                        location(citation.locator)
                        if let version = value.matchedExtractionVersion {
                            LabeledContent("Available extraction version", value: String(version))
                        }
                        if let excerpt = value.currentExcerpt {
                            Text("Source excerpt matching this saved citation").font(.headline)
                            Text(excerpt).textSelection(.enabled)
                        } else {
                            unavailable(value.availability)
                            if let saved = value.savedExcerpt {
                                Text("Saved source excerpt").font(.headline)
                                Text(saved).textSelection(.enabled)
                            }
                        }
                        Text("The original source version number was not saved.")
                            .font(.footnote).foregroundStyle(.secondary)
                        DisclosureGroup("Source identity") {
                            LabeledContent("Document", value: citation.documentID)
                            if let chunk = citation.sourceChunkID { LabeledContent("Source excerpt", value: chunk) }
                            if let digest = citation.excerptDigest { LabeledContent("Saved content revision", value: digest) }
                        }.font(.footnote).textSelection(.enabled)
                    } else {
                        unavailable(value.availability)
                    }
                }.padding().frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
            }
            .navigationTitle("Source citation")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.nfDesktopPresentationFrame(minWidth: 340, minHeight: 360)
        #if os(macOS)
        .onExitCommand { dismiss() }
        #endif
    }

    @ViewBuilder private func unavailable(_ availability: NFHistoryCitationPresentation.Availability) -> some View {
        switch availability {
        case .available: EmptyView()
        case .changedSource:
            Text("This source has changed. Its current text cannot replace the saved citation.")
        case .missingSource:
            Text("The original source excerpt is unavailable. It may have been deleted or reprocessed.")
        case .unverifiedRevision:
            Text("The saved source revision cannot be verified, so the current source is unavailable for this citation.")
        case .unavailableCitation:
            Text("This saved citation is unavailable. Return to the saved answer to review the retained context.")
        case .protectedContent:
            Text("Exact source context is unavailable for this protected check. Practice this skill with a fresh question.")
        }
    }

    @ViewBuilder private func location(_ locator: NFExerciseCitationLocator) -> some View {
        switch locator {
        case .page(let page): LabeledContent("Page", value: String(page))
        case .pages(let start, let end): LabeledContent("Pages", value: "\(start)–\(end)")
        case .section(let section): LabeledContent("Section", value: section)
        case .lines(let start, let end): LabeledContent("Lines", value: "\(start)–\(end)")
        case .chunk: Text("Source excerpt")
        case .equation(let equation): LabeledContent("Equation", value: equation)
        case .figure(let figure): LabeledContent("Figure", value: figure)
        }
    }
}

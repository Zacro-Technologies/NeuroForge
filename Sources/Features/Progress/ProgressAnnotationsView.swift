import SwiftUI

struct ProgressAnnotationsCard: View {
    @Environment(AppStore.self) private var store
    @State private var editorDraft: NFProgressAnnotationDraft?
    @State private var annotationPendingDeletion: ProgressAnnotationRecord?
    @State private var errorMessage: String?
    @State private var showsAllAnnotations = false
    @State private var annotationSearchText = ""
    @State private var annotationVisibleLimit = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                NFSectionHeader(
                    "Private context annotations",
                    subtitle: "Optionally mark a date range such as exams, travel, or a schedule change. No health detail or category is required."
                )
                Spacer(minLength: 12)
                Button {
                    editorDraft = NFProgressAnnotationDraft()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if store.progressAnnotations.isEmpty {
                Text("No private date-range annotations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if showsAllAnnotations {
                    TextField("Search annotations", text: $annotationSearchText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityHint("Searches annotation notes and their formatted date ranges")
                }

                if visibleAnnotations.isEmpty {
                    ContentUnavailableView.search(text: annotationSearchText)
                        .frame(minHeight: 120)
                }

                ForEach(visibleAnnotations) { annotation in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(NFTheme.indigoForeground)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(annotationRange(annotation))
                                .font(.subheadline.weight(.semibold))
                            Group {
                                if annotation.note.isEmpty {
                                    Text("Private context (no note)")
                                } else {
                                    Text(verbatim: annotation.note)
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            Label(
                                annotation.includeInExport ? "Included when you prepare an export" : "Excluded from every export",
                                systemImage: annotation.includeInExport ? "square.and.arrow.up" : "lock.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(annotation.includeInExport ? NFTheme.cyanForeground : NFTheme.mintForeground)
                        }
                        Spacer(minLength: 8)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                annotationEditButton(annotation)
                                annotationExportButton(annotation)
                                annotationDeleteButton(annotation)
                            }
                            VStack(spacing: 8) {
                                annotationEditButton(annotation)
                                annotationExportButton(annotation)
                                annotationDeleteButton(annotation)
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityAction(named: Text("Edit annotation")) {
                        editorDraft = NFProgressAnnotationDraft(annotation: annotation)
                    }
                    .accessibilityAction(named: Text("Delete annotation")) {
                        annotationPendingDeletion = annotation
                    }
                    if annotation.id != visibleAnnotations.last?.id { Divider() }
                }

                if store.progressAnnotations.count > 6 {
                    Button {
                        showsAllAnnotations.toggle()
                        if !showsAllAnnotations {
                            annotationSearchText = ""
                            annotationVisibleLimit = 20
                        }
                    } label: {
                        Label(
                            showsAllAnnotations ? "Show recent annotations" : "See all annotations",
                            systemImage: showsAllAnnotations ? "chevron.up" : "clock.arrow.circlepath"
                        )
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(
                        showsAllAnnotations
                            ? "Shows the six most recent annotations"
                            : "Shows every retained annotation"
                    )
                }

                if showsAllAnnotations, filteredAnnotations.count > annotationVisibleLimit {
                    Button("Load more annotations") {
                        annotationVisibleLimit += 20
                    }
                    .buttonStyle(.bordered)
                    .accessibilityValue(NFAppLocalization.localized(
                        "\(NFAppLocalization.formattedAnnotationCount(visibleAnnotations.count)) of \(NFAppLocalization.formattedAnnotationCount(filteredAnnotations.count)) shown",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Annotation-history paging status with localized visible and total annotation counts."
                    ))
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(NFTheme.roseForeground)
            }

            Text("Annotations remain on this device until you delete them. They never alter scores, plans, consistency, or claims, and each new annotation is excluded from export unless you explicitly include it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .nfCard()
        .sheet(item: $editorDraft) { draft in
            ProgressAnnotationEditor(draft: draft) { updated in
                try store.saveProgressAnnotation(
                    id: updated.persistedID,
                    startDate: updated.startDate,
                    endDate: updated.endDate,
                    note: updated.note,
                    includeInExport: updated.includeInExport
                )
                errorMessage = nil
            }
        }
        .alert("Delete this private annotation?", isPresented: Binding(
            get: { annotationPendingDeletion != nil },
            set: { if !$0 { annotationPendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) { annotationPendingDeletion = nil }
            Button("Delete", role: .destructive) {
                guard let annotationPendingDeletion else { return }
                do {
                    try store.deleteProgressAnnotation(annotationPendingDeletion)
                    errorMessage = nil
                } catch {
                    errorMessage = NFAppLocalization.localized(
                        "The annotation was not deleted. Try again."
                    )
                }
                self.annotationPendingDeletion = nil
            }
        } message: {
            Text("This removes only the private note and date range. Training history is unchanged.")
        }
    }

    private func annotationRange(_ annotation: ProgressAnnotationRecord) -> String {
        var calendar = Calendar.current
        calendar.locale = NFAppLocalization.preferredLocale
        if calendar.isDate(annotation.startDate, inSameDayAs: annotation.endDate) {
            return annotationDateFormatter.string(from: annotation.startDate)
        }
        return "\(annotationDateFormatter.string(from: annotation.startDate)) – \(annotationDateFormatter.string(from: annotation.endDate))"
    }

    private var visibleAnnotations: [ProgressAnnotationRecord] {
        showsAllAnnotations
            ? Array(filteredAnnotations.prefix(annotationVisibleLimit))
            : Array(store.progressAnnotations.prefix(6))
    }

    private var filteredAnnotations: [ProgressAnnotationRecord] {
        let query = annotationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.progressAnnotations }
        return store.progressAnnotations.filter {
            $0.note.localizedCaseInsensitiveContains(query)
                || annotationRange($0).localizedCaseInsensitiveContains(query)
        }
    }

    private var annotationDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = NFAppLocalization.preferredLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    private func annotationEditButton(_ annotation: ProgressAnnotationRecord) -> some View {
        Button {
            editorDraft = NFProgressAnnotationDraft(annotation: annotation)
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Edit annotation starting \(annotationDateFormatter.string(from: annotation.startDate))")
    }

    private func annotationExportButton(_ annotation: ProgressAnnotationRecord) -> some View {
        ShareLink(item: annotationExportText(annotation)) {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Export annotation starting \(annotationDateFormatter.string(from: annotation.startDate))")
    }

    private func annotationDeleteButton(_ annotation: ProgressAnnotationRecord) -> some View {
        Button(role: .destructive) {
            annotationPendingDeletion = annotation
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Delete annotation starting \(annotationDateFormatter.string(from: annotation.startDate))")
    }

    private func annotationExportText(_ annotation: ProgressAnnotationRecord) -> String {
        [
            NFAppLocalization.localized("NeuroForge progress annotation", locale: NFAppLocalization.preferredLocale, comment: "Title in a user-exported individual progress annotation."),
            NFAppLocalization.localized("Date range: \(annotationRange(annotation))", locale: NFAppLocalization.preferredLocale, comment: "Date range in a user-exported individual progress annotation."),
            annotation.note.isEmpty
                ? NFAppLocalization.localized("Note: None", locale: NFAppLocalization.preferredLocale, comment: "Empty note in a user-exported individual progress annotation.")
                : NFAppLocalization.localized("Note: \(annotation.note)", locale: NFAppLocalization.preferredLocale, comment: "Optional note in a user-exported individual progress annotation.")
        ].joined(separator: "\n")
    }
}

struct NFProgressAnnotationDraft: Identifiable, Equatable {
    let id = UUID()
    let persistedID: UUID?
    var startDate: Date
    var endDate: Date
    var note: String
    var includeInExport: Bool

    init(
        persistedID: UUID? = nil,
        startDate: Date = Date(),
        endDate: Date = Date(),
        note: String = "",
        includeInExport: Bool = false
    ) {
        self.persistedID = persistedID
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
        self.includeInExport = includeInExport
    }

    init(annotation: ProgressAnnotationRecord) {
        persistedID = annotation.id
        startDate = annotation.startDate
        endDate = annotation.endDate
        note = annotation.note
        includeInExport = annotation.includeInExport
    }
}

private struct ProgressAnnotationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NFProgressAnnotationDraft
    @State private var saveError: String?
    @State private var isShowingDiscardConfirmation = false
    @AccessibilityFocusState private var saveErrorIsFocused: Bool
    private let originalDraft: NFProgressAnnotationDraft
    let onSave: (NFProgressAnnotationDraft) throws -> Void

    init(draft: NFProgressAnnotationDraft, onSave: @escaping (NFProgressAnnotationDraft) throws -> Void) {
        _draft = State(initialValue: draft)
        originalDraft = draft
        self.onSave = onSave
    }

    private var isOverLimit: Bool {
        draft.note.count > NFProgressAnnotationValidation.maximumNoteCharacters
    }

    private var isDirty: Bool {
        draft != originalDraft
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date range") {
                    DatePicker("Start", selection: $draft.startDate, displayedComponents: .date)
                    DatePicker("End", selection: $draft.endDate, in: draft.startDate..., displayedComponents: .date)
                }
                Section("Optional private note") {
                    Text("Note")
                        .font(.subheadline.weight(.semibold))
                    TextEditor(text: $draft.note)
                        .frame(minHeight: 100)
                        .accessibilityLabel("Private annotation note")
                    Text(NFProgressAnnotationValidation.countMessage(for: draft.note))
                        .font(.caption)
                        .foregroundStyle(isOverLimit ? NFTheme.roseForeground : .secondary)
                    Text("You can write general context without naming an illness, diagnosis, or other sensitive detail.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(NFTheme.roseForeground)
                            .accessibilityFocused($saveErrorIsFocused)
                    }
                }
                Section("Export") {
                    Toggle("Include this annotation in exports", isOn: $draft.includeInExport)
                    Text(draft.includeInExport
                         ? "The date range and note will appear in the full archive you deliberately prepare."
                         : "The annotation stays in the private app store and is omitted from every prepared export.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(draft.persistedID == nil ? "Add annotation" : "Edit annotation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            isShowingDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try onSave(draft)
                            dismiss()
                        } catch {
                            saveError = NFAppLocalization.localized(
                                "The annotation was not saved. Your draft is still here; try again."
                            )
                            saveErrorIsFocused = true
                        }
                    }
                    .disabled(isOverLimit)
                }
            }
        }
        .nfDesktopPresentationFrame(minWidth: 380, idealWidth: 560, minHeight: 500, idealHeight: 640)
        .nfGuardsUnsavedEditor(
            isDirty,
            title: NFAppLocalization.localized("Progress annotation", comment: "Dirty-editor name used in the global navigation warning.")
        )
        .alert("Discard this annotation draft?", isPresented: $isShowingDiscardConfirmation) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard", role: .destructive) { dismiss() }
        } message: {
            Text("Your unsaved note, date range, and export choice will be lost.")
        }
    }
}

enum NFProgressAnnotationValidation {
    static let maximumNoteCharacters = ProgressAnnotationRecord.maximumNoteCharacters

    static func countMessage(for note: String) -> String {
        let difference = maximumNoteCharacters - note.count
        if difference >= 0 {
            return NFAppLocalization.formattedCharactersRemaining(difference)
        }
        return NFAppLocalization.formattedCharactersOverLimit(-difference)
    }
}

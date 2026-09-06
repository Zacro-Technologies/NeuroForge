import SwiftUI

struct NFAttemptAnnotationView: View {
    @Environment(AppStore.self) private var store
    let attemptID: UUID
    @State private var note = ""
    @State private var savedNote = ""
    @State private var saveError: String?
    @State private var loaded = false
    @State private var reflectionNote = ""
    @State private var savedReflectionNote = ""
    @State private var reflectionReason: NFErrorReflectionCode?
    @State private var savedReflectionReason: NFErrorReflectionCode?

    private var annotation: NFStudyAnnotation {
        store.privateStudyMetadata.annotations.first { $0.id == attemptID } ?? NFStudyAnnotation(id: attemptID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reason = store.privateStudyMetadataUnavailableReason {
                Text(verbatim: reason).foregroundStyle(.secondary)
            }
            Text("My study notes").font(.headline)
            Text("Notes and bookmarks are saved on this device, separately from your original answer.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button(annotation.bookmarked ? "Remove bookmark" : "Save for later") {
                var update = annotation
                update.bookmarked.toggle()
                update.updatedAt = Date()
                persist(update)
            }.buttonStyle(.bordered)
            TextEditor(text: $note).frame(minHeight: 100)
                .accessibilityLabel("Study note")
            Button("Save note") {
                var update = annotation
                update.note = note
                update.updatedAt = Date()
                if persist(update) { savedNote = note }
            }.buttonStyle(.bordered).disabled(note == savedNote)
            if let original = store.attemptReflections.first(where: { $0.attemptID == attemptID }) {
                Divider()
                Text("My reflection").font(.headline)
                Text("You can revise your reflection. Your original answer, score and first reflection stay saved.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let reason = store.reflectionUnavailableReason(for: attemptID) {
                    Text(verbatim: reason).foregroundStyle(.secondary)
                }
                DisclosureGroup("First reflection") {
                    Text(original.selectedErrorCode?.title ?? NFAppLocalization.localizedCatalogValue("Not sure yet", locale: NFAppLocalization.preferredLocale))
                    if !original.note.isEmpty { Text(original.note) }
                }
                Picker("My reason", selection: $reflectionReason) {
                    Text("Not sure yet").tag(NFErrorReflectionCode?.none)
                    ForEach(NFErrorReflectionCode.allCases) { reason in
                        Text(reason.title).tag(Optional(reason))
                    }
                }
                .disabled(store.reflectionUnavailableReason(for: attemptID) != nil)
                TextField("Reflection note", text: $reflectionNote, axis: .vertical)
                    .lineLimit(3...8)
                    .disabled(store.reflectionUnavailableReason(for: attemptID) != nil)
                Button("Save reflection") {
                    do {
                        try store.saveAttemptReflection(attemptID: attemptID,
                            deterministicErrorCode: original.deterministicErrorCode,
                            selectedErrorCode: reflectionReason, trigger: original.trigger, note: reflectionNote)
                        savedReflectionNote = reflectionNote
                        savedReflectionReason = reflectionReason
                        saveError = nil
                    } catch { saveError = error.localizedDescription }
                }.buttonStyle(.bordered)
                    .disabled((reflectionNote == savedReflectionNote && reflectionReason == savedReflectionReason)
                        || reflectionNote.trimmingCharacters(in: .whitespacesAndNewlines).count > AttemptReflectionRecord.maximumNoteCharacters
                        || store.reflectionUnavailableReason(for: attemptID) != nil)
            }
            if let saveError { Text(saveError).foregroundStyle(.red) }
        }.nfCard()
        .disabled(store.privateStudyMetadataUnavailableReason != nil)
        .onAppear {
            guard !loaded else { return }
            note = annotation.note
            savedNote = note
            if let reflection = store.currentReflection(for: attemptID) {
                reflectionNote = reflection.note
                savedReflectionNote = reflection.note
                reflectionReason = reflection.selectedErrorCodeRaw.flatMap(NFErrorReflectionCode.init(rawValue:))
                savedReflectionReason = reflectionReason
            }
            loaded = true
        }
        .nfGuardsUnsavedEditor(note != savedNote || reflectionNote != savedReflectionNote || reflectionReason != savedReflectionReason,
            title: "Study note", onDiscard: {
                note = savedNote
                reflectionNote = savedReflectionNote
                reflectionReason = savedReflectionReason
            })
    }

    @discardableResult
    private func persist(_ update: NFStudyAnnotation) -> Bool {
        do { try store.saveStudyAnnotation(update); saveError = nil; return true }
        catch { saveError = NFAppLocalization.localizedCatalogValue("Your note could not be saved. Keep it open and try again.", locale: NFAppLocalization.preferredLocale); return false }
    }
}

import SwiftUI

struct NFStudyResourcesView: View {
    @Environment(AppStore.self) private var store
    @State private var editingCollection: NFStudyCollection?
    @State private var selectedSet: NFLocalSavedStudySet?
    @State private var startsNewSession = false
    @State private var removingSet: NFLocalSavedStudySet?
    @State private var errorMessage: String?

    private var savedSets: [NFLocalSavedStudySet] {
        (store.localSessions.archive.savedSets ?? []).sorted { $0.savedAt > $1.savedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Saved on this device").font(.title.bold())
                Text("Saved sets and collections remain available until you remove them. Include them in a backup to move them to another device.")
                    .foregroundStyle(.secondary)
                if savedSets.isEmpty {
                    ContentUnavailableView("No saved sets yet", systemImage: "bookmark", description: Text("Choose Save set after creating questions. You can practice without creating a collection."))
                }
                ForEach(savedSets) { set in setRow(set) }
                HStack {
                    Text("Collections").font(.title2.bold())
                    Spacer()
                    Button("New collection") { editingCollection = NFStudyCollection(title: "") }
                        .disabled(store.privateStudyMetadataUnavailableReason != nil)
                }
                if let reason = store.privateStudyMetadataUnavailableReason {
                    Text(verbatim: reason).foregroundStyle(.secondary)
                }
                ForEach(store.privateStudyMetadata.collections) { collection in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(collection.title).font(.headline)
                        if !collection.description.isEmpty { Text(collection.description).foregroundStyle(.secondary) }
                        Text("\(collection.sourceIDs.count) sources · \(collection.savedSetIDs.count) saved sets")
                        collectionActivity(collection)
                        Button("Open collection") { editingCollection = collection }.buttonStyle(.bordered)
                    }.nfCard()
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .navigationTitle("Saved and collections")
        .sheet(item: $editingCollection) { collection in
            NFStudyCollectionEditor(collection: collection)
        }
        .sheet(item: $selectedSet) { set in
            if let request = request(for: set) {
                AIGeneratedPracticeView(result: set.result, request: request, restoresProgress: false, savedDraft: startsNewSession ? nil : store.generatedPracticeDraft(for: set.id))
            }
        }
        .confirmationDialog("Remove saved copy?", isPresented: Binding(get: { removingSet != nil }, set: { if !$0 { removingSet = nil } }), titleVisibility: .visible) {
            Button("Remove saved copy", role: .destructive) {
                guard let set = removingSet else { return }
                do { try store.unsaveGenerationSet(set.id) }
                catch { errorMessage = error.localizedDescription }
                removingSet = nil
            }
            Button("Cancel", role: .cancel) { removingSet = nil }
        } message: {
            Text("This stops permanent retention of the set. Any temporary copy follows its original expiry. Unfinished sessions, saved answers and original sources remain available.")
        }
    }

    private func setRow(_ set: NFLocalSavedStudySet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title(for: set)).font(.headline)
            Text(NFAppLocalization.formattedQuestionCount(set.result.questions.count)).foregroundStyle(.secondary)
            if let reason = set.unavailableReason {
                Text(verbatim: NFAppLocalization.localizedCatalogValue(reason, locale: NFAppLocalization.preferredLocale))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(store.generatedPracticeDraft(for: set.id) == nil ? "Start practice" : "Continue session") { startsNewSession = false; selectedSet = set }
                    .buttonStyle(.borderedProminent).disabled(request(for: set) == nil)
                Menu("More") {
                    if store.generatedPracticeDraft(for: set.id) != nil {
                        Button("Start a new session") { startsNewSession = true; selectedSet = set }
                            .disabled(request(for: set) == nil)
                    }
                    if let data = try? JSONEncoder().encode(set.result), let json = String(data: data, encoding: .utf8) {
                        ShareLink("Export available questions", item: json)
                    }
                    Button("Remove saved copy", role: .destructive) { removingSet = set }
                }.buttonStyle(.bordered)
            }
        }.nfCard()
    }

    @ViewBuilder private func collectionActivity(_ collection: NFStudyCollection) -> some View {
        let attempts = store.attempts.filter { $0.generationID.map(collection.savedSetIDs.contains) == true }
        if let last = attempts.map(\.submittedAt).max() {
            LabeledContent("Last practiced", value: NFAppLocalization.formattedDate(last, date: .abbreviated, time: .omitted))
        }
        Text("Review timing follows each source or practice item.").font(.footnote).foregroundStyle(.secondary)
    }

    private func title(for set: NFLocalSavedStudySet) -> String {
        let topic = store.aiGenerations.first { $0.id == set.id }?.topic ?? ""
        return topic.isEmpty ? (set.result.questions.first?.lab.title ?? NFAppLocalization.localizedCatalogValue("Saved question set", locale: NFAppLocalization.preferredLocale)) : topic
    }

    private func request(for set: NFLocalSavedStudySet) -> NFAuthoringRequest? {
        guard set.unavailableReason == nil else { return nil }
        if let draft = store.generatedPracticeDraft(for: set.id) { return draft.request }
        guard let first = set.result.questions.first else { return nil }
        return NFAuthoringRequest(id: set.id, capability: .contextualize, lab: first.lab,
            field: first.authoritativeExercise.sourceContext.primaryField,
            customTopic: title(for: set), learningObjective: "", style: first.style,
            difficulty: first.difficulty, count: set.result.questions.count,
            localeIdentifier: first.authoritativeExercise.localeIdentifier,
            seed: first.authoritativeExercise.seed, aiMode: .disabled, allowsShortcutAuthoring: false)
    }
}

private struct NFStudyCollectionEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var collection: NFStudyCollection
    @State private var saveError: String?
    @State private var confirmsDeletion = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Collection details") {
                    TextField("Title", text: $collection.title)
                    TextField("Description", text: $collection.description, axis: .vertical)
                    Text("Membership changes do not change the underlying sources, questions or answer history.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Included sources") {
                    ForEach(store.documents) { document in
                        Toggle(document.filename, isOn: membership(document.id, in: $collection.sourceIDs))
                    }
                }
                Section("Included saved sets") {
                    ForEach(store.localSessions.archive.savedSets ?? []) { set in
                        Toggle(setTitle(set), isOn: membership(set.id, in: $collection.savedSetIDs))
                    }
                }
                Section("Practice") {
                    ForEach(store.documents.filter { collection.sourceIDs.contains($0.id) }) { document in
                        NavigationLink(document.filename) { DocumentDetailView(document: document) }
                    }
                    if !collection.savedSetIDs.isEmpty {
                        NavigationLink("Practice saved sets") { NFStudyResourcesView() }
                    }
                }
                Section {
                    if let data = try? JSONEncoder().encode(collection), let json = String(data: data, encoding: .utf8) {
                        ShareLink("Export collection list", item: json)
                    }
                    Button("Delete collection", role: .destructive) { confirmsDeletion = true }
                }
                if let saveError { Text(saveError).foregroundStyle(.red) }
            }
            .navigationTitle("Collection")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try store.saveStudyCollection(collection); dismiss() }
                        catch { saveError = error.localizedDescription }
                    }.disabled(collection.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .confirmationDialog("Delete collection?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("Delete collection", role: .destructive) {
                    var metadata = store.privateStudyMetadata
                    metadata.collections.removeAll { $0.id == collection.id }
                    do { try store.savePrivateStudyMetadata(metadata); dismiss() }
                    catch { saveError = error.localizedDescription }
                }
            } message: { Text("Only this organization is removed. Sources, saved sets, unfinished sessions and answer history are kept.") }
        }
    }

    private func membership(_ id: UUID, in values: Binding<Set<UUID>>) -> Binding<Bool> {
        Binding(get: { values.wrappedValue.contains(id) }, set: { included in
            if included { values.wrappedValue.insert(id) } else { values.wrappedValue.remove(id) }
        })
    }

    private func setTitle(_ set: NFLocalSavedStudySet) -> String {
        store.aiGenerations.first { $0.id == set.id }?.topic ?? set.result.questions.first?.lab.title ?? ""
    }
}

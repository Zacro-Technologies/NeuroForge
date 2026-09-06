import SwiftUI

struct NFContinueSessionsCard: View {
    @Environment(AppStore.self) private var store
    var showsSessionFilters = false
    @State private var selectedGeneratedDraft: NFGeneratedPracticeDraft?
    @State private var sessionFilter = SessionFilter.all
    @State private var additionalSessionLimit = 9
    @State private var generatedSessionLimit = 10

    private enum SessionFilter: String, CaseIterable, Identifiable {
        case all, focused, review
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .all: "All sessions"
            case .focused: "Focused practice"
            case .review: "Review"
            }
        }
    }

    private func filteredSessions(_ sessions: [NFLocalSessionEnvelope]) -> [NFLocalSessionEnvelope] {
        guard showsSessionFilters else { return sessions }
        return sessions.filter { session in
            switch sessionFilter {
            case .all: true
            case .focused: session.request.source == .focused && session.request.retentionItemIDs.isEmpty
            case .review: !session.request.retentionItemIDs.isEmpty || session.request.source == .reassessment
            }
        }
    }

    var body: some View {
        let allSessions = store.resumableSessions
        let sessions = filteredSessions(allSessions)
        let generatedDrafts = store.generatedPracticeDrafts
        VStack(alignment: .leading, spacing: 16) {
        if !allSessions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if showsSessionFilters {
                    Picker("Saved sessions", selection: $sessionFilter) {
                        ForEach(SessionFilter.allCases) { filter in Text(filter.title).tag(filter) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("saved-session-filter")
                }
                if let recent = sessions.first {
                Label("Saved on this device", systemImage: "internaldrive")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(recent.request.topic ?? recent.request.lab.title).font(.title2.bold())
                Text("Question \(min(recent.index + 1, recent.itemCount)) of \(recent.itemCount)")
                    .font(.subheadline)
                Button("Continue session") { _ = store.resumeSession(recent.id) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("continue-session")
                if sessions.count > 1 {
                    DisclosureGroup("Other saved sessions (\(sessions.count - 1))") {
                        ForEach(Array(sessions.dropFirst().prefix(additionalSessionLimit))) { session in
                            Button(session.request.topic ?? session.request.lab.title) {
                                _ = store.resumeSession(session.id)
                            }.frame(minHeight: 44)
                        }
                        if sessions.count - 1 > additionalSessionLimit {
                            Button("Show more") { additionalSessionLimit += 10 }
                                .frame(minHeight: 44)
                        }
                    }
                }
                } else {
                    Text("No saved sessions match this filter.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .nfCard()
        }
        ForEach(Array(generatedDrafts.prefix(generatedSessionLimit))) { draft in
            VStack(alignment: .leading, spacing: 12) {
                Text(draft.request.customTopic.isEmpty ? draft.request.lab.title : draft.request.customTopic).font(.headline)
                Text("Question \(draft.index + 1) of \(draft.result.questions.count)").font(.subheadline)
                if draft.ownerDeviceID == store.localSessions.ownerDeviceID {
                    Button("Continue session") { selectedGeneratedDraft = draft }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Review recovered work") { selectedGeneratedDraft = draft }
                        .buttonStyle(.bordered)
                }
            }.nfCard()
        }
        if generatedDrafts.count > generatedSessionLimit {
            Button("Show more") { generatedSessionLimit += 10 }
                .frame(minHeight: 44)
        }
        }
        .onChange(of: sessionFilter) { _, _ in additionalSessionLimit = 9 }
        .sheet(item: $selectedGeneratedDraft) { draft in
            AIGeneratedPracticeView(result: draft.result, request: draft.request, savedDraft: draft).environment(store)
        }
    }
}

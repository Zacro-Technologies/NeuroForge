import SwiftUI

/// One claim at a time keeps the evidence list short. Drag and accessible
/// selection write exactly the same mapping; undo never touches a saved attempt.
struct NFClaimEvidenceEditor: View {
    let schema: NFClaimEvidenceResponseSchema
    @Binding var selection: [String: Set<String>]
    var onInput: () -> Void = {}
    @State private var selectedClaimID: String?
    @State private var previousSelection: [String: Set<String>]?

    private var currentClaim: NFClaimOption? {
        schema.claims.first { $0.id == selectedClaimID } ?? schema.claims.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Claim", selection: Binding(
                get: { currentClaim?.id ?? "" }, set: { selectedClaimID = $0 }
            )) {
                ForEach(schema.claims) { claim in Text(claim.text).tag(claim.id) }
            }
            .pickerStyle(.menu)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            if let claim = currentClaim {
                Text(claim.text).font(.headline)
                Text("Choose evidence for this claim.").font(.subheadline).foregroundStyle(.secondary)
                ForEach(schema.evidence) { evidence in
                    let selected = selection[claim.id, default: []].contains(evidence.id)
                    Button { toggle(evidence.id, for: claim.id) } label: {
                        Label(evidence.text, systemImage: selected ? "checkmark.square.fill" : "square")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(8)
                            .background(selected ? NFTheme.indigo.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .draggable(evidence.id)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { toggle(evidence.id, for: claim.id) }
                    .nfSelectionAccessibility(selected)
                    .accessibilityLabel("\(claim.text): \(evidence.text)")
                }
                HStack {
                    Button("Clear current claim") {
                        mutate { selection[claim.id] = [] }
                    }.disabled(selection[claim.id, default: []].isEmpty)
                    Button("Undo") {
                        guard let previousSelection else { return }
                        let current = selection
                        selection = previousSelection
                        self.previousSelection = current
                        onInput()
                    }.disabled(previousSelection == nil)
                }.buttonStyle(.bordered)
            }
            DisclosureGroup("Current connections") {
                ForEach(schema.claims) { claim in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(claim.text).font(.headline)
                        ForEach(schema.evidence.filter { selection[claim.id, default: []].contains($0.id) }) { evidence in
                            Label(evidence.text, systemImage: "link")
                        }
                        if selection[claim.id, default: []].isEmpty { Text("No evidence selected").foregroundStyle(.secondary) }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    .dropDestination(for: String.self) { values, _ in
                        let valid = values.filter { id in schema.evidence.contains { $0.id == id } }
                        guard !valid.isEmpty else { return false }
                        mutate { selection[claim.id, default: []].formUnion(valid) }
                        return true
                    }
                }
            }
        }.nfCard(cornerRadius: 16, padding: 16)
    }

    private func toggle(_ evidenceID: String, for claimID: String) {
        mutate {
            if selection[claimID, default: []].contains(evidenceID) { selection[claimID, default: []].remove(evidenceID) }
            else { selection[claimID, default: []].insert(evidenceID) }
        }
    }

    private func mutate(_ action: () -> Void) {
        previousSelection = selection
        action()
        onInput()
    }
}


/// Both input routes use the same scoped dictionary. The binding refuses late
/// drops or undo after stage one has been durably frozen.
struct NFScienceStudyEditor: View {
    let exercise: NFExercise
    let draft: NFScienceStudyDraft
    let selection: [String: Set<String>]
    let canEdit: Bool
    let updateSelection: ([String: Set<String>]) -> Void
    let onInput: () -> Void
    @AccessibilityFocusState private var stageHeadingFocused: Bool

    var body: some View {
        if let study = NFScienceStudyContract.make(exercise: exercise) {
            VStack(alignment: .leading, spacing: 16) {
                Text(study.title).font(.headline)
                Text(draft.awaitsEvidence ? LocalizedStringKey("Study stage 1 of 2 · Connect the evidence") : LocalizedStringKey("Study stage 2 of 2 · Choose the experiment"))
                    .font(.title3.bold()).accessibilityHeading(.h2).accessibilityFocused($stageHeadingFocused)
                    .accessibilityIdentifier("science-study-stage")
                if draft.awaitsEvidence {
                    NFClaimEvidenceEditor(schema: study.evidenceSchema,
                        selection: Binding(get: { selection.filter { id, _ in study.evidenceClaims.contains { $0.id == id } } },
                            set: { value in
                                guard canEdit, draft.awaitsEvidence else { return }
                                let ids = Set(study.evidenceClaims.map(\.id)), evidenceIDs = Set(study.observations.map(\.id))
                                guard Set(value.keys).isSubset(of: ids), value.values.allSatisfy({ $0.isSubset(of: evidenceIDs) }) else { return }
                                var updated = selection
                                for id in ids { updated[id] = value[id, default: []] }
                                updateSelection(updated)
                            }), onInput: onInput)
                        .disabled(!canEdit)
                    Text("Save these connections to open the experimental choice. The mapping remains part of your final answer.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    NFScienceSavedEvidenceView(exercise: exercise, draft: draft)
                    Text(study.experimentClaim.text).font(.headline)
                    Text("Choose one experiment. Consider both assignment and measurement.").font(.subheadline)
                    ForEach(study.experiments) { option in
                        let selected = selection[study.experimentClaim.id, default: []].contains(option.id)
                        Button {
                            guard canEdit else { return }
                            var updated = selection; updated[study.experimentClaim.id] = [option.id]
                            updateSelection(updated); onInput()
                        } label: {
                            Label(option.text, systemImage: selected ? "largecircle.fill.circle" : "circle")
                                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).padding(10)
                        }.buttonStyle(.bordered).disabled(!canEdit).nfSelectionAccessibility(selected)
                    }
                }
            }
            .task(id: draft.awaitsEvidence) {
                guard !draft.awaitsEvidence else { return }
                await Task.yield(); guard !Task.isCancelled else { return }; stageHeadingFocused = true
            }
        }
    }
}

struct NFScienceSavedEvidenceView: View {
    let exercise: NFExercise
    let draft: NFScienceStudyDraft
    var body: some View {
        if let first = draft.firstEvidence, let study = NFScienceStudyContract.make(exercise: exercise) {
            DisclosureGroup("Evidence saved before choosing the experiment") {
                ForEach(study.evidenceClaims) { claim in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(claim.text).font(.headline)
                        let selected = Set(first.pairs.first { $0.claimID == claim.id }?.evidenceIDs ?? [])
                        ForEach(study.observations.filter { selected.contains($0.id) }) { option in
                            Label(option.text, systemImage: "link").textSelection(.enabled)
                        }
                    }.padding(.vertical, 6)
                }
            }.accessibilityIdentifier("science-saved-evidence")
        }
    }
}

struct NFScienceStudyFeedbackView: View {
    let exercise: NFExercise
    let response: NFExerciseResponse
    var body: some View {
        if let study = NFScienceStudyContract.make(exercise: exercise), case let .claimEvidence(submission) = response,
           let selectedID = submission.pairs.first(where: { $0.claimID == study.experimentClaim.id })?.evidenceIDs.first,
           let selected = study.experiments.first(where: { $0.id == selectedID }) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your follow-up experiment").font(.headline)
                Text(selected.text)
                Text(selected.explanation).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("If the workshop has an effect").font(.subheadline.bold())
                    Text(selected.interventionPrediction)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("If the original contrast has another explanation").font(.subheadline.bold())
                    Text(selected.baselinePrediction)
                }
            }.nfCard().accessibilityIdentifier("science-experiment-feedback")
        }
    }
}


struct NFTransferRelationshipEditor: View {
    let exercise: NFExercise
    let draft: NFTransferRelationshipDraft
    let response: NFExerciseResponse
    let canEdit: Bool
    let choose: (String?) -> Void
    let enterTotal: (String) -> Void
    let onInput: () -> Void
    let onSubmit: () -> Void
    @State private var previousChoice: String?
    @State private var hasUndo = false
    @FocusState private var totalFocused: Bool
    @AccessibilityFocusState private var stageFocused: Bool

    var body: some View {
        if let contract = NFTransferRelationshipContract.make(exercise: exercise), case let .logicState(submission) = response {
            VStack(alignment: .leading, spacing: 14) {
                Text(draft.awaitsRelationship ? LocalizedStringKey("Transfer stage 1 of 2 · Choose a relationship") : LocalizedStringKey("Transfer stage 2 of 2 · Solve the target"))
                    .font(.title3.bold()).accessibilityHeading(.h2).accessibilityFocused($stageFocused)
                    .accessibilityIdentifier("transfer-relationship-stage")
                if draft.awaitsRelationship {
                    Text("Choose a relationship that can carry from the source example to the target. Your first choice is saved before the calculation opens.")
                    ForEach(contract.relationships) { option in
                        let selected = submission.violatedRuleID == option.id
                        Button {
                            guard canEdit else { return }
                            previousChoice = submission.violatedRuleID; hasUndo = true
                            choose(option.id); onInput()
                        } label: {
                            Label(option.text, systemImage: selected ? "largecircle.fill.circle" : "circle")
                                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).padding(10)
                        }.buttonStyle(.bordered).disabled(!canEdit).nfSelectionAccessibility(selected)
                    }
                    Button("Clear relationship choice") {
                        guard canEdit else { return }
                        previousChoice = submission.violatedRuleID; hasUndo = true
                        choose(nil); onInput()
                    }.buttonStyle(.bordered).disabled(!canEdit || submission.violatedRuleID == nil)
                    Button("Undo relationship choice") {
                        guard canEdit, hasUndo else { return }
                        choose(previousChoice); hasUndo = false; onInput()
                    }.buttonStyle(.bordered).disabled(!canEdit || !hasUndo)
                } else {
                    NFTransferSavedRelationshipView(exercise: exercise, draft: draft)
                    Text("Calculate the target total using the target's units and conditions. The saved first relationship remains unchanged.")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Target total (\(contract.targetUnit))").font(.headline)
                        TextField("Target total", text: Binding(get: { submission.finalState[NFTransferRelationshipContract.totalKey, default: ""] },
                            set: { guard canEdit else { return }; enterTotal($0) }))
                            .textFieldStyle(.roundedBorder).frame(minHeight: 44).contentShape(Rectangle())
                            .focused($totalFocused).simultaneousGesture(TapGesture().onEnded { if canEdit { totalFocused = true } })
                            .accessibilityLabel("Target total in \(contract.targetUnit)")
                            .accessibilityIdentifier("transfer-target-total")
                            .submitLabel(.done).onSubmit { if canEdit { onSubmit() } }.disabled(!canEdit)
                    }
                }
            }
            .task(id: draft.awaitsRelationship) {
                guard !draft.awaitsRelationship else { return }
                await Task.yield(); guard !Task.isCancelled else { return }; stageFocused = true
            }
        }
    }
}

struct NFTransferSavedRelationshipView: View {
    let exercise: NFExercise
    let draft: NFTransferRelationshipDraft
    var body: some View {
        if let text = draft.recoveryText(exercise: exercise) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Relationship saved before calculating", systemImage: "lock.fill").font(.subheadline.bold())
                Text(text).textSelection(.enabled)
            }.accessibilityIdentifier("transfer-saved-relationship")
        }
    }
}

struct NFTransferRelationshipDebriefView: View {
    let exercise: NFExercise
    var body: some View {
        if let contract = NFTransferRelationshipContract.make(exercise: exercise) {
            VStack(alignment: .leading, spacing: 12) {
                Text("What carried over").font(.headline)
                Text(contract.sharedStructure)
                Text("What changed in the target").font(.headline)
                Text(contract.changedConditions)
            }.nfCard().accessibilityIdentifier("transfer-relationship-debrief")
        }
    }
}

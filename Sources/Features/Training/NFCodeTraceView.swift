import SwiftUI

enum NFCodeTraceAction { case next, previous, reset, selectLine(Int), predict(String, String) }

/// One retained program and one derived state table. It has no answer binding:
/// all inspection changes pass through the owner's durable support boundary.
struct NFCodeTraceView: View {
    let projection: NFCodeTraceProjection
    let draft: NFTraceInspectionDraft?
    let canInspect: Bool
    let predictionIsReady: Bool
    let perform: (NFCodeTraceAction) -> Void
    @AccessibilityFocusState private var stateFocused: Bool
    @FocusState private var focusedPrediction: String?

    private var cursor: Int { draft?.cursor ?? 0 }
    private var values: [String: NFPseudocodeValue] { projection.variables(at: cursor) }
    private var changed: [String] { projection.changedVariables(at: cursor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Program and state").font(.headline).accessibilityHeading(.h2)
            ForEach(Array(projection.lines.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
                    Text(verbatim: text).font(.body.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
                .background(draft?.selectedLine == index + 1 ? NFTheme.indigo.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: NFAppLocalization.localized("Line \(index + 1): \(text)", locale: NFAppLocalization.preferredLocale, comment: "Numbered original program line.")))
            }
            if projection.contract.inputCount > 0 {
                LabeledContent("Original input count", value: "\(projection.contract.inputCount)")
                let visited = cursor > 0 && projection.steps.indices.contains(cursor - 1)
                    ? projection.steps[cursor - 1].visitedInputIndices : []
                LabeledContent("Visited input indices (zero-based)", value: visited.map(String.init).joined(separator: ", "))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey(cursor == 0 ? "Original starting state" : "Revealed state")).font(.subheadline.bold())
                ForEach(values.keys.sorted(), id: \.self) { name in
                    HStack {
                        Text(verbatim: name).font(.body.monospaced())
                        Spacer()
                        Text(verbatim: values[name]?.traceText ?? "").font(.body.monospaced())
                        if changed.contains(name) { Image(systemName: "arrow.triangle.2.circlepath").accessibilityLabel("Changed") }
                    }
                    .padding(8)
                    .background(changed.contains(name) ? NFTheme.indigo.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("code-trace-state")
            .accessibilityFocused($stateFocused)
            if let draft {
                Text("Execution inspection is recorded as support. Your first prediction stays saved.")
                    .font(.footnote).foregroundStyle(.secondary)
                DisclosureGroup("Predict the next state (optional)") {
                    ForEach(projection.contract.initialVariables.keys.sorted(), id: \.self) { name in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: name).font(.subheadline.monospaced())
                            TextField("Next value", text: Binding(get: { draft.nextStatePrediction?[name] ?? "" },
                                set: { perform(.predict(name, $0)) }))
                                .textFieldStyle(.roundedBorder).frame(minHeight: 44)
                                .contentShape(Rectangle())
                                .focused($focusedPrediction, equals: name)
                                .simultaneousGesture(TapGesture().onEnded { focusedPrediction = name })
                                .accessibilityLabel(Text(verbatim: NFAppLocalization.localized("Next value of \(name)", locale: NFAppLocalization.preferredLocale, comment: "Field for a next-state prediction.")))
                                .disabled(!canInspect)
                        }
                    }
                    Text("Use an integer or true/false in every next-state field, or leave them all blank.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(!canInspect)
                Picker("Inspect program line", selection: Binding(get: { draft.selectedLine ?? 1 }, set: { inspect(.selectLine($0)) })) {
                    ForEach(1...projection.lines.count, id: \.self) { line in Text("Line \(line)").tag(line) }
                }
                .pickerStyle(.menu).frame(minHeight: 44).disabled(!canInspect)
                ViewThatFits(in: .horizontal) {
                    HStack { controls }
                    VStack(alignment: .leading) { controls }
                }
                Text("\(draft.revealedStepCount) of \(projection.steps.count) execution steps revealed")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Predict the final state and rule before revealing execution. Inspection is optional and counts as support.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Save prediction and reveal next step") { inspect(.next) }
                    .buttonStyle(.bordered).frame(minHeight: 44)
                    .disabled(!canInspect || !predictionIsReady)
                    .accessibilityIdentifier("code-trace-start")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("code-trace-inspection")
        .onChange(of: cursor) { old, new in
            guard old != new else { return }
            let stateText = values.keys.sorted().map { "\($0): \(values[$0]?.traceText ?? "")" }.joined(separator: ", ")
            let message = NFAppLocalization.localized("State after step \(new): \(stateText)", locale: NFAppLocalization.preferredLocale, comment: "Announces the state after an explicit execution-inspection action.")
            AccessibilityNotification.Announcement(message).post()
            stateFocused = true
        }
    }
    @ViewBuilder private var controls: some View {
        Button("Previous revealed step") { inspect(.previous) }
            .buttonStyle(.bordered).frame(minHeight: 44).disabled(!canInspect || cursor == 0)
        Button("Next step") { inspect(.next) }
            .buttonStyle(.bordered).frame(minHeight: 44).disabled(!canInspect || cursor >= projection.steps.count || draft?.canAdvance(in: projection) == false)
            .accessibilityIdentifier("code-trace-next")
        Button("Reset to original input") { inspect(.reset) }
            .buttonStyle(.bordered).frame(minHeight: 44).disabled(!canInspect || cursor == 0)
            .accessibilityIdentifier("code-trace-reset")
    }
    private func inspect(_ action: NFCodeTraceAction) {
        focusedPrediction = nil
        perform(action)
    }
}

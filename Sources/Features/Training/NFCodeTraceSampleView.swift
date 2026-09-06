import SwiftUI

struct NFCodeTraceSampleView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var revealedCount = 0
    @State private var prediction = ""
    @State private var predictions: [Int: String] = [:]
    @State private var selectedStep = 0

    private let program: [NFPseudocodeStatement] = [
        .assign(name: "x", expression: .value(.integer(3))),
        .assign(name: "y", expression: .add(.variable("x"), .value(.integer(2)))),
        .assign(name: "x", expression: .add(.variable("y"), .value(.integer(1))))
    ]

    private var visibleState: [String: NFPseudocodeValue] {
        (try? NFRestrictedPseudocodeInterpreter.execute(Array(program.prefix(selectedStep))).variables) ?? [:]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Predict, then step through code").font(.title2.bold())
                    Text("This instructional example does not change your skill estimate. Only the displayed assignments run; imported code is never executed.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(program.indices, id: \.self) { line in
                        Text("\(line + 1). \(NFPseudocodeRenderer.render([program[line]], skin: .languageNeutral))")
                            .font(.body.monospaced()).padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(line + 1 == selectedStep ? NFTheme.indigo.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                    Text("Variable state").font(.headline)
                    if visibleState.isEmpty { Text("No variables assigned yet.").foregroundStyle(.secondary) }
                    ForEach(visibleState.keys.sorted(), id: \.self) { name in
                        LabeledContent(name, value: display(visibleState[name]))
                    }
                    if revealedCount < program.count {
                        TextField("Predict the next assigned value", text: $prediction)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("Your answer")
                        Button("Next step") {
                            predictions[revealedCount] = prediction
                            revealedCount += 1
                            selectedStep = revealedCount
                            prediction = ""
                        }.buttonStyle(.borderedProminent).disabled(prediction.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if selectedStep > 0, let prior = predictions[selectedStep - 1] {
                        LabeledContent("Your prediction", value: prior)
                        Text("Compare your prediction with the changed variable above.").font(.subheadline)
                    }
                    HStack {
                        Button("Previous revealed step") { selectedStep = max(0, selectedStep - 1) }.disabled(selectedStep == 0)
                        Button("Latest revealed step") { selectedStep = revealedCount }.disabled(selectedStep == revealedCount)
                    }.buttonStyle(.bordered)
                    Button("Reset view") { selectedStep = 0 }
                    if revealedCount == program.count {
                        Text("Assignments use the current value. Changing x at the end does not change the value already stored in y.").font(.headline)
                    }
                }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .navigationTitle("Code trace sample")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func display(_ value: NFPseudocodeValue?) -> String {
        switch value {
        case .integer(let number): String(number)
        case .boolean(let flag): String(flag)
        case nil: ""
        }
    }
}

import SwiftUI

#if os(iOS)
import PencilKit
import UIKit
#endif

struct NFScratchpadPayload: Codable, Equatable {
    static let prefix = "neuroforge-scratchpad-v1:"

    var notes: String
    var drawingData: Data

    static func decode(_ storedValue: String) -> NFScratchpadPayload {
        guard storedValue.hasPrefix(prefix),
              let data = Data(base64Encoded: String(storedValue.dropFirst(prefix.count))),
              let payload = try? JSONDecoder().decode(NFScratchpadPayload.self, from: data) else {
            return NFScratchpadPayload(notes: storedValue, drawingData: Data())
        }
        return payload
    }

    var storedValue: String {
        guard !notes.isEmpty || !drawingData.isEmpty,
              let data = try? JSONEncoder().encode(self) else { return "" }
        return Self.prefix + data.base64EncodedString()
    }

    var hasNotes: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasDrawing: Bool { !drawingData.isEmpty }
}

struct ScratchpadView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var storedValue: String
    @State private var notes: String

    #if os(iOS)
    private enum Mode: String, CaseIterable, Identifiable {
        case draw = "Draw"
        case notes = "Notes"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .draw: NFAppLocalization.localized("Draw", locale: NFAppLocalization.preferredLocale, comment: "Scratchpad input mode.")
            case .notes: NFAppLocalization.localized("Notes", locale: NFAppLocalization.preferredLocale, comment: "Scratchpad input mode.")
            }
        }
    }

    @State private var drawingData: Data
    @State private var mode: Mode
    #endif

    init(text: Binding<String>) {
        _storedValue = text
        let payload = NFScratchpadPayload.decode(text.wrappedValue)
        _notes = State(initialValue: payload.notes)
        #if os(iOS)
        _drawingData = State(initialValue: payload.drawingData)
        _mode = State(initialValue: UIDevice.current.userInterfaceIdiom == .pad ? .draw : .notes)
        #endif
    }

    var body: some View {
        NavigationStack {
            Group {
                #if os(iOS)
                VStack(spacing: 0) {
                    Picker("Scratchpad input", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 10)

                    if mode == .draw {
                        NFPencilCanvas(drawingData: $drawingData)
                            .accessibilityLabel("Drawing scratchpad")
                            .accessibilityHint("Draw with Apple Pencil or touch. Use the PencilKit palette for pen, eraser, and lasso tools.")
                    } else {
                        notesEditor
                    }
                }
                #else
                notesEditor
                #endif
            }
            .background(Color.windowBackground)
            .navigationTitle("Scratchpad")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { clearCurrentInput() }
                        .disabled(currentInputIsEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        persist()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Scratchpad content is excluded from scoring. It stays with this chapter for resume and completed review, and is removed when its history or all local data is deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
        .nfDesktopPresentationFrame(minWidth: 340, minHeight: 360)
        .onChange(of: notes) { _, _ in persist() }
        #if os(iOS)
        .onChange(of: drawingData) { _, _ in persist() }
        #endif
        .onDisappear { persist() }
    }

    private var notesEditor: some View {
        TextEditor(text: $notes)
            .font(.system(.title3, design: .monospaced))
            .padding()
            .accessibilityLabel("Typed scratchpad notes")
    }

    private func clearCurrentInput() {
        #if os(iOS)
        if mode == .draw {
            drawingData = Data()
        } else {
            notes = ""
        }
        #else
        notes = ""
        #endif
        persist()
    }

    private var currentInputIsEmpty: Bool {
        #if os(iOS)
        mode == .draw ? drawingData.isEmpty : notes.isEmpty
        #else
        notes.isEmpty
        #endif
    }

    private func persist() {
        #if os(iOS)
        storedValue = NFScratchpadPayload(notes: notes, drawingData: drawingData).storedValue
        #else
        storedValue = NFScratchpadPayload(notes: notes, drawingData: Data()).storedValue
        #endif
    }
}

#if os(iOS)
private struct NFPencilCanvas: UIViewRepresentable {
    @Binding var drawingData: Data

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let toolPicker = PKToolPicker()
        var parent: NFPencilCanvas
        var isApplyingExternalDrawing = false

        init(parent: NFPencilCanvas) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingExternalDrawing else { return }
            parent.drawingData = canvasView.drawing.dataRepresentation()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 4)
        canvas.drawing = decodedDrawing
        context.coordinator.toolPicker.addObserver(canvas)
        context.coordinator.toolPicker.setVisible(true, forFirstResponder: canvas)
        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        let drawing = decodedDrawing
        guard canvas.drawing.dataRepresentation() != drawing.dataRepresentation() else { return }
        context.coordinator.isApplyingExternalDrawing = true
        canvas.drawing = drawing
        context.coordinator.isApplyingExternalDrawing = false
    }

    private var decodedDrawing: PKDrawing {
        guard !drawingData.isEmpty,
              let drawing = try? PKDrawing(data: drawingData) else { return PKDrawing() }
        return drawing
    }
}
#endif

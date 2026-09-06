import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import PencilKit
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct NFScratchpadPayload: Codable, Equatable, Sendable {
    static let prefix = "neuroforge-scratchpad-v1:"

    var notes: String
    var drawingData: Data

    static func decode(_ storedValue: String) -> NFScratchpadPayload {
        // Compatibility accessor for existing payload consumers. Presentation
        // uses inspect() so encoded failures cannot appear as learner notes.
        NFScratchpadInspection.inspect(storedValue).payload
            ?? NFScratchpadPayload(notes: storedValue, drawingData: Data())
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

/// These limits bound decoding before an imported value reaches PencilKit. They
/// do not truncate or rewrite the original string retained by the checkpoint.
struct NFScratchpadDecodeLimits: Equatable, Sendable {
    var maximumDecodedBytes = 8 * 1_024 * 1_024
    var maximumDrawingBytes = 4 * 1_024 * 1_024
    var maximumStoredBytes = ((8 * 1_024 * 1_024 + 2) / 3) * 4 + 128
    static let standard = NFScratchpadDecodeLimits()
}

struct NFScratchpadInspection: Equatable, Sendable {
    enum UnavailableReason: Equatable, Sendable { case unsupportedVersion, malformed, oversized, unsafeDrawing }
    let originalStoredValue: String
    let payload: NFScratchpadPayload?
    let unavailableReason: UnavailableReason?
    var canEdit: Bool { unavailableReason == nil && payload != nil }

    /// Called by both live and history presentation. Legacy plain text remains
    /// readable; an unknown encoded envelope is never mistaken for learner notes.
    static func inspect(_ storedValue: String, limits: NFScratchpadDecodeLimits = .standard) -> Self {
        func unavailable(_ reason: UnavailableReason) -> Self {
            .init(originalStoredValue: storedValue, payload: nil, unavailableReason: reason)
        }
        guard limits.maximumStoredBytes >= 0, limits.maximumDecodedBytes >= 0,
              limits.maximumDrawingBytes >= 0, limits.maximumStoredBytes < Int.max,
              limits.maximumDecodedBytes < Int.max - 2,
              storedValue.utf8.prefix(limits.maximumStoredBytes + 1).count <= limits.maximumStoredBytes else {
            return unavailable(.oversized)
        }
        guard storedValue.hasPrefix("neuroforge-scratchpad-") else {
            return .init(originalStoredValue: storedValue,
                payload: .init(notes: storedValue, drawingData: Data()), unavailableReason: nil)
        }
        guard storedValue.hasPrefix(NFScratchpadPayload.prefix) else { return unavailable(.unsupportedVersion) }
        let encoded = storedValue.dropFirst(NFScratchpadPayload.prefix.count)
        // Base64's maximum decoded length is known before allocating Data.
        guard encoded.utf8.count / 4 * 3 <= limits.maximumDecodedBytes + 2 else { return unavailable(.oversized) }
        guard let data = Data(base64Encoded: String(encoded)) else { return unavailable(.malformed) }
        guard data.count <= limits.maximumDecodedBytes else { return unavailable(.oversized) }
        guard let payload = try? JSONDecoder().decode(NFScratchpadPayload.self, from: data) else { return unavailable(.malformed) }
        guard payload.drawingData.count <= limits.maximumDrawingBytes else { return unavailable(.oversized) }
        return .init(originalStoredValue: storedValue, payload: payload, unavailableReason: nil)
    }

    /// A rejected edit leaves the exact previous value available for recovery.
    func accepting(_ candidate: NFScratchpadPayload, limits: NFScratchpadDecodeLimits = .standard) -> String? {
        guard canEdit else { return nil }
        let encoded = candidate.storedValue
        guard Self.inspect(encoded, limits: limits).canEdit else { return nil }
        return encoded
    }
}

struct NFScratchpadPreviewPlan: Equatable, Sendable {
    let rect: CGRect
    let scale: CGFloat
    var pixelWidth: Int { Int(ceil(rect.width * scale)) }
    var pixelHeight: Int { Int(ceil(rect.height * scale)) }
}

enum NFScratchpadGeometryPolicy {
    static let maximumCoordinate: CGFloat = 1_000_000
    static let maximumSpan: CGFloat = 100_000
    static let maximumPixelDimension: CGFloat = 1_024

    static func supports(_ bounds: CGRect) -> Bool {
        let values = [bounds.origin.x, bounds.origin.y, bounds.width, bounds.height]
        guard values.allSatisfy(\.isFinite), bounds.width >= 0, bounds.height >= 0,
              bounds.width <= maximumSpan, bounds.height <= maximumSpan else { return false }
        return [bounds.minX, bounds.maxX, bounds.minY, bounds.maxY].allSatisfy {
            $0.isFinite && abs($0) <= maximumCoordinate
        }
    }

    static func previewPlan(for bounds: CGRect) -> NFScratchpadPreviewPlan? {
        guard supports(bounds), !bounds.isEmpty else { return nil }
        let rect = bounds.insetBy(dx: -12, dy: -12)
        guard supports(rect), !rect.isEmpty else { return nil }
        let proposedScale = min(2, min(maximumPixelDimension / rect.width, maximumPixelDimension / rect.height))
        // Round down when shrinking so a floating-point boundary cannot request
        // a 1,025th pixel after the rasterizer rounds dimensions upward.
        let scale = proposedScale < 2 ? proposedScale.nextDown : proposedScale
        guard scale.isFinite, scale > 0 else { return nil }
        return .init(rect: rect, scale: scale)
    }
}

#if os(iOS)
enum NFScratchpadDrawingSafety {
    static func decode(_ data: Data) -> PKDrawing? {
        guard data.count <= NFScratchpadDecodeLimits.standard.maximumDrawingBytes else { return nil }
        guard !data.isEmpty else { return PKDrawing() }
        guard let drawing = try? PKDrawing(data: data) else { return nil }
        guard drawing.strokes.isEmpty || NFScratchpadGeometryPolicy.supports(drawing.bounds) else { return nil }
        return drawing
    }
}
#endif

/// Explicit recovery export contains the exact stored UTF-8 bytes. It neither
/// executes nor normalizes an unsupported encoded payload.
struct NFScratchpadRecoveryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let originalStoredValue: String
    var originalBytes: Data { Data(originalStoredValue.utf8) }
    init(originalStoredValue: String) { self.originalStoredValue = originalStoredValue }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents,
              let value = String(data: bytes, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        originalStoredValue = value
    }
    func makeRecoveryFileWrapper() -> FileWrapper { FileWrapper(regularFileWithContents: originalBytes) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { makeRecoveryFileWrapper() }
}

struct NFScratchpadRecoveryView: View {
    let storedValue: String
    var isUnsavedEdit = false
    @State private var showsExporter = false
    @State private var exportFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isUnsavedEdit {
                Text("This scratchpad is too large to save. Reduce it or export the current content before closing.")
                    .foregroundStyle(.secondary)
                Button("Export current scratchpad", systemImage: "square.and.arrow.up") { showsExporter = true }
            } else {
                Text("This scratchpad cannot be opened safely. Its original content is retained and can be exported.")
                    .foregroundStyle(.secondary)
                Button("Export original scratchpad", systemImage: "square.and.arrow.up") { showsExporter = true }
            }
            if exportFailed {
                Text("The original scratchpad could not be exported. It is still retained.").foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("scratchpad-recovery")
        .fileExporter(isPresented: $showsExporter,
            document: NFScratchpadRecoveryDocument(originalStoredValue: storedValue),
            contentType: .plainText, defaultFilename: "NeuroForge-Scratchpad-Recovery") { result in
                if case .failure = result { exportFailed = true } else { exportFailed = false }
            }
    }
}

/// Only question givens cross this boundary. The scratchpad never receives a
/// response, scoring key, hint ladder, worked answer or self-check reference.
struct NFScratchpadExerciseContext: Equatable, Sendable {
    let prompt: String
    let instructions: String?
    let contextText: String?
    let representations: [NFExerciseRepresentation]
    let initialLogicState: [String: String]
    let localeIdentifier: String

    static func make(exercise: NFExercise) -> Self {
        let representations: [NFExerciseRepresentation]
        if let metadata = exercise.contractMetadata,
           metadata.representationRoles.count != exercise.representations.count {
            representations = []
        } else {
            representations = exercise.independentRepresentations
        }
        let initial: [String: String]
        if case .logicState(let schema) = exercise.interaction,
           representations.contains(where: { if case .logicState = $0 { return true }; return false }) {
            initial = schema.initialState
        } else { initial = [:] }
        return .init(prompt: exercise.prompt, instructions: exercise.instructions,
            contextText: exercise.independentContextText, representations: representations,
            initialLogicState: initial, localeIdentifier: exercise.localeIdentifier)
    }
}

enum NFScratchpadLayoutPolicy {
    static func usesSplitPane(availableWidth: CGFloat, accessibilityType: Bool, hasContext: Bool) -> Bool {
        hasContext && availableWidth.isFinite && availableWidth >= 900 && !accessibilityType
    }

    static func expandedContextHeight(availableHeight: CGFloat) -> CGFloat {
        guard availableHeight.isFinite, availableHeight > 0 else { return 120 }
        return min(320, max(100, availableHeight * 0.42))
    }
}

/// Tracks the active native editor's undo manager; it does not interpret work
/// as an answer or serialize an additional undo history into the checkpoint.
@MainActor @Observable
final class NFScratchpadEditingController {
    private(set) var canUndo = false
    private(set) var canRedo = false
    @ObservationIgnored private weak var manager: UndoManager?
    @ObservationIgnored private var clearAction: (() -> Void)?

    func attach(manager: UndoManager?, clear: @escaping () -> Void) {
        self.manager = manager
        clearAction = clear
        refresh()
    }

    func refresh() {
        canUndo = manager?.canUndo == true
        canRedo = manager?.canRedo == true
    }

    func undo() { manager?.undo(); refresh() }
    func redo() { manager?.redo(); refresh() }
    func clear() { clearAction?(); refresh() }
}

struct ScratchpadView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var notesFontSize: CGFloat = 17
    @Binding private var storedValue: String
    private let questionContext: NFScratchpadExerciseContext?
    private let initialInspection: NFScratchpadInspection
    @State private var rejectedEdit: String?
    @State private var preservedDrawingData: Data
    @State private var notes: String
    @State private var showsQuestionContext = false
    @State private var notesEditing = NFScratchpadEditingController()

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
    @State private var drawingEditing = NFScratchpadEditingController()
    #endif

    init(text: Binding<String>, exercise: NFExercise? = nil, prompt: String? = nil) {
        questionContext = exercise.map { NFScratchpadExerciseContext.make(exercise: $0) }
            ?? prompt.map { .init(prompt: $0, instructions: nil, contextText: nil,
                representations: [], initialLogicState: [:], localeIdentifier: NFAppLocalization.preferredLocale.identifier) }
        _storedValue = text
        var inspection = NFScratchpadInspection.inspect(text.wrappedValue)
        #if os(iOS)
        if let payload = inspection.payload, NFScratchpadDrawingSafety.decode(payload.drawingData) == nil {
            inspection = .init(originalStoredValue: text.wrappedValue, payload: payload, unavailableReason: .unsafeDrawing)
        }
        #endif
        initialInspection = inspection
        let payload = inspection.payload ?? .init(notes: "", drawingData: Data())
        _notes = State(initialValue: payload.notes)
        _preservedDrawingData = State(initialValue: payload.drawingData)
        #if os(iOS)
        _drawingData = State(initialValue: payload.drawingData)
        _mode = State(initialValue: UIDevice.current.userInterfaceIdiom == .pad ? .draw : .notes)
        #endif
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let split = NFScratchpadLayoutPolicy.usesSplitPane(availableWidth: geometry.size.width,
                    accessibilityType: dynamicTypeSize.isAccessibilitySize, hasContext: questionContext != nil)
                let layout = split ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
                    : AnyLayout(VStackLayout(spacing: 0))
                layout {
                    if let questionContext {
                        questionPane(questionContext, split: split, height: geometry.size.height)
                            .frame(width: split ? min(480, geometry.size.width * 0.42) : nil)
                            .frame(maxHeight: split ? .infinity : nil)
                    }
                    editorPane.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .accessibilityIdentifier(split ? "scratchpad-split-layout" : "scratchpad-compact-layout")
            }
            .background(Color.windowBackground)
            .navigationTitle("Scratchpad")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HStack {
                        Button("Undo", systemImage: "arrow.uturn.backward") { activeEditing.undo() }
                            .disabled(!activeEditing.canUndo)
                            .keyboardShortcut("z", modifiers: .command)
                            .accessibilityIdentifier("scratchpad-undo")
                        Button("Redo", systemImage: "arrow.uturn.forward") { activeEditing.redo() }
                            .disabled(!activeEditing.canRedo)
                            .keyboardShortcut("z", modifiers: [.command, .shift])
                            .accessibilityIdentifier("scratchpad-redo")
                        Button("Clear", systemImage: "eraser") { activeEditing.clear() }
                            .disabled(currentInputIsEmpty)
                            .accessibilityIdentifier("scratchpad-clear")
                    }.disabled(!initialInspection.canEdit)
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if persist() { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let rejectedEdit {
                    NFScratchpadRecoveryView(storedValue: rejectedEdit, isUnsavedEdit: true).padding().background(.bar)
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
        .nfDesktopPresentationFrame(minWidth: 340, idealWidth: 1000, minHeight: 360, idealHeight: 700)
        .interactiveDismissDisabled(rejectedEdit != nil)
        .onChange(of: notes) { _, _ in persist() }
        #if os(iOS)
        .onChange(of: drawingData) { _, _ in persist() }
        #endif
        .onDisappear { persist() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)) { _ in activeEditing.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in activeEditing.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in activeEditing.refresh() }
    }

    private var activeEditing: NFScratchpadEditingController {
        #if os(iOS)
        mode == .draw ? drawingEditing : notesEditing
        #else
        notesEditing
        #endif
    }

    @ViewBuilder private var editorPane: some View {
        if !initialInspection.canEdit {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !notes.isEmpty { Text(notes).textSelection(.enabled) }
                    NFScratchpadRecoveryView(storedValue: initialInspection.originalStoredValue)
                }.padding()
            }
        } else {
            #if os(iOS)
            VStack(spacing: 0) {
                Picker("Scratchpad input", selection: $mode) {
                    ForEach(Mode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 10)
                ZStack {
                    NFPencilCanvas(drawingData: $drawingData, editing: drawingEditing, isActive: mode == .draw)
                        .opacity(mode == .draw ? 1 : 0).allowsHitTesting(mode == .draw)
                        .accessibilityHidden(mode != .draw)
                        .accessibilityLabel("Drawing scratchpad")
                        .accessibilityHint("Draw with Apple Pencil or touch. Use the PencilKit palette for pen, eraser, and lasso tools.")
                    NFScratchpadNotesEditor(text: $notes, editing: notesEditing, fontSize: notesFontSize, isActive: mode == .notes)
                        .opacity(mode == .notes ? 1 : 0).allowsHitTesting(mode == .notes)
                        .accessibilityHidden(mode != .notes)
                }
            }
            #else
            NFScratchpadNotesEditor(text: $notes, editing: notesEditing, fontSize: notesFontSize)
            #endif
        }
    }

    @ViewBuilder
    private func questionPane(_ context: NFScratchpadExerciseContext, split: Bool, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if split {
                Text("Current question").font(.headline).accessibilityHeading(.h2).padding()
                ScrollView { questionDetails(context).padding() }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(context.prompt).font(.body).lineLimit(2)
                        .accessibilityIdentifier("scratchpad-question-preview")
                    Button {
                        showsQuestionContext.toggle()
                    } label: {
                        Label(LocalizedStringKey(showsQuestionContext ? "Hide question context" : "Show question context"),
                            systemImage: showsQuestionContext ? "chevron.up" : "chevron.down")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("scratchpad-toggle-context")
                    .accessibilityValue(showsQuestionContext ? Text("Expanded") : Text("Collapsed"))
                }.padding()
                if showsQuestionContext {
                    ScrollView { questionDetails(context).padding() }
                        .frame(height: NFScratchpadLayoutPolicy.expandedContextHeight(availableHeight: height))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private func questionDetails(_ context: NFScratchpadExerciseContext) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(context.prompt).font(.headline).textSelection(.enabled)
            if let instructions = context.instructions, !instructions.isEmpty { Text(instructions).textSelection(.enabled) }
            if let text = context.contextText, !text.isEmpty { Text(text).textSelection(.enabled) }
            ForEach(Array(context.representations.enumerated()), id: \.offset) { _, representation in
                switch representation {
                case .table(let headers, let rows, let summary):
                    let model = NFExerciseTableAccessibilityModel(headers: headers, rows: rows, authoredSummary: summary)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(summary).font(.subheadline).accessibilityLabel(model.summary)
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Row \(index + 1)").font(.subheadline.bold())
                                ForEach(Array(row.enumerated()), id: \.offset) { column, value in
                                    VStack(alignment: .leading, spacing: 2) {
                                        if headers.indices.contains(column) { Text(headers[column]).font(.caption).foregroundStyle(.secondary) }
                                        Text(value).textSelection(.enabled)
                                    }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(model.cellLabel(rowIndex: index, columnIndex: column))
                                }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }.accessibilityIdentifier("scratchpad-question-table")
                case .spatial(let metadata):
                    NFSpatialDiagramView(metadata: metadata, localeIdentifier: context.localeIdentifier, prefersReducedMotion: reduceMotion)
                        .accessibilityIdentifier("scratchpad-question-diagram")
                case .equation(let latex, let spoken):
                    NFLaTeXEquationView(source: latex).accessibilityLabel(spoken)
                case .code(_, let source, let summary):
                    Text(summary).font(.subheadline)
                    Text(source).font(.body.monospaced()).textSelection(.enabled)
                case .logicState(let metadata):
                    VStack(alignment: .leading, spacing: 10) {
                        if !context.initialLogicState.isEmpty { Text("Original starting state").font(.headline) }
                        ForEach(context.initialLogicState.keys.sorted(), id: \.self) { key in
                            LabeledContent(key, value: context.initialLogicState[key] ?? "")
                        }
                        if !metadata.variables.isEmpty { Text("Original variables").font(.headline) }
                        ForEach(metadata.variables.keys.sorted(), id: \.self) { key in
                            LabeledContent(key, value: metadata.variables[key] ?? "")
                        }
                        ForEach(Array(metadata.transitions.enumerated()), id: \.offset) { index, transition in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Step \(index + 1)").font(.subheadline.bold())
                                Text(transition.condition).textSelection(.enabled)
                                Text(transition.mutation).font(.body.monospaced()).textSelection(.enabled)
                            }
                        }
                        if !metadata.invariants.isEmpty { Text("Original rules").font(.headline) }
                        ForEach(metadata.invariants.keys.sorted(), id: \.self) { key in
                            LabeledContent(key, value: metadata.invariants[key] ?? "")
                        }
                    }
                case .prose: EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("scratchpad-question-context")
    }

    private var currentInputIsEmpty: Bool {
        #if os(iOS)
        mode == .draw ? drawingData.isEmpty : notes.isEmpty
        #else
        notes.isEmpty
        #endif
    }

    @discardableResult
    private func persist() -> Bool {
        guard initialInspection.canEdit else { return true }
        #if os(iOS)
        let candidate = NFScratchpadPayload(notes: notes, drawingData: drawingData)
        #else
        let candidate = NFScratchpadPayload(notes: notes, drawingData: preservedDrawingData)
        #endif
        guard let accepted = initialInspection.accepting(candidate) else {
            rejectedEdit = candidate.storedValue
            return false
        }
        storedValue = accepted
        rejectedEdit = nil
        return true
    }
}

#if os(iOS)
@MainActor
final class NFScratchpadNativeNotesView: UITextView {
    private let editorUndoManager = UndoManager()
    override var undoManager: UndoManager? { editorUndoManager }
    var onTextChanged: ((String) -> Void)?

    func replaceAllUndoably(with replacement: String) {
        let previous = text ?? ""
        guard previous != replacement else { return }
        editorUndoManager.registerUndo(withTarget: self) { target in target.replaceAllUndoably(with: previous) }
        editorUndoManager.disableUndoRegistration()
        text = replacement
        selectedRange = NSRange(location: (replacement as NSString).length, length: 0)
        editorUndoManager.enableUndoRegistration()
        onTextChanged?(replacement)
    }
}

private struct NFScratchpadNotesEditor: UIViewRepresentable {
    @Binding var text: String
    let editing: NFScratchpadEditingController
    let fontSize: CGFloat
    let isActive: Bool

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NFScratchpadNotesEditor
        var wasActive: Bool
        init(_ parent: NFScratchpadNotesEditor) { self.parent = parent; wasActive = parent.isActive }
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.editing.refresh()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> NFScratchpadNativeNotesView {
        let view = NFScratchpadNativeNotesView()
        view.text = text
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        view.adjustsFontForContentSizeCategory = true
        view.undoManager?.levelsOfUndo = 30
        view.onTextChanged = { [weak coordinator = context.coordinator] value in
            coordinator?.parent.text = value
            coordinator?.parent.editing.refresh()
        }
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            editing.attach(manager: view.undoManager, clear: { [weak view] in view?.replaceAllUndoably(with: "") })
        }
        return view
    }

    func updateUIView(_ view: NFScratchpadNativeNotesView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.accessibilityLabel = NFAppLocalization.localized("Scratchpad notes", locale: NFAppLocalization.preferredLocale, comment: "Scratchpad notes editor accessibility name.")
        if !isActive && view.isFirstResponder { view.resignFirstResponder() }
        if isActive && !context.coordinator.wasActive {
            DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
                if coordinator?.parent.isActive == true { view?.becomeFirstResponder() }
            }
        }
        context.coordinator.wasActive = isActive
    }

    static func dismantleUIView(_ view: NFScratchpadNativeNotesView, coordinator: Coordinator) {
        view.undoManager?.removeAllActions()
        view.onTextChanged = nil
        view.delegate = nil
    }
}

@MainActor
final class NFScratchpadNativeCanvas: PKCanvasView {
    private let editorUndoManager = UndoManager()
    override var undoManager: UndoManager? { editorUndoManager }
    var onDrawingChanged: ((Data) -> Void)?

    func replaceDrawingUndoably(with replacement: PKDrawing) {
        let previous = drawing
        guard previous.dataRepresentation() != replacement.dataRepresentation() else { return }
        editorUndoManager.registerUndo(withTarget: self) { target in target.replaceDrawingUndoably(with: previous) }
        editorUndoManager.disableUndoRegistration()
        drawing = replacement
        editorUndoManager.enableUndoRegistration()
        onDrawingChanged?(replacement.strokes.isEmpty ? Data() : replacement.dataRepresentation())
    }
}

private struct NFPencilCanvas: UIViewRepresentable {
    @Binding var drawingData: Data
    let editing: NFScratchpadEditingController
    let isActive: Bool

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let toolPicker = PKToolPicker()
        var parent: NFPencilCanvas
        var isApplyingExternalDrawing = false
        var wasActive: Bool

        init(parent: NFPencilCanvas) {
            self.parent = parent
            wasActive = parent.isActive
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingExternalDrawing else { return }
            parent.drawingData = canvasView.drawing.strokes.isEmpty ? Data() : canvasView.drawing.dataRepresentation()
            parent.editing.refresh()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = NFScratchpadNativeCanvas()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 4)
        canvas.undoManager?.levelsOfUndo = 30
        if let drawing = decodedDrawing { canvas.drawing = drawing }
        canvas.undoManager?.removeAllActions()
        canvas.delegate = context.coordinator
        canvas.onDrawingChanged = { [weak coordinator = context.coordinator] data in
            coordinator?.parent.drawingData = data
            coordinator?.parent.editing.refresh()
        }
        context.coordinator.toolPicker.addObserver(canvas)
        DispatchQueue.main.async { [weak canvas] in
            guard let canvas else { return }
            editing.attach(manager: canvas.undoManager, clear: { [weak canvas] in canvas?.replaceDrawingUndoably(with: PKDrawing()) })
            if isActive { canvas.becomeFirstResponder() }
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.toolPicker.setVisible(isActive, forFirstResponder: canvas)
        if !isActive && canvas.isFirstResponder { canvas.resignFirstResponder() }
        if isActive && !context.coordinator.wasActive {
            DispatchQueue.main.async { [weak canvas, weak coordinator = context.coordinator] in
                if coordinator?.parent.isActive == true { canvas?.becomeFirstResponder() }
            }
        }
        context.coordinator.wasActive = isActive
        guard let drawing = decodedDrawing,
              canvas.drawing.dataRepresentation() != drawing.dataRepresentation() else { return }
        context.coordinator.isApplyingExternalDrawing = true
        canvas.undoManager?.disableUndoRegistration()
        canvas.drawing = drawing
        canvas.undoManager?.enableUndoRegistration()
        context.coordinator.isApplyingExternalDrawing = false
    }

    private var decodedDrawing: PKDrawing? {
        NFScratchpadDrawingSafety.decode(drawingData)
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker.removeObserver(canvas)
        canvas.undoManager?.removeAllActions()
        (canvas as? NFScratchpadNativeCanvas)?.onDrawingChanged = nil
        canvas.delegate = nil
    }
}
#elseif os(macOS)
@MainActor
final class NFScratchpadNativeNotesView: NSTextView {
    private let editorUndoManager = UndoManager()
    override var undoManager: UndoManager? { editorUndoManager }
    var onTextChanged: ((String) -> Void)?

    func replaceAllUndoably(with replacement: String) {
        let previous = string
        guard previous != replacement else { return }
        editorUndoManager.registerUndo(withTarget: self) { target in target.replaceAllUndoably(with: previous) }
        editorUndoManager.disableUndoRegistration()
        string = replacement
        setSelectedRange(NSRange(location: (replacement as NSString).length, length: 0))
        editorUndoManager.enableUndoRegistration()
        onTextChanged?(replacement)
    }
}

private struct NFScratchpadNotesEditor: NSViewRepresentable {
    @Binding var text: String
    let editing: NFScratchpadEditingController
    let fontSize: CGFloat

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NFScratchpadNotesEditor
        init(_ parent: NFScratchpadNotesEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            parent.editing.refresh()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let view = NFScratchpadNativeNotesView()
        view.string = text
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainerInset = NSSize(width: 16, height: 16)
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.undoManager?.levelsOfUndo = 30
        view.onTextChanged = { [weak coordinator = context.coordinator] value in
            coordinator?.parent.text = value
            coordinator?.parent.editing.refresh()
        }
        scroll.documentView = view
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            editing.attach(manager: view.undoManager, clear: { [weak view] in view?.replaceAllUndoably(with: "") })
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NFScratchpadNativeNotesView else { return }
        if view.string != text { view.string = text }
        view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.setAccessibilityLabel(NFAppLocalization.localized("Scratchpad notes", locale: NFAppLocalization.preferredLocale, comment: "Scratchpad notes editor accessibility name."))
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let view = scroll.documentView as? NFScratchpadNativeNotesView else { return }
        view.undoManager?.removeAllActions()
        view.onTextChanged = nil
        view.delegate = nil
    }
}
#endif

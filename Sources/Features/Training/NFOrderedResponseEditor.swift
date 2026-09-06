import SwiftUI
import UniformTypeIdentifiers

/// Private data has no text conformance, so a drag cannot insert an opaque
/// identifier into an answer or notes editor. Only this process can load it.
enum NFOrderedResponseDragPayload {
    static let type = UTType(exportedAs: "com.zacrotech.NeuroForge.ordered-response-step", conformingTo: .data)
    static func provider(token: String) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = Data(token.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
    static func token(from data: Data?) -> String? {
        guard let data, data.count <= 64, let value = String(data: data, encoding: .utf8),
              UUID(uuidString: value) != nil else { return nil }
        return value
    }
}

private enum NFOrderedResponseDiagnostics {
    static func record(_ event: String) {
        #if os(macOS)
        NFNativeSessionExitDiagnostics.record("ordered." + event)
        #endif
    }
}

/// Every interaction operates on the same stable-ID permutation. Drag preview
/// never mutates a response, and late native callbacks cannot edit a new item.
@MainActor @Observable
final class NFOrderedResponseController {
    @MainActor private final class NativeUndoTarget {
        weak var controller: NFOrderedResponseController?
        let id = UUID()
        init(controller: NFOrderedResponseController) { self.controller = controller }
    }
    private struct Change {
        let before: [String]; let after: [String]; let selectedID: String
        let target: NativeUndoTarget
    }
    let stepIDs: [String]
    private(set) var order: [String]
    private(set) var selectedID: String?
    private(set) var previewInsertion: Int?
    private var draggedID: String?
    private var dragToken: String?
    private var dragOriginal: [String]?
    private var pendingDropToken: String?
    private var undoChanges: [Change] = []
    private var redoChanges: [Change] = []
    private var mounted = false
    private var permitsEditing: () -> Bool = { false }
    private var publish: ([String]) -> Void = { _ in }
    private var didMove: (String, Int) -> Void = { _, _ in }
    private weak var undoManager: UndoManager?
    private var actionName = ""

    init(stepIDs: [String], order: [String]) { self.stepIDs = stepIDs; self.order = order }
    var isValid: Bool { Self.isPermutation(order, of: stepIDs) }
    var canEdit: Bool { mounted && permitsEditing() && isValid }
    var canUndo: Bool { canEdit && !undoChanges.isEmpty }
    var hasLocalDrag: Bool { canEdit && draggedID != nil && dragOriginal == order }

    static func isPermutation(_ order: [String], of stepIDs: [String]) -> Bool {
        !stepIDs.isEmpty && !stepIDs.contains(where: \.isEmpty)
            && Set(stepIDs).count == stepIDs.count && order.count == stepIDs.count
            && Set(order).count == order.count && Set(order) == Set(stepIDs)
    }

    func connect(undoManager: UndoManager?, actionName: String,
                 permitsEditing: @escaping () -> Bool,
                 publish: @escaping ([String]) -> Void,
                 didMove: @escaping (String, Int) -> Void = { _, _ in }) {
        mounted = true; self.undoManager = undoManager; self.actionName = actionName
        NFOrderedResponseDiagnostics.record(undoManager == nil ? "undo.connect-missing" : "undo.connect-present")
        self.permitsEditing = permitsEditing; self.publish = publish; self.didMove = didMove
    }

    func disconnect() {
        mounted = false; cancelDrag(); removeNativeActions()
        undoChanges = []; redoChanges = []; undoManager = nil
        permitsEditing = { false }; publish = { _ in }; didMove = { _, _ in }
    }

    /// A restore or different external edit invalidates old undo/drop callbacks;
    /// it never replaces a malformed original order with an invented one.
    func synchronize(_ value: [String]) {
        guard value != order else { return }
        order = value; cancelDrag(); removeNativeActions()
        undoChanges = []; redoChanges = []
        if let selectedID, !order.contains(selectedID) { self.selectedID = nil }
    }

    func select(_ id: String) { if order.contains(id) { selectedID = id } }

    func move(_ id: String, offset: Int) {
        guard canEdit, [-1, 1].contains(offset), let index = order.firstIndex(of: id),
              order.indices.contains(index + offset) else { return }
        var next = order; next.swapAt(index, index + offset)
        accept(next, selected: id)
    }

    func beginDrag(_ id: String) -> String? {
        guard canEdit, order.contains(id) else { return nil }
        cancelDrag(); selectedID = id; draggedID = id; dragOriginal = order
        let token = UUID().uuidString; dragToken = token; return token
    }

    func preview(at insertion: Int) {
        guard hasLocalDrag, (0...order.count).contains(insertion) else { return }
        previewInsertion = insertion
    }
    func leavePreview(at insertion: Int) { if previewInsertion == insertion { previewInsertion = nil } }
    func cancelDrag() { draggedID = nil; dragToken = nil; dragOriginal = nil; previewInsertion = nil; pendingDropToken = nil }

    /// A native source-end event is insufficient: this exact editor must first
    /// acknowledge a valid destination before an asynchronous load can commit.
    func prepareDrop(at insertion: Int) -> String? {
        guard hasLocalDrag, (0...order.count).contains(insertion), let dragToken else { return nil }
        pendingDropToken = dragToken
        return dragToken
    }
    @discardableResult
    func finishDrop(data: Data?, expectedToken: String, at insertion: Int) -> Bool {
        guard expectedToken == dragToken, expectedToken == pendingDropToken else { return false }
        guard NFOrderedResponseDragPayload.token(from: data) == expectedToken else {
            cancelDrag(); return false
        }
        return drop(token: expectedToken, at: insertion)
    }

    /// Called by the actual AppKit/UIKit source delegate, including Escape,
    /// drop outside the app, and a drag that never reaches a valid destination.
    func nativeDragEnded(token: String, acceptedMove: Bool) {
        guard token == dragToken else { return }
        if !acceptedMove || pendingDropToken != token { cancelDrag() }
    }

    @discardableResult
    func drop(token: String?, at insertion: Int) -> Bool {
        guard canEdit, let token, token == dragToken, dragOriginal == order,
              let id = draggedID, let oldIndex = order.firstIndex(of: id),
              (0...order.count).contains(insertion) else { return false }
        var next = order; next.remove(at: oldIndex)
        next.insert(id, at: insertion > oldIndex ? insertion - 1 : insertion)
        cancelDrag()
        guard next != order else { return true }
        accept(next, selected: id); return true
    }

    func undo() { undo(expectedTarget: nil) }

    private func undo(expectedTarget: UUID?) {
        NFOrderedResponseDiagnostics.record(expectedTarget == nil ? "undo.visible" : "undo.native")
        guard canUndo, let change = undoChanges.last, order == change.after,
              expectedTarget == nil || expectedTarget == change.target.id else { return }
        if undoManager?.isUndoing != true {
            // A visible Undo starts a new branch. Older native redo callbacks
            // cannot replay ahead of this inverse, so remove only our targets.
            for old in redoChanges { undoManager?.removeAllActions(withTarget: old.target) }
            redoChanges = []
        }
        undoChanges.removeLast(); redoChanges.append(change)
        if undoManager?.isUndoing != true {
            // Remove only this change from the native stack. Other text editors
            // and older ordering actions retain their own native undo entries.
            undoManager?.removeAllActions(withTarget: change.target)
        }
        apply(change.before, selected: change.selectedID)
        if undoManager?.isUndoing == true { registerRedo(change) }
    }

    private func redo(expectedTarget: UUID) {
        guard canEdit, let change = redoChanges.last, order == change.before,
              expectedTarget == change.target.id else { return }
        redoChanges.removeLast(); undoChanges.append(change)
        apply(change.after, selected: change.selectedID)
        registerUndo(change)
    }

    private func accept(_ next: [String], selected: String) {
        guard canEdit, Self.isPermutation(next, of: stepIDs), next != order else { return }
        let change = Change(before: order, after: next, selectedID: selected,
            target: NativeUndoTarget(controller: self))
        for old in redoChanges { undoManager?.removeAllActions(withTarget: old.target) }
        undoChanges.append(change); redoChanges = []
        apply(next, selected: selected); registerUndo(change)
    }
    private func apply(_ next: [String], selected: String) {
        cancelDrag(); order = next; selectedID = selected
        publish(next)
        if let index = next.firstIndex(of: selected) { didMove(selected, index + 1) }
    }
    private func registerUndo(_ change: Change) {
        NFOrderedResponseDiagnostics.record(undoManager == nil ? "undo.register-missing" : "undo.register-present")
        undoManager?.registerUndo(withTarget: change.target) { target in
            target.controller?.undo(expectedTarget: target.id)
        }
        undoManager?.setActionName(actionName)
    }
    private func registerRedo(_ change: Change) {
        undoManager?.registerUndo(withTarget: change.target) { target in
            target.controller?.redo(expectedTarget: target.id)
        }
        undoManager?.setActionName(actionName)
    }
    private func removeNativeActions() {
        for change in undoChanges + redoChanges {
            undoManager?.removeAllActions(withTarget: change.target)
            change.target.controller = nil
        }
    }

}

struct NFOrderedResponseEditor: View {
    let schema: NFOrderedStepsResponseSchema
    @Binding var order: [String]
    let isEditable: Bool
    let permitsEditing: () -> Bool
    var onInput: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    @Environment(\.undoManager) private var undoManager
    @State private var controller: NFOrderedResponseController
    @FocusState private var focusedStep: String?

    init(schema: NFOrderedStepsResponseSchema, order: Binding<[String]>, isEditable: Bool,
         permitsEditing: @escaping () -> Bool, onInput: @escaping () -> Void = {},
         onHover: @escaping (Bool) -> Void = { _ in }) {
        self.schema = schema; _order = order; self.isEditable = isEditable
        self.permitsEditing = permitsEditing; self.onInput = onInput; self.onHover = onHover
        _controller = State(initialValue: NFOrderedResponseController(stepIDs: schema.steps.map(\.id), order: order.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Arrange the steps").font(.headline)
            Text("Drag a step to an insertion line, or use Move up and Move down.").font(.caption).foregroundStyle(.secondary)
            if controller.isValid {
                ForEach(Array(controller.order.enumerated()), id: \.element) { index, id in
                    if let step = schema.steps.first(where: { $0.id == id }) {
                        VStack(spacing: 0) {
                            insertionMarker(at: index)
                            row(id: id, text: step.text, index: index)
                        }
                        .modifier(NFOrderedResponseDestination(controller: controller, insertion: index))
                    }
                }
                insertionMarker(at: controller.order.count)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .modifier(NFOrderedResponseDestination(controller: controller, insertion: controller.order.count))
                Button("Undo") { controller.undo() }
                    .buttonStyle(.bordered).frame(minHeight: 44)
                    .disabled(!isEditable || !controller.canUndo)
                    .accessibilityIdentifier("ordered-response-undo")
            } else {
                Text("The saved step order is unavailable. Your original answer is retained.")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ordered-response-editor")
        .onAppear { connect() }
        .onChange(of: order) { _, value in controller.synchronize(value) }
        .onChange(of: isEditable) { _, allowed in if !allowed { controller.cancelDrag() } }
        .onDisappear { controller.disconnect() }
    }

    private func connect() {
        controller.connect(undoManager: undoManager,
            actionName: NFAppLocalization.localized("Arrange the steps", locale: NFAppLocalization.preferredLocale, comment: "Undo action for ordering a response."),
            permitsEditing: permitsEditing,
            publish: { next in onInput(); order = next },
            didMove: { id, position in
                guard let step = schema.steps.first(where: { $0.id == id }) else { return }
                focusedStep = id
                let message = NFAppLocalization.localized("\(step.text), position \(position) of \(schema.steps.count)",
                    locale: NFAppLocalization.preferredLocale, comment: "Announces the resulting position of a reordered answer step.")
                AccessibilityNotification.Announcement(message).post()
            })
    }

    private func row(id: String, text: String, index: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                dragHandle(id: id)
                stepButton(id: id, text: text, index: index)
                moveButtons(id: id, text: text, index: index)
            }
            VStack(alignment: .leading, spacing: 8) {
                stepButton(id: id, text: text, index: index)
                HStack { dragHandle(id: id); moveButtons(id: id, text: text, index: index) }
            }
        }
        .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(controller.selectedID == id ? NFTheme.indigo : .clear, lineWidth: 2))
        .accessibilityElement(children: .contain)
        .onHover(perform: onHover)
    }

    private func dragHandle(id: String) -> some View {
        NFOrderedResponseNativeDragHandle(controller: controller, stepID: id, isEditable: isEditable)
            .frame(width: 44, height: 44)
            .accessibilityHidden(true) // Named move controls provide the equivalent action.
    }

    private func stepButton(id: String, text: String, index: Int) -> some View {
        Button { controller.select(id); focusedStep = id } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(index + 1)").font(.caption.bold().monospacedDigit())
                    .frame(width: 26, height: 26).background(.secondary.opacity(0.12), in: Circle())
                Text(text).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focusedStep, equals: id)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityValue(Text(verbatim: NFAppLocalization.localized("Position \(index + 1) of \(schema.steps.count)", locale: NFAppLocalization.preferredLocale, comment: "Current position of an answer step.")))
        .accessibilityHint("Use Move up or Move down, or the Up and Down arrow keys, to change this step’s position.")
        .onKeyPress(.upArrow) { NFOrderedResponseDiagnostics.record("key.up"); guard isEditable, controller.canEdit else { return .ignored }; controller.move(id, offset: -1); return .handled }
        .onKeyPress(.downArrow) { NFOrderedResponseDiagnostics.record("key.down"); guard isEditable, controller.canEdit else { return .ignored }; controller.move(id, offset: 1); return .handled }
    }

    @ViewBuilder private func moveButtons(id: String, text: String, index: Int) -> some View {
        moveButton(id: id, text: text, index: index, offset: -1)
        moveButton(id: id, text: text, index: index, offset: 1)
    }
    private func moveButton(id: String, text: String, index: Int, offset: Int) -> some View {
        Button { controller.move(id, offset: offset) } label: {
            Image(systemName: offset < 0 ? "arrow.up" : "arrow.down")
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
        .disabled(!isEditable || !controller.order.indices.contains(index + offset))
        .accessibilityLabel(Text(verbatim: offset < 0
            ? NFAppLocalization.localized("Move step \(index + 1) up: \(text)", locale: NFAppLocalization.preferredLocale, comment: "Accessibility label for moving an ordered response step up.")
            : NFAppLocalization.localized("Move step \(index + 1) down: \(text)", locale: NFAppLocalization.preferredLocale, comment: "Accessibility label for moving an ordered response step down.")))
    }
    private func insertionMarker(at position: Int) -> some View {
        Rectangle().fill(controller.previewInsertion == position ? NFTheme.indigo : .clear)
            .frame(height: 3).accessibilityHidden(true)
    }
}

private struct NFOrderedResponseDestination: ViewModifier {
    let controller: NFOrderedResponseController
    let insertion: Int
    func body(content: Content) -> some View {
        #if os(macOS)
        content.overlay {
            NFOrderedResponseNativeDropRegion(controller: controller, insertion: insertion)
                .accessibilityHidden(true)
        }
        #else
        content.onDrop(of: [NFOrderedResponseDragPayload.type],
            delegate: NFOrderedResponseDropDelegate(controller: controller, insertion: insertion))
        #endif
    }
}

private struct NFOrderedResponseDropDelegate: DropDelegate {
    let controller: NFOrderedResponseController
    let insertion: Int
    func validateDrop(info: DropInfo) -> Bool { controller.hasLocalDrag && info.hasItemsConforming(to: [NFOrderedResponseDragPayload.type]) }
    func dropEntered(info: DropInfo) { NFOrderedResponseDiagnostics.record("drop.entered"); controller.preview(at: insertion) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func dropExited(info: DropInfo) { controller.leavePreview(at: insertion) }
    func performDrop(info: DropInfo) -> Bool {
        NFOrderedResponseDiagnostics.record("drop.perform")
        guard let provider = info.itemProviders(for: [NFOrderedResponseDragPayload.type]).first,
              let expected = controller.prepareDrop(at: insertion) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: NFOrderedResponseDragPayload.type.identifier) { data, _ in
            Task { @MainActor in
                let accepted = controller.finishDrop(data: data, expectedToken: expected, at: insertion)
                NFOrderedResponseDiagnostics.record(accepted ? "drop.accepted" : "drop.rejected")
            }
        }
        return true
    }
}

#if os(macOS)
/// Native source and destination speak the same private pasteboard format.
/// This overlay is transparent to normal mouse/focus events. During our own
/// drag it supplies a registered AppKit destination over the existing row.
struct NFOrderedResponseNativeDropRegion: NSViewRepresentable {
    let controller: NFOrderedResponseController
    let insertion: Int
    final class Region: NSView {
        var controller: NFOrderedResponseController?
        var insertion = 0
        static let pasteboardType = NSPasteboard.PasteboardType(NFOrderedResponseDragPayload.type.identifier)
        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes([Self.pasteboardType])
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard controller?.hasLocalDrag == true else { return nil }
            return super.hitTest(point) == nil ? nil : self
        }
        private func verifiedPayload(_ sender: any NSDraggingInfo) -> (NFOrderedResponseController, String, Data)? {
            guard let controller, controller.hasLocalDrag,
                  let window, sender.draggingDestinationWindow === window,
                  sender.draggingSourceOperationMask.contains(.move),
                  let source = sender.draggingSource as? NFOrderedResponseNativeDragHandle.Handle,
                  source.window === window, source.controller === controller, source.isEditable,
                  let items = sender.draggingPasteboard.pasteboardItems, items.count == 1,
                  let data = items[0].data(forType: Self.pasteboardType),
                  let token = NFOrderedResponseDragPayload.token(from: data),
                  source.currentNativeToken == token,
                  (0...controller.order.count).contains(insertion) else { return nil }
            return (controller, token, data)
        }
        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            NFOrderedResponseDiagnostics.record("native-drop.entered")
            return draggingUpdated(sender)
        }
        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            guard let (controller, _, _) = verifiedPayload(sender) else {
                self.controller?.leavePreview(at: insertion)
                NFOrderedResponseDiagnostics.record("native-drop.rejected")
                return []
            }
            if controller.previewInsertion != insertion {
                NFOrderedResponseDiagnostics.record("native-drop.valid-target")
            }
            controller.preview(at: insertion)
            return .move
        }
        override func draggingExited(_ sender: (any NSDraggingInfo)?) {
            NFOrderedResponseDiagnostics.record("native-drop.exited")
            controller?.leavePreview(at: insertion)
        }
        override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            NFOrderedResponseDiagnostics.record("native-drop.prepare")
            return verifiedPayload(sender) != nil
        }
        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            NFOrderedResponseDiagnostics.record("native-drop.perform")
            guard let (controller, token, data) = verifiedPayload(sender),
                  controller.prepareDrop(at: insertion) == token else { return false }
            let accepted = controller.finishDrop(data: data, expectedToken: token, at: insertion)
            NFOrderedResponseDiagnostics.record(accepted ? "native-drop.accepted" : "native-drop.rejected")
            return accepted
        }
    }
    func makeNSView(context: Context) -> Region { Region(frame: .zero) }
    func updateNSView(_ view: Region, context: Context) {
        view.controller = controller; view.insertion = insertion
    }
    static func dismantleNSView(_ view: Region, coordinator: ()) {
        view.controller?.leavePreview(at: view.insertion)
        view.controller = nil; view.unregisterDraggedTypes()
    }
}

struct NFOrderedResponseNativeDragHandle: NSViewRepresentable {
    let controller: NFOrderedResponseController
    let stepID: String
    let isEditable: Bool
    final class Handle: NSView, NSDraggingSource {
        var controller: NFOrderedResponseController?
        var stepID = ""
        var isEditable = false
        private var tokens: [ObjectIdentifier: String] = [:]
        private(set) var currentNativeToken: String?
        private var mouseDownLocation: NSPoint?
        private let symbol = NSImageView()
        override init(frame: NSRect) {
            super.init(frame: frame)
            symbol.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
            symbol.contentTintColor = .secondaryLabelColor
            symbol.imageScaling = .scaleProportionallyDown
            addSubview(symbol)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func layout() { super.layout(); symbol.frame = bounds.insetBy(dx: 12, dy: 12) }
        // The decorative NSImageView is an NSControl. All points in this
        // grip belong to our source view, including the image at its center.
        override func hitTest(_ point: NSPoint) -> NSView? {
            super.hitTest(point) == nil ? nil : self
        }
        override func mouseDown(with event: NSEvent) {
            NFOrderedResponseDiagnostics.record("drag.mouse-down")
            guard isEditable, controller?.canEdit == true else {
                mouseDownLocation = nil
                return
            }
            controller?.select(stepID)
            mouseDownLocation = convert(event.locationInWindow, from: nil)
        }
        override func mouseUp(with event: NSEvent) {
            NFOrderedResponseDiagnostics.record("drag.mouse-up")
            mouseDownLocation = nil
        }
        override func mouseDragged(with event: NSEvent) {
            guard let start = mouseDownLocation, currentNativeToken == nil else { return }
            let point = convert(event.locationInWindow, from: nil)
            guard hypot(point.x - start.x, point.y - start.y) >= 3 else { return }
            mouseDownLocation = nil
            guard let token = beginNativeDrag() else {
                NFOrderedResponseDiagnostics.record("drag.not-editable"); return
            }
            NFOrderedResponseDiagnostics.record("drag.begin-after-movement")
            let payload = NSPasteboardItem()
            payload.setData(Data(token.utf8), forType: NSPasteboard.PasteboardType(NFOrderedResponseDragPayload.type.identifier))
            let item = NSDraggingItem(pasteboardWriter: payload)
            item.setDraggingFrame(bounds, contents: symbol.image)
            let session = beginDraggingSession(with: [item], event: event, source: self)
            tokens[ObjectIdentifier(session)] = token
        }
        /// Called by the actual mouse source; tests exercise this same local
        /// source lease without synthesizing an OS drag session.
        func beginNativeDrag() -> String? {
            guard isEditable, let token = controller?.beginDrag(stepID) else { return nil }
            currentNativeToken = token
            return token
        }
        func endNativeDrag(token: String, acceptedMove: Bool) {
            if currentNativeToken == token { currentNativeToken = nil }
            controller?.nativeDragEnded(token: token, acceptedMove: acceptedMove)
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? .move : []
        }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            guard let token = tokens.removeValue(forKey: ObjectIdentifier(session)) else { return }
            NFOrderedResponseDiagnostics.record(operation == .move ? "drag.end-move" : "drag.end-cancel")
            endNativeDrag(token: token, acceptedMove: operation == .move)
        }
        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    }
    func makeNSView(context: Context) -> Handle { Handle(frame: .zero) }
    func updateNSView(_ view: Handle, context: Context) {
        view.controller = controller; view.stepID = stepID; view.isEditable = isEditable
    }
}
#elseif os(iOS)
private struct NFOrderedResponseNativeDragHandle: UIViewRepresentable {
    let controller: NFOrderedResponseController
    let stepID: String
    let isEditable: Bool
    final class Handle: UIView, UIDragInteractionDelegate {
        var controller: NFOrderedResponseController?
        var stepID = ""
        var permitsDrag = false
        private let symbol = UIImageView(image: UIImage(systemName: "line.3.horizontal"))
        override init(frame: CGRect) {
            super.init(frame: frame)
            symbol.tintColor = .secondaryLabel; symbol.contentMode = .scaleAspectFit
            addSubview(symbol)
            let interaction = UIDragInteraction(delegate: self); interaction.isEnabled = true
            addInteraction(interaction)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func layoutSubviews() { super.layoutSubviews(); symbol.frame = bounds.insetBy(dx: 12, dy: 12) }
        func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: any UIDragSession) -> [UIDragItem] {
            guard permitsDrag, let token = controller?.beginDrag(stepID) else { return [] }
            let item = UIDragItem(itemProvider: NFOrderedResponseDragPayload.provider(token: token))
            item.localObject = token
            return [item]
        }
        func dragInteraction(_ interaction: UIDragInteraction, sessionAllowsMoveOperation session: any UIDragSession) -> Bool { true }
        func dragInteraction(_ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: any UIDragSession) -> Bool { true }
        func dragInteraction(_ interaction: UIDragInteraction, session: any UIDragSession, didEndWith operation: UIDropOperation) {
            guard let token = session.items.first?.localObject as? String else { return }
            controller?.nativeDragEnded(token: token, acceptedMove: operation == .move)
        }
    }
    func makeUIView(context: Context) -> Handle { Handle(frame: .zero) }
    func updateUIView(_ view: Handle, context: Context) {
        view.controller = controller; view.stepID = stepID; view.permitsDrag = isEditable
    }
}
#endif

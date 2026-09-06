import XCTest
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif
@testable import NeuroForge

@MainActor
final class OrderedResponseInteractionTests: XCTestCase {
    func testArrowAndValidatedDropProduceTheSameStableIDPermutation() throws {
        let ids = ["start", "middle", "end"]
        let arrow = NFOrderedResponseController(stepIDs: ids, order: ids)
        let drag = NFOrderedResponseController(stepIDs: ids, order: ids)
        var arrowResponse = ids, dragResponse = ids
        arrow.connect(undoManager: nil, actionName: "Order", permitsEditing: { true }, publish: { arrowResponse = $0 })
        drag.connect(undoManager: nil, actionName: "Order", permitsEditing: { true }, publish: { dragResponse = $0 })
        arrow.move("start", offset: 1)
        let token = try XCTUnwrap(drag.beginDrag("start"))
        drag.preview(at: 2)
        XCTAssertEqual(drag.order, ids)
        XCTAssertEqual(dragResponse, ids)
        XCTAssertTrue(drag.drop(token: token, at: 2))
        XCTAssertEqual(arrowResponse, ["middle", "start", "end"])
        XCTAssertEqual(dragResponse, arrowResponse)
        XCTAssertEqual(drag.selectedID, "start")
        XCTAssertEqual(arrow.selectedID, "start")
    }

    func testCancelledForeignAndLateDropsNeverChangeTheResponse() throws {
        let ids = ["a", "b", "c"]
        let controller = NFOrderedResponseController(stepIDs: ids, order: ids)
        var commits = 0
        controller.connect(undoManager: nil, actionName: "Order", permitsEditing: { true }, publish: { _ in commits += 1 })
        let original = try XCTUnwrap(controller.beginDrag("a"))
        controller.preview(at: 3)
        controller.cancelDrag()
        XCTAssertFalse(controller.drop(token: original, at: 3))
        let new = try XCTUnwrap(controller.beginDrag("b"))
        XCTAssertFalse(controller.drop(token: "foreign-provider", at: 0))
        XCTAssertFalse(controller.drop(token: original, at: 0))
        XCTAssertEqual(controller.order, ids)
        XCTAssertEqual(commits, 0)
        XCTAssertTrue(controller.drop(token: new, at: 0))
        XCTAssertEqual(controller.order, ["b", "a", "c"])
        XCTAssertEqual(commits, 1)
    }

    func testNativeUndoAndRedoUseTheSameGuardedResponsePath() {
        let ids = ["a", "b", "c"]
        let controller = NFOrderedResponseController(stepIDs: ids, order: ids)
        let manager = UndoManager(); manager.groupsByEvent = false
        var saved = ids, announcements: [(String, Int)] = []
        controller.connect(undoManager: manager, actionName: "Order", permitsEditing: { true }, publish: { saved = $0 }, didMove: { announcements.append(($0, $1)) })
        manager.beginUndoGrouping(); controller.move("a", offset: 1); manager.endUndoGrouping()
        XCTAssertEqual(saved, ["b", "a", "c"])
        manager.undo()
        XCTAssertEqual(saved, ids)
        XCTAssertEqual(announcements.last?.0, "a")
        XCTAssertEqual(announcements.last?.1, 1)
        manager.redo()
        XCTAssertEqual(saved, ["b", "a", "c"])
        XCTAssertEqual(controller.selectedID, "a")
        controller.undo()
        XCTAssertEqual(saved, ids)
        controller.disconnect()
        XCTAssertFalse(manager.canUndo)
    }

    func testFeedbackAndRemovedPresentationRejectAllPendingMutations() throws {
        let ids = ["a", "b", "c"]
        let controller = NFOrderedResponseController(stepIDs: ids, order: ids)
        let manager = UndoManager(); manager.groupsByEvent = false
        var editable = true, saved = ids
        controller.connect(undoManager: manager, actionName: "Order", permitsEditing: { editable }, publish: { saved = $0 })
        manager.beginUndoGrouping(); controller.move("a", offset: 1); manager.endUndoGrouping()
        let token = try XCTUnwrap(controller.beginDrag("c"))
        let committed = saved
        editable = false
        controller.move("c", offset: -1)
        controller.undo()
        XCTAssertFalse(controller.drop(token: token, at: 0))
        manager.undo()
        XCTAssertEqual(saved, committed)
        XCTAssertFalse(controller.canUndo)
        controller.disconnect()
        editable = true
        controller.move("c", offset: -1)
        XCTAssertFalse(controller.drop(token: token, at: 0))
        XCTAssertEqual(saved, committed)
    }

    func testExternalRestoreInvalidatesEarlierDragAndUndoWithoutInventingAnOrder() throws {
        let ids = ["a", "b", "c"]
        let controller = NFOrderedResponseController(stepIDs: ids, order: ids)
        let manager = UndoManager(); manager.groupsByEvent = false
        controller.connect(undoManager: manager, actionName: "Order", permitsEditing: { true }, publish: { _ in })
        manager.beginUndoGrouping(); controller.move("a", offset: 1); manager.endUndoGrouping()
        let token = try XCTUnwrap(controller.beginDrag("a"))
        controller.synchronize(["c", "b", "a"])
        XCTAssertFalse(controller.drop(token: token, at: 0))
        XCTAssertFalse(controller.canUndo)
        XCTAssertFalse(manager.canUndo)
        XCTAssertEqual(controller.order, ["c", "b", "a"])
        controller.synchronize(["a", "a"])
        controller.move("a", offset: 1)
        XCTAssertFalse(controller.isValid)
        XCTAssertEqual(controller.order, ["a", "a"], "An unreadable original order stays unchanged for recovery.")
    }

    func testBoundaryAndMalformedActionsPreserveEveryOriginalIdentifier() {
        let ids = ["a", "b", "c"]
        let controller = NFOrderedResponseController(stepIDs: ids, order: ids)
        var commits = 0
        controller.connect(undoManager: nil, actionName: "Order", permitsEditing: { true }, publish: { _ in commits += 1 })
        controller.move("a", offset: -1); controller.move("c", offset: 1)
        controller.move("unknown", offset: 1); controller.move("a", offset: 2)
        XCTAssertEqual(controller.order, ids); XCTAssertEqual(commits, 0)
        for bad in [[], ["a", "b"], ["a", "a", "c"], ["a", "b", "foreign"]] {
            XCTAssertFalse(NFOrderedResponseController.isPermutation(bad, of: ids))
        }
        XCTAssertFalse(NFOrderedResponseController.isPermutation(["a", "a"], of: ["a", "a"]))
    }
    func testExplicitUndoDoesNotUndoAnUnrelatedNativeActionAndNextNativeUndoUsesCurrentOrder() {
        final class OtherEditor { var text = "latest note" }
        let ids = ["a", "b", "c"]
        let controller = NFOrderedResponseController(stepIDs: ids, order: ids)
        let manager = UndoManager(); manager.groupsByEvent = false
        let other = OtherEditor()
        var saved = ids
        controller.connect(undoManager: manager, actionName: "Order", permitsEditing: { true }, publish: { saved = $0 })
        manager.beginUndoGrouping(); controller.move("a", offset: 1); manager.endUndoGrouping()
        manager.beginUndoGrouping(); controller.move("a", offset: 1); manager.endUndoGrouping()
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: other) { target in target.text = "prior note" }
        manager.endUndoGrouping()
        controller.undo()
        XCTAssertEqual(saved, ["b", "a", "c"])
        XCTAssertEqual(other.text, "latest note")
        manager.undo()
        XCTAssertEqual(other.text, "prior note")
        XCTAssertEqual(saved, ["b", "a", "c"])
        manager.undo()
        XCTAssertEqual(saved, ids)
        XCTAssertFalse(manager.canUndo, "Explicit Undo removes its own native entry instead of leaving a stale action.")
        controller.disconnect()
    }

    func testNativeCancellationRevokesPendingProviderButAcceptedMoveCanFinishAsynchronously() throws {
        let ids = ["a", "b", "c"]
        let controller = NFOrderedResponseController(stepIDs: ids, order: ids)
        var saved = ids
        controller.connect(undoManager: nil, actionName: "Order", permitsEditing: { true }, publish: { saved = $0 })
        let cancelled = try XCTUnwrap(controller.beginDrag("a"))
        controller.preview(at: 3)
        controller.nativeDragEnded(token: cancelled, acceptedMove: false)
        XCTAssertNil(controller.previewInsertion)
        XCTAssertFalse(controller.drop(token: cancelled, at: 3), "An OS-cancelled drag cannot be committed by a delayed provider callback.")
        XCTAssertEqual(saved, ids)
        let accepted = try XCTUnwrap(controller.beginDrag("c"))
        controller.preview(at: 0)
        XCTAssertEqual(controller.prepareDrop(at: 0), accepted)
        controller.nativeDragEnded(token: accepted, acceptedMove: true)
        XCTAssertEqual(saved, ids, "A source-end notification alone does not submit the drop.")
        XCTAssertTrue(controller.finishDrop(data: Data(accepted.utf8), expectedToken: accepted, at: 0))
        XCTAssertEqual(saved, ["c", "a", "b"])
    }

    func testLateCancellationFromEarlierDragDoesNotCancelNewerDrag() throws {
        let ids = ["a", "b", "c"]
        let controller = NFOrderedResponseController(stepIDs: ids, order: ids)
        controller.connect(undoManager: nil, actionName: "Order", permitsEditing: { true }, publish: { _ in })
        let old = try XCTUnwrap(controller.beginDrag("a"))
        let current = try XCTUnwrap(controller.beginDrag("c"))
        controller.preview(at: 0)
        controller.nativeDragEnded(token: old, acceptedMove: false)
        XCTAssertEqual(controller.previewInsertion, 0)
        XCTAssertTrue(controller.drop(token: current, at: 0))
        XCTAssertEqual(controller.order, ["c", "a", "b"])
    }


    func testVisibleUndoAfterNativeUndoRemovesObsoleteNativeRedo() {
        let ids = ["a", "b", "c"]
        let controller = NFOrderedResponseController(stepIDs: ids, order: ids)
        let manager = UndoManager(); manager.groupsByEvent = false
        var saved = ids
        controller.connect(undoManager: manager, actionName: "Order", permitsEditing: { true }, publish: { saved = $0 })
        manager.beginUndoGrouping(); controller.move("a", offset: 1); manager.endUndoGrouping() // A
        manager.beginUndoGrouping(); controller.move("a", offset: 1); manager.endUndoGrouping() // B
        manager.undo() // Native Undo(B) registers Redo(B).
        XCTAssertEqual(saved, ["b", "a", "c"])
        XCTAssertTrue(manager.canRedo)
        controller.undo() // Visible Undo(A) branches before B.
        XCTAssertEqual(saved, ids)
        XCTAssertFalse(manager.canRedo, "An obsolete editor redo must not stay enabled and silently consume Cmd-Shift-Z.")
        XCTAssertFalse(manager.canUndo)
        controller.disconnect()
    }

    func testPrivateDragPayloadHasNoTextRepresentationAndValidatesBoundedToken() async throws {
        let token = UUID().uuidString
        let provider = NFOrderedResponseDragPayload.provider(token: token)
        XCTAssertEqual(provider.registeredTypeIdentifiers, [NFOrderedResponseDragPayload.type.identifier])
        XCTAssertFalse(provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier))
        XCTAssertFalse(provider.hasItemConformingToTypeIdentifier(UTType.text.identifier))
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: NFOrderedResponseDragPayload.type.identifier) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile)) }
            }
        }
        XCTAssertEqual(NFOrderedResponseDragPayload.token(from: data), token)
        XCTAssertNil(NFOrderedResponseDragPayload.token(from: Data("answer text".utf8)))
        XCTAssertNil(NFOrderedResponseDragPayload.token(from: Data(repeating: 65, count: 65)))
    }

    func testForeignAcceptedMoveAndInvalidPendingPayloadRevokeOnlyTheirOwnDrag() throws {
        let ids = ["a", "b", "c"]
        let controller = NFOrderedResponseController(stepIDs: ids, order: ids)
        controller.connect(undoManager: nil, actionName: "Order", permitsEditing: { true }, publish: { _ in })
        let foreign = try XCTUnwrap(controller.beginDrag("a"))
        controller.nativeDragEnded(token: foreign, acceptedMove: true)
        XCTAssertFalse(controller.drop(token: foreign, at: 3), "An unrelated accepting destination cannot keep our token live.")
        let invalid = try XCTUnwrap(controller.beginDrag("a"))
        XCTAssertEqual(controller.prepareDrop(at: 3), invalid)
        XCTAssertFalse(controller.finishDrop(data: Data("wrong".utf8), expectedToken: invalid, at: 3))
        XCTAssertFalse(controller.hasLocalDrag)
        let stale = try XCTUnwrap(controller.beginDrag("a"))
        XCTAssertEqual(controller.prepareDrop(at: 3), stale)
        let current = try XCTUnwrap(controller.beginDrag("c"))
        XCTAssertFalse(controller.finishDrop(data: Data(stale.utf8), expectedToken: stale, at: 3))
        XCTAssertEqual(controller.prepareDrop(at: 0), current)
        XCTAssertTrue(controller.finishDrop(data: Data(current.utf8), expectedToken: current, at: 0))
        XCTAssertEqual(controller.order, ["c", "a", "b"])
    }

}

#if os(macOS)
@MainActor final class OrderedResponseNativeGripTests: XCTestCase {
    func testClickOnlySelectsWithoutStartingDragAndMouseUpCancelsDragReadiness() throws {
        let controller = NFOrderedResponseController(stepIDs: ["a", "b"], order: ["a", "b"])
        controller.connect(undoManager: nil, actionName: "Order", permitsEditing: { true }, publish: { _ in })
        defer { controller.disconnect() }
        let grip = NFOrderedResponseNativeDragHandle.Handle(frame: NSRect(x: 0, y: 0, width: 44, height: 44))
        grip.controller = controller; grip.stepID = "b"; grip.isEditable = true
        func event(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
        }
        grip.mouseDown(with: try event(.leftMouseDown, at: NSPoint(x: 22, y: 22)))
        XCTAssertEqual(controller.selectedID, "b")
        XCTAssertNil(grip.currentNativeToken)
        XCTAssertFalse(controller.hasLocalDrag, "A click is selection, not an already-running OS drag.")
        grip.mouseDragged(with: try event(.leftMouseDragged, at: NSPoint(x: 23, y: 22)))
        XCTAssertNil(grip.currentNativeToken, "Sub-threshold pointer jitter must not start a drag.")
        grip.mouseUp(with: try event(.leftMouseUp, at: NSPoint(x: 23, y: 22)))
        grip.mouseDragged(with: try event(.leftMouseDragged, at: NSPoint(x: 42, y: 22)))
        XCTAssertNil(grip.currentNativeToken, "A released click cannot start a delayed drag.")
        XCTAssertEqual(controller.order, ["a", "b"])
    }

    func testDecorativeImageCannotStealTheGripMouseTarget() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 140, height: 120))
        let grip = NFOrderedResponseNativeDragHandle.Handle(frame: NSRect(x: 30, y: 20, width: 44, height: 44))
        container.addSubview(grip)
        grip.layout()
        XCTAssertTrue(grip.subviews.first is NSImageView)
        XCTAssertTrue(container.hitTest(NSPoint(x: 52, y: 42)) === grip,
            "The image center must reach the actual NSDraggingSource mouseDown handler")
        XCTAssertTrue(container.hitTest(NSPoint(x: 31, y: 21)) === grip)
        XCTAssertFalse(container.hitTest(NSPoint(x: 75, y: 42)) === grip)
        grip.isHidden = true
        XCTAssertFalse(container.hitTest(NSPoint(x: 52, y: 42)) === grip)
    }
}
#endif

#if os(macOS)
@MainActor final class OrderedResponseNativeDestinationTests: XCTestCase {
    @MainActor private final class DragInfo: NSObject, NSDraggingInfo {
        var draggingDestinationWindow: NSWindow?
        var draggingSourceOperationMask: NSDragOperation = .move
        var draggingLocation = NSPoint.zero
        var draggedImageLocation = NSPoint.zero
        nonisolated var draggedImage: NSImage? { nil }
        let draggingPasteboard = NSPasteboard.withUniqueName()
        var draggingSource: Any?
        var draggingSequenceNumber = 1
        var draggingFormation: NSDraggingFormation = .none
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1
        var springLoadingHighlight: NSSpringLoadingHighlight { .none }
        func slideDraggedImage(to screenPoint: NSPoint) {}
        nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
        func resetSpringLoading() {}
        func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
            classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
            using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
        func setToken(_ token: String) {
            draggingPasteboard.clearContents()
            let item = NSPasteboardItem()
            item.setData(Data(token.utf8), forType: NFOrderedResponseNativeDropRegion.Region.pasteboardType)
            draggingPasteboard.writeObjects([item])
        }
    }
    private func fixture() -> (NSWindow, NFOrderedResponseController, NFOrderedResponseNativeDragHandle.Handle, NFOrderedResponseNativeDropRegion.Region) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let controller = NFOrderedResponseController(stepIDs: ["a", "b", "c"], order: ["a", "b", "c"])
        controller.connect(undoManager: nil, actionName: "Order", permitsEditing: { true }, publish: { _ in })
        let source = NFOrderedResponseNativeDragHandle.Handle(frame: NSRect(x: 30, y: 180, width: 44, height: 44))
        source.controller = controller; source.stepID = "c"; source.isEditable = true
        let destination = NFOrderedResponseNativeDropRegion.Region(frame: NSRect(x: 20, y: 20, width: 350, height: 100))
        destination.controller = controller; destination.insertion = 0
        window.contentView?.addSubview(source); window.contentView?.addSubview(destination)
        return (window, controller, source, destination)
    }
    func testNativeDestinationPreviewsThenCommitsExactPrivateLocalSource() throws {
        let (window, controller, source, destination) = fixture()
        defer { controller.disconnect(); window.close() }
        XCTAssertEqual(destination.registeredDraggedTypes, [NFOrderedResponseNativeDropRegion.Region.pasteboardType])
        XCTAssertNil(destination.hitTest(NSPoint(x: 30, y: 30)), "Normal pointer events must continue to the original SwiftUI controls.")
        let token = try XCTUnwrap(source.beginNativeDrag())
        let info = DragInfo(); info.draggingDestinationWindow = window; info.draggingSource = source; info.setToken(token)
        defer { info.draggingPasteboard.releaseGlobally() }
        XCTAssertTrue(destination.hitTest(NSPoint(x: 30, y: 30)) === destination)
        XCTAssertEqual(destination.draggingEntered(info), .move)
        XCTAssertEqual(controller.previewInsertion, 0)
        XCTAssertEqual(controller.order, ["a", "b", "c"], "Native preview does not change a response.")
        XCTAssertTrue(destination.prepareForDragOperation(info))
        XCTAssertTrue(destination.performDragOperation(info))
        XCTAssertEqual(controller.order, ["c", "a", "b"])
        source.endNativeDrag(token: token, acceptedMove: true)
        XCTAssertNil(source.currentNativeToken)
        XCTAssertFalse(controller.hasLocalDrag)
        XCTAssertFalse(destination.performDragOperation(info), "An accepted drop cannot be replayed.")
    }
    func testPrivateTokenAloneDoesNotAuthorizeForeignSourceOrOtherWindow() throws {
        let (window, controller, source, destination) = fixture()
        defer { controller.disconnect(); window.close() }
        let token = try XCTUnwrap(source.beginNativeDrag())
        let info = DragInfo(); info.draggingDestinationWindow = window; info.setToken(token)
        defer { info.draggingPasteboard.releaseGlobally() }
        info.draggingSource = NSObject()
        XCTAssertEqual(destination.draggingEntered(info), [])
        XCTAssertFalse(destination.performDragOperation(info))
        let impostor = NFOrderedResponseNativeDragHandle.Handle(frame: .zero)
        impostor.controller = controller; impostor.isEditable = true; window.contentView?.addSubview(impostor)
        info.draggingSource = impostor
        XCTAssertFalse(destination.prepareForDragOperation(info), "A source of the right class/controller still needs the original live source lease.")
        info.draggingSource = source; info.draggingDestinationWindow = nil
        XCTAssertFalse(destination.performDragOperation(info))
        info.draggingDestinationWindow = window; info.draggingSourceOperationMask = .copy
        XCTAssertEqual(destination.draggingEntered(info), [])
        XCTAssertEqual(controller.order, ["a", "b", "c"])
    }
    func testCancellationAndOwnerLockRejectNativeDropAfterPreview() throws {
        let (window, controller, source, destination) = fixture()
        defer { controller.disconnect(); window.close() }
        var editable = true
        controller.connect(undoManager: nil, actionName: "Order", permitsEditing: { editable }, publish: { _ in })
        let info = DragInfo(); info.draggingDestinationWindow = window; info.draggingSource = source
        defer { info.draggingPasteboard.releaseGlobally() }
        let old = try XCTUnwrap(source.beginNativeDrag()); info.setToken(old)
        XCTAssertEqual(destination.draggingEntered(info), .move)
        destination.draggingExited(info)
        XCTAssertNil(controller.previewInsertion)
        XCTAssertTrue(controller.hasLocalDrag, "Crossing to another row must not cancel the source.")
        source.endNativeDrag(token: old, acceptedMove: false)
        XCTAssertFalse(destination.performDragOperation(info))
        let current = try XCTUnwrap(source.beginNativeDrag()); info.setToken(current)
        XCTAssertEqual(destination.draggingEntered(info), .move)
        editable = false
        XCTAssertFalse(destination.prepareForDragOperation(info))
        XCTAssertFalse(destination.performDragOperation(info))
        XCTAssertEqual(controller.order, ["a", "b", "c"])
        XCTAssertNil(destination.hitTest(NSPoint(x: 30, y: 30)))
    }
}
#endif

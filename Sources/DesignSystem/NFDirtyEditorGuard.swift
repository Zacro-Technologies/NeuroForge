import SwiftUI

private struct NFDirtyEditorGuardModifier: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var generatedRegistrationID = UUID()

    let registrationID: UUID?
    let isDirty: Bool
    let title: String
    let onDiscard: () -> Void

    private var resolvedRegistrationID: UUID {
        registrationID ?? generatedRegistrationID
    }

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(isDirty)
            .onAppear {
                store.updateDirtyEditor(id: resolvedRegistrationID, title: title, isDirty: isDirty)
            }
            .onChange(of: isDirty) { _, newValue in
                store.updateDirtyEditor(id: resolvedRegistrationID, title: title, isDirty: newValue)
            }
            .onChange(of: store.lastDiscardedDirtyEditorID) { _, discardedID in
                guard discardedID == resolvedRegistrationID else { return }
                onDiscard()
                dismiss()
            }
            .onDisappear {
                store.clearDirtyEditor(id: resolvedRegistrationID)
            }
    }
}

extension View {
    func nfGuardsUnsavedEditor(
        _ isDirty: Bool,
        title: String,
        registrationID: UUID? = nil,
        onDiscard: @escaping () -> Void = {}
    ) -> some View {
        modifier(NFDirtyEditorGuardModifier(
            registrationID: registrationID,
            isDirty: isDirty,
            title: title,
            onDiscard: onDiscard
        ))
    }
}

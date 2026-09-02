import SwiftUI

struct NFSpotlightSettingsControls: View {
    @Environment(AppStore.self) private var store
    @Environment(NFSystemIntegrationCoordinator.self) private var integrations

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spotlight")
                .font(.subheadline.weight(.semibold))

            Toggle("Show NeuroForge study entries in system search", isOn: enabledBinding)
            Toggle("Include document titles", isOn: documentTitleBinding)
                .disabled(!integrations.spotlightDraftEnabled)
            Toggle("Include extracted source text", isOn: sourceTextBinding)
                .disabled(!integrations.spotlightDraftEnabled)

            sourceTextWarning

            LabeledContent("System search", value: localizedSpotlightStatus)
                .font(.subheadline)

            Button {
                Task { await integrations.applySpotlightPreferences(store: store) }
            } label: {
                Label("Apply search settings", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.bordered)
            .disabled(integrations.spotlightIsApplying)
        }
    }

    @ViewBuilder
    private var sourceTextWarning: some View {
        if integrations.spotlightDraftIncludesSourceText && integrations.spotlightDraftEnabled {
            Label {
                Text("Source excerpts may appear in system-wide search results on this device.")
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(NFTheme.amberForeground)
            }
            .font(.caption)
        }
    }

    private var localizedSpotlightStatus: String {
        switch integrations.spotlightStatus {
        case "On":
            NFAppLocalization.localized("On", locale: NFAppLocalization.preferredLocale, comment: "Spotlight integration status when system search is enabled.")
        case "Off":
            NFAppLocalization.localized("Off", locale: NFAppLocalization.preferredLocale, comment: "Spotlight integration status when system search is disabled.")
        case "Needs retry":
            NFAppLocalization.localized("Needs retry", locale: NFAppLocalization.preferredLocale, comment: "Spotlight integration status when applying search settings failed.")
        default:
            integrations.spotlightStatus
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { integrations.spotlightDraftEnabled },
            set: { integrations.spotlightDraftEnabled = $0 }
        )
    }

    private var documentTitleBinding: Binding<Bool> {
        Binding(
            get: { integrations.spotlightDraftIncludesDocumentTitles },
            set: { integrations.spotlightDraftIncludesDocumentTitles = $0 }
        )
    }

    private var sourceTextBinding: Binding<Bool> {
        Binding(
            get: { integrations.spotlightDraftIncludesSourceText },
            set: { integrations.spotlightDraftIncludesSourceText = $0 }
        )
    }
}

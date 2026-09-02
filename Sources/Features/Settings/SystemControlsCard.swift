import SwiftUI

struct SystemControlsCard: View {
    var body: some View {
        SettingsCard(
            symbol: "bell.and.waves.left.and.right.fill",
            color: NFTheme.amber,
            title: "Reminders & system search",
            subtitle: "Choose when NeuroForge can remind you or appear in system search."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                NFNotificationSettingsControls()
                Divider()
                NFSpotlightSettingsControls()
            }
        }
    }
}

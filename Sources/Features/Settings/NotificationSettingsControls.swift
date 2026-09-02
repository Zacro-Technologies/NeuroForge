import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct NFNotificationSettingsControls: View {
    @Environment(AppStore.self) private var store
    @Environment(NFSystemIntegrationCoordinator.self) private var integrations
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notifications")
                .font(.subheadline.weight(.semibold))

            NFDailyReminderControls()
            NFWeeklyReminderControls()

            Toggle("Review-due reminder", isOn: dueReviewBinding)

            NFQuietHoursControls()

            LabeledContent("Notification access", value: authorizationTitle)
                .font(.subheadline)

            if integrations.notificationAuthorization == .denied {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your reminder choices stay editable, but NeuroForge cannot deliver any reminder until notification access is allowed in System Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        if let url = notificationSettingsURL { openURL(url) }
                    } label: {
                        Label("Open System Settings", systemImage: "gear")
                    }
                    .buttonStyle(.bordered)
                    .disabled(notificationSettingsURL == nil)
                }
            }

            reminderActions
        }
    }

    private var dueReviewBinding: Binding<Bool> {
        Binding(
            get: { integrations.notificationPreferences.dueReviewReminderEnabled },
            set: { integrations.setDueReviewReminderEnabled($0) }
        )
    }

    private var reminderActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack { reminderActionButtons }
            VStack(alignment: .leading, spacing: 10) { reminderActionButtons }
        }
    }

    @ViewBuilder
    private var reminderActionButtons: some View {
        Button {
            Task { await integrations.applyNotificationPreferences(store: store) }
        } label: {
            Label("Save reminder schedule", systemImage: "checkmark.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(NFTheme.controlTint)
        .foregroundStyle(NFTheme.controlForeground)
        .disabled(!integrations.notificationPreferences.hasConfiguredReminder || integrations.notificationIsApplying)

        if integrations.notificationPreferences.hasConfiguredReminder {
            Button("Turn all off") {
                Task { await integrations.disableAllNotifications(store: store) }
            }
            .buttonStyle(.bordered)
            .disabled(integrations.notificationIsApplying)
        }
    }

    private var authorizationTitle: String {
        switch integrations.notificationAuthorization {
        case .notDetermined: NFAppLocalization.localized("Not requested", locale: NFAppLocalization.preferredLocale, comment: "Notification authorization status.")
        case .denied: NFAppLocalization.localized("Denied", locale: NFAppLocalization.preferredLocale, comment: "Notification authorization status.")
        case .authorized: NFAppLocalization.localized("Allowed", locale: NFAppLocalization.preferredLocale, comment: "Notification authorization status.")
        case .provisional: NFAppLocalization.localized("Provisional", locale: NFAppLocalization.preferredLocale, comment: "Notification authorization status granted provisionally by the system.")
        case .ephemeral: NFAppLocalization.localized("Temporary", locale: NFAppLocalization.preferredLocale, comment: "Temporary notification authorization status.")
        case .unavailable: NFAppLocalization.localized("Unavailable", locale: NFAppLocalization.preferredLocale, comment: "Notification authorization status.")
        }
    }

    private var notificationSettingsURL: URL? {
        #if os(iOS)
        URL(string: UIApplication.openSettingsURLString)
        #elseif os(macOS)
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        #else
        nil
        #endif
    }
}

private struct NFDailyReminderControls: View {
    @Environment(NFSystemIntegrationCoordinator.self) private var integrations

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Daily practice reminder", isOn: enabledBinding)

            if let time = integrations.notificationPreferences.dailyReminderTime {
                DatePicker(
                    "Reminder time",
                    selection: timeBinding(time),
                    displayedComponents: .hourAndMinute
                )
                Text("Uses your profile’s training days: \(trainingDaysSummary).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { integrations.notificationPreferences.dailyReminderTime != nil },
            set: { integrations.setDailyReminderEnabled($0) }
        )
    }

    private func timeBinding(_ time: NFLocalClockTime) -> Binding<Date> {
        Binding(
            get: { NFSettingsTime.date(for: time) },
            set: { integrations.setDailyReminder(date: $0) }
        )
    }

    private var trainingDaysSummary: String {
        let weekdays = integrations.notificationPreferences.trainingDays.sorted()
        if weekdays.count == NFWeekday.allCases.count {
            return NFAppLocalization.localized("every day", locale: NFAppLocalization.preferredLocale, comment: "Summary of a reminder schedule that includes every weekday.")
        }
        return weekdays.map(NFSettingsTime.weekdayTitle).joined(separator: ", ")
    }
}

private struct NFWeeklyReminderControls: View {
    @Environment(NFSystemIntegrationCoordinator.self) private var integrations

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Weekly reflection", isOn: enabledBinding)

            if integrations.notificationPreferences.weeklySummaryEnabled {
                Picker("Weekly day", selection: weekdayBinding) {
                    ForEach(NFWeekday.allCases, id: \.rawValue) { weekday in
                        Text(NFSettingsTime.weekdayTitle(weekday)).tag(weekday)
                    }
                }
                .pickerStyle(.menu)

                DatePicker(
                    "Weekly time",
                    selection: weeklyTimeBinding,
                    displayedComponents: .hourAndMinute
                )
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { integrations.notificationPreferences.weeklySummaryEnabled },
            set: { integrations.setWeeklySummaryEnabled($0) }
        )
    }

    private var weekdayBinding: Binding<NFWeekday> {
        Binding(
            get: { integrations.notificationPreferences.weeklySummaryWeekday },
            set: { integrations.setWeeklySummaryWeekday($0) }
        )
    }

    private var weeklyTimeBinding: Binding<Date> {
        Binding(
            get: { NFSettingsTime.date(for: integrations.notificationPreferences.weeklySummaryTime) },
            set: { integrations.setWeeklySummaryTime(date: $0) }
        )
    }
}

private struct NFQuietHoursControls: View {
    @Environment(NFSystemIntegrationCoordinator.self) private var integrations

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Quiet hours", isOn: enabledBinding)

            if let quietHours = integrations.notificationPreferences.quietHours {
                ViewThatFits(in: .horizontal) {
                    HStack { quietHourPickers(quietHours) }
                    VStack(alignment: .leading, spacing: 10) { quietHourPickers(quietHours) }
                }
            }
        }
    }

    @ViewBuilder
    private func quietHourPickers(_ quietHours: NFQuietHours) -> some View {
        DatePicker(
            "From",
            selection: startBinding(quietHours),
            displayedComponents: .hourAndMinute
        )
        DatePicker(
            "Until",
            selection: endBinding(quietHours),
            displayedComponents: .hourAndMinute
        )
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { integrations.notificationPreferences.quietHours != nil },
            set: { integrations.setQuietHoursEnabled($0) }
        )
    }

    private func startBinding(_ hours: NFQuietHours) -> Binding<Date> {
        Binding(
            get: { NFSettingsTime.date(for: hours.startsAt) },
            set: { integrations.setQuietHoursStart(date: $0) }
        )
    }

    private func endBinding(_ hours: NFQuietHours) -> Binding<Date> {
        Binding(
            get: { NFSettingsTime.date(for: hours.endsAt) },
            set: { integrations.setQuietHoursEnd(date: $0) }
        )
    }
}

private enum NFSettingsTime {
    static func date(for time: NFLocalClockTime) -> Date {
        var calendar = Calendar.current
        calendar.locale = NFAppLocalization.preferredLocale
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = time.hour
        components.minute = time.minute
        return calendar.date(from: components) ?? Date()
    }

    static func weekdayTitle(_ weekday: NFWeekday) -> String {
        switch weekday {
        case .sunday: NFAppLocalization.localized("Sun", locale: NFAppLocalization.preferredLocale, comment: "Abbreviated weekday name for Sunday.")
        case .monday: NFAppLocalization.localized("Mon", locale: NFAppLocalization.preferredLocale, comment: "Abbreviated weekday name for Monday.")
        case .tuesday: NFAppLocalization.localized("Tue", locale: NFAppLocalization.preferredLocale, comment: "Abbreviated weekday name for Tuesday.")
        case .wednesday: NFAppLocalization.localized("Wed", locale: NFAppLocalization.preferredLocale, comment: "Abbreviated weekday name for Wednesday.")
        case .thursday: NFAppLocalization.localized("Thu", locale: NFAppLocalization.preferredLocale, comment: "Abbreviated weekday name for Thursday.")
        case .friday: NFAppLocalization.localized("Fri", locale: NFAppLocalization.preferredLocale, comment: "Abbreviated weekday name for Friday.")
        case .saturday: NFAppLocalization.localized("Sat", locale: NFAppLocalization.preferredLocale, comment: "Abbreviated weekday name for Saturday.")
        }
    }
}

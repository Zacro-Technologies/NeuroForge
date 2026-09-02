import Foundation

#if canImport(UserNotifications)
@preconcurrency import UserNotifications
#endif

extension Notification.Name {
    static let neuroForgeExternalRouteRequested = Notification.Name(
        "NeuroForge.ExternalRouteRequested"
    )
}

enum NFNotificationAuthorizationStatus: String, Codable, Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unavailable

    var permitsScheduling: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied, .unavailable:
            false
        }
    }
}

enum NFNotificationLanguage: String, Codable, Equatable, Sendable {
    case english
    case japanese

    init(localeIdentifier: String) {
        self = localeIdentifier
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .hasPrefix("ja") ? .japanese : .english
    }
}

struct NFNotificationCategoryPresentation: Equatable, Sendable {
    let language: NFNotificationLanguage
    let openActionTitle: String

    init(language: NFNotificationLanguage) {
        self.language = language
        let locale = Locale(identifier: language == .japanese ? "ja" : "en")
        openActionTitle = NFAppLocalization.localized(
            "Open NeuroForge",
            locale: locale,
            comment: "Notification action that opens the task named by the reminder."
        )
    }
}

enum NFWeekday: Int, Codable, CaseIterable, Comparable, Sendable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    static func < (lhs: NFWeekday, rhs: NFWeekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct NFLocalClockTime: Codable, Equatable, Sendable {
    let hour: Int
    let minute: Int

    init?(hour: Int, minute: Int) {
        guard (0 ... 23).contains(hour), (0 ... 59).contains(minute) else {
            return nil
        }
        self.hour = hour
        self.minute = minute
    }

    static let nineAM = NFLocalClockTime(hour: 9, minute: 0)!

    fileprivate var minutesAfterMidnight: Int {
        hour * 60 + minute
    }
}

struct NFQuietHours: Codable, Equatable, Sendable {
    let startsAt: NFLocalClockTime
    let endsAt: NFLocalClockTime

    func contains(_ time: NFLocalClockTime) -> Bool {
        let start = startsAt.minutesAfterMidnight
        let end = endsAt.minutesAfterMidnight
        let candidate = time.minutesAfterMidnight

        if start == end {
            return false
        }
        if start < end {
            return candidate >= start && candidate < end
        }
        return candidate >= start || candidate < end
    }
}

struct NFNotificationPreferences: Codable, Equatable, Sendable {
    var dailyReminderTime: NFLocalClockTime?
    var trainingDays: Set<NFWeekday>
    var weeklySummaryEnabled: Bool
    var weeklySummaryWeekday: NFWeekday
    var weeklySummaryTime: NFLocalClockTime
    var dueReviewReminderEnabled: Bool
    var quietHours: NFQuietHours?

    init(
        dailyReminderTime: NFLocalClockTime? = nil,
        trainingDays: Set<NFWeekday> = [],
        weeklySummaryEnabled: Bool = false,
        weeklySummaryWeekday: NFWeekday = .sunday,
        weeklySummaryTime: NFLocalClockTime = .nineAM,
        dueReviewReminderEnabled: Bool = false,
        quietHours: NFQuietHours? = nil
    ) {
        self.dailyReminderTime = dailyReminderTime
        self.trainingDays = trainingDays
        self.weeklySummaryEnabled = weeklySummaryEnabled
        self.weeklySummaryWeekday = weeklySummaryWeekday
        self.weeklySummaryTime = weeklySummaryTime
        self.dueReviewReminderEnabled = dueReviewReminderEnabled
        self.quietHours = quietHours
    }

    var hasConfiguredReminder: Bool {
        (dailyReminderTime != nil && !trainingDays.isEmpty)
            || weeklySummaryEnabled
            || dueReviewReminderEnabled
    }
}

enum NFNotificationScheduleKind: String, Codable, CaseIterable, Equatable, Sendable {
    case dailyTraining
    case weeklySummary
    case dueReview
}

enum NFNotificationRecurrence: Codable, Equatable, Sendable {
    case weekly(weekday: NFWeekday, time: NFLocalClockTime, timeZoneIdentifier: String)
    case oneTime(DateComponents)
}

struct NFNotificationScheduleDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: NFNotificationScheduleKind
    let title: String
    let body: String
    let recurrence: NFNotificationRecurrence

    var deepLinkURL: URL {
        let value = switch kind {
        case .dailyTraining: "neuroforge://today"
        case .weeklySummary: "neuroforge://progress"
        case .dueReview: "neuroforge://today?review=due"
        }
        return URL(string: value)!
    }

    var categoryIdentifier: String {
        "NF_\(kind.rawValue.uppercased())"
    }
}

enum NFNotificationPlanNotice: String, Codable, Equatable, Sendable {
    case adjustedDailyReminderForQuietHours
    case adjustedWeeklySummaryForQuietHours
    case adjustedDueReviewForQuietHours
    case omittedPastDueReview
}

struct NFNotificationPlan: Codable, Equatable, Sendable {
    let descriptors: [NFNotificationScheduleDescriptor]
    let notices: [NFNotificationPlanNotice]
}

enum NFNotificationPlanner {
    static let managedIdentifiers: Set<String> = Set(
        NFWeekday.allCases.map { "nf.notification.daily.\($0.rawValue)" }
            + ["nf.notification.weekly-summary", "nf.notification.due-review"]
    )

    static func makePlan(
        preferences: NFNotificationPreferences,
        dueReviewAt: Date?,
        now: Date,
        calendar suppliedCalendar: Calendar,
        timeZone: TimeZone,
        language: NFNotificationLanguage
    ) -> NFNotificationPlan {
        var descriptors: [NFNotificationScheduleDescriptor] = []
        var notices: [NFNotificationPlanNotice] = []

        let copy = NFNotificationCopy(language: language)
        let timeZoneIdentifier = timeZone.identifier

        if let requestedTime = preferences.dailyReminderTime, !preferences.trainingDays.isEmpty {
            let resolvedTime = resolve(requestedTime, against: preferences.quietHours)
            if resolvedTime != requestedTime {
                notices.append(.adjustedDailyReminderForQuietHours)
            }

            for weekday in preferences.trainingDays.sorted() {
                descriptors.append(
                    NFNotificationScheduleDescriptor(
                        id: "nf.notification.daily.\(weekday.rawValue)",
                        kind: .dailyTraining,
                        title: copy.dailyTitle,
                        body: copy.dailyBody,
                        recurrence: .weekly(
                            weekday: weekday,
                            time: resolvedTime,
                            timeZoneIdentifier: timeZoneIdentifier
                        )
                    )
                )
            }
        }

        if preferences.weeklySummaryEnabled {
            let resolvedTime = resolve(preferences.weeklySummaryTime, against: preferences.quietHours)
            if resolvedTime != preferences.weeklySummaryTime {
                notices.append(.adjustedWeeklySummaryForQuietHours)
            }
            descriptors.append(
                NFNotificationScheduleDescriptor(
                    id: "nf.notification.weekly-summary",
                    kind: .weeklySummary,
                    title: copy.weeklyTitle,
                    body: copy.weeklyBody,
                    recurrence: .weekly(
                        weekday: preferences.weeklySummaryWeekday,
                        time: resolvedTime,
                        timeZoneIdentifier: timeZoneIdentifier
                    )
                )
            )
        }

        if preferences.dueReviewReminderEnabled, let dueReviewAt {
            var calendar = suppliedCalendar
            calendar.timeZone = timeZone
            let adjustedDueDate = resolve(
                dueReviewAt,
                against: preferences.quietHours,
                calendar: calendar
            )
            if adjustedDueDate != dueReviewAt {
                notices.append(.adjustedDueReviewForQuietHours)
            }

            if adjustedDueDate > now {
                var components = calendar.dateComponents(
                    [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
                    from: adjustedDueDate
                )
                components.calendar = calendar
                components.timeZone = timeZone
                if
                    let minuteBoundary = calendar.date(from: components),
                    minuteBoundary <= now,
                    let nextMinute = calendar.date(byAdding: .minute, value: 1, to: minuteBoundary)
                {
                    components = calendar.dateComponents(
                        [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
                        from: nextMinute
                    )
                    components.calendar = calendar
                    components.timeZone = timeZone
                }
                descriptors.append(
                    NFNotificationScheduleDescriptor(
                        id: "nf.notification.due-review",
                        kind: .dueReview,
                        title: copy.dueTitle,
                        body: copy.dueBody,
                        recurrence: .oneTime(components)
                    )
                )
            } else {
                notices.append(.omittedPastDueReview)
            }
        }

        return NFNotificationPlan(descriptors: descriptors, notices: notices)
    }

    private static func resolve(
        _ time: NFLocalClockTime,
        against quietHours: NFQuietHours?
    ) -> NFLocalClockTime {
        guard let quietHours, quietHours.contains(time) else { return time }
        return quietHours.endsAt
    }

    private static func resolve(
        _ date: Date,
        against quietHours: NFQuietHours?,
        calendar: Calendar
    ) -> Date {
        guard
            let quietHours,
            let localTime = NFLocalClockTime(
                hour: calendar.component(.hour, from: date),
                minute: calendar.component(.minute, from: date)
            ),
            quietHours.contains(localTime)
        else {
            return date
        }

        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = quietHours.endsAt.hour
        components.minute = quietHours.endsAt.minute
        components.second = 0

        guard let sameDay = calendar.date(from: components) else { return date }
        if sameDay >= date {
            return sameDay
        }
        return calendar.date(byAdding: .day, value: 1, to: sameDay) ?? date
    }
}

private struct NFNotificationCopy: Sendable {
    let dailyTitle: String
    let dailyBody: String
    let weeklyTitle: String
    let weeklyBody: String
    let dueTitle: String
    let dueBody: String

    init(language: NFNotificationLanguage) {
        let locale = Locale(identifier: language == .japanese ? "ja" : "en")
        dailyTitle = NFAppLocalization.localized(
            "Your practice is ready",
            locale: locale,
            comment: "Title of the optional daily local training reminder notification."
        )
        dailyBody = NFAppLocalization.localized(
            "A short NeuroForge session is available.",
            locale: locale,
            comment: "Body of the optional daily local training reminder notification."
        )
        weeklyTitle = NFAppLocalization.localized(
            "Weekly reflection",
            locale: locale,
            comment: "Title of the optional weekly local progress-summary notification."
        )
        weeklyBody = NFAppLocalization.localized(
            "Review your week and choose what to practice next.",
            locale: locale,
            comment: "Body of the optional weekly local progress-summary notification."
        )
        dueTitle = NFAppLocalization.localized(
            "Reviews are ready",
            locale: locale,
            comment: "Title of the optional local reminder that retention reviews are due."
        )
        dueBody = NFAppLocalization.localized(
            "A short review can strengthen retention.",
            locale: locale,
            comment: "Body of the optional local reminder that retention reviews are due. Retention means durable recall after a delay."
        )
    }
}

protocol NFNotificationCenterClient: Sendable {
    func refreshCategories(using presentation: NFNotificationCategoryPresentation) async
    func authorizationStatus() async -> NFNotificationAuthorizationStatus
    func requestAuthorizationAfterExplicitOptIn() async throws -> NFNotificationAuthorizationStatus
    func replaceManagedSchedules(with descriptors: [NFNotificationScheduleDescriptor]) async throws
    func removeManagedSchedules() async throws
}

enum NFNotificationCleanupError: Error {
    case verificationFailed
}

enum NFNotificationConfigurationOutcome: Equatable, Sendable {
    case noRemindersConfigured
    case awaitingExplicitOptIn
    case denied
    case scheduled(NFNotificationPlan)
    case unavailable
}

actor NFNotificationOptInCoordinator {
    private let client: any NFNotificationCenterClient

    init(client: any NFNotificationCenterClient) {
        self.client = client
    }

    func apply(
        preferences: NFNotificationPreferences,
        dueReviewAt: Date?,
        now: Date,
        calendar: Calendar,
        timeZone: TimeZone,
        language: NFNotificationLanguage,
        userExplicitlySavedAndOptedIn: Bool
    ) async throws -> NFNotificationConfigurationOutcome {
        guard preferences.hasConfiguredReminder else {
            try await client.removeManagedSchedules()
            return .noRemindersConfigured
        }

        var status = await client.authorizationStatus()
        if status == .notDetermined {
            guard userExplicitlySavedAndOptedIn else {
                return .awaitingExplicitOptIn
            }
            status = try await client.requestAuthorizationAfterExplicitOptIn()
        }

        guard status.permitsScheduling else {
            return status == .denied ? .denied : .unavailable
        }

        let plan = NFNotificationPlanner.makePlan(
            preferences: preferences,
            dueReviewAt: dueReviewAt,
            now: now,
            calendar: calendar,
            timeZone: timeZone,
            language: language
        )
        try await client.replaceManagedSchedules(with: plan.descriptors)
        return .scheduled(plan)
    }

    func removeAllManagedSchedules() async throws {
        try await client.removeManagedSchedules()
    }
}

#if canImport(UserNotifications)
final class NFNotificationResponseRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NFNotificationResponseRouter()
    static let routeUserInfoKey = "neuroforge.route"

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let rawValue = response.notification.request.content.userInfo[
            Self.routeUserInfoKey
        ] as? String,
        let url = URL(string: rawValue) else { return }
        await MainActor.run {
            NotificationCenter.default.post(
                name: .neuroForgeExternalRouteRequested,
                object: url
            )
        }
    }
}

actor NFUserNotificationCenterAdapter: NFNotificationCenterClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        center.delegate = NFNotificationResponseRouter.shared
        Self.registerCategories(
            using: NFNotificationCategoryPresentation(
                language: NFNotificationLanguage(
                    localeIdentifier: NFAppLocalization.preferredLanguageCode
                )
            ),
            center: center
        )
    }

    func refreshCategories(using presentation: NFNotificationCategoryPresentation) async {
        Self.registerCategories(using: presentation, center: center)
    }

    private static func registerCategories(
        using presentation: NFNotificationCategoryPresentation,
        center: UNUserNotificationCenter
    ) {
        let openAction = UNNotificationAction(
            identifier: "NF_OPEN",
            title: presentation.openActionTitle,
            options: [.foreground]
        )
        center.setNotificationCategories(Set(NFNotificationScheduleKind.allCases.map { kind in
            UNNotificationCategory(
                identifier: "NF_\(kind.rawValue.uppercased())",
                actions: [openAction],
                intentIdentifiers: [],
                options: []
            )
        }))
    }

    func authorizationStatus() async -> NFNotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    func requestAuthorizationAfterExplicitOptIn() async throws -> NFNotificationAuthorizationStatus {
        _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        return await authorizationStatus()
    }

    func replaceManagedSchedules(with descriptors: [NFNotificationScheduleDescriptor]) async throws {
        center.removePendingNotificationRequests(
            withIdentifiers: Array(NFNotificationPlanner.managedIdentifiers)
        )

        for descriptor in descriptors {
            let content = UNMutableNotificationContent()
            content.title = descriptor.title
            content.body = descriptor.body
            content.sound = .default
            content.categoryIdentifier = descriptor.categoryIdentifier
            content.threadIdentifier = "neuroforge.\(descriptor.kind.rawValue)"
            content.userInfo = [
                NFNotificationResponseRouter.routeUserInfoKey:
                    descriptor.deepLinkURL.absoluteString
            ]

            let trigger: UNNotificationTrigger
            switch descriptor.recurrence {
            case let .weekly(weekday, time, timeZoneIdentifier):
                var components = DateComponents()
                components.calendar = Calendar(identifier: .gregorian)
                components.timeZone = TimeZone(identifier: timeZoneIdentifier)
                components.weekday = weekday.rawValue
                components.hour = time.hour
                components.minute = time.minute
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            case let .oneTime(components):
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            }

            try await center.add(
                UNNotificationRequest(
                    identifier: descriptor.id,
                    content: content,
                    trigger: trigger
                )
            )
        }
    }

    func removeManagedSchedules() async throws {
        let identifiers = Array(NFNotificationPlanner.managedIdentifiers)
        center.removePendingNotificationRequests(
            withIdentifiers: identifiers
        )
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        async let pending = center.pendingNotificationRequests()
        async let delivered = center.deliveredNotifications()
        let remainingPending = await pending
        let remainingDelivered = await delivered
        guard
            remainingPending.allSatisfy({ !NFNotificationPlanner.managedIdentifiers.contains($0.identifier) }),
            remainingDelivered.allSatisfy({ !NFNotificationPlanner.managedIdentifiers.contains($0.request.identifier) })
        else {
            throw NFNotificationCleanupError.verificationFailed
        }
    }

    private static func map(_ status: UNAuthorizationStatus) -> NFNotificationAuthorizationStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        case .ephemeral: .ephemeral
        @unknown default: .unavailable
        }
    }
}
#endif

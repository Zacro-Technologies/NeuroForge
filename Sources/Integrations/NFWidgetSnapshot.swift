import Foundation

enum NFWidgetLanguage: String, Codable, Equatable, Sendable {
    case english = "en"
    case japanese = "ja"

    init(localeIdentifier: String) {
        self = localeIdentifier
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .hasPrefix("ja") ? .japanese : .english
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }
}

struct NFWidgetBlockSnapshot: Codable, Equatable, Sendable {
    let title: String
    let minutes: Int
    let isComplete: Bool
}

struct NFWidgetSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    /// The learner's in-app language at publication time. Widget rendering
    /// must never infer this from SpringBoard's or the device's current locale.
    let language: NFWidgetLanguage
    let generatedAt: Date
    let localDayKey: String
    let scheduledMinutes: Int
    let completedItems: Int
    let expectedItems: Int
    let reviewsDue: Int
    let blocks: [NFWidgetBlockSnapshot]

    var progress: Double {
        guard expectedItems > 0 else { return 0 }
        return min(1, max(0, Double(completedItems) / Double(expectedItems)))
    }

    var nextBlock: NFWidgetBlockSnapshot? {
        blocks.first(where: { !$0.isComplete })
    }

    /// One state drives widget copy, accessibility, and routing so the visual
    /// presentation cannot advertise Start after the plan is complete.
    var planState: NFWidgetPlanState {
        guard expectedItems > 0, !blocks.isEmpty else { return .noPlan }
        if blocks.allSatisfy(\.isComplete) || completedItems >= expectedItems {
            return .completed
        }
        return completedItems > 0 || blocks.contains(where: \.isComplete)
            ? .inProgress
            : .ready
    }

    static let placeholder = NFWidgetSnapshot(
        schemaVersion: schemaVersion,
        language: .english,
        generatedAt: .now,
        localDayKey: "today",
        scheduledMinutes: 10,
        completedItems: 2,
        expectedItems: 6,
        reviewsDue: 1,
        blocks: [
            NFWidgetBlockSnapshot(title: "Review", minutes: 2, isComplete: true),
            NFWidgetBlockSnapshot(title: "Practice", minutes: 5, isComplete: false),
            NFWidgetBlockSnapshot(title: "Transfer", minutes: 3, isComplete: false)
        ]
    )
}

enum NFWidgetDurationStyle: Sendable {
    case compact
    case full
}

/// A single, testable presentation model drives every learner-facing widget
/// string and format. The selected language is carried by the snapshot so a
/// widget process cannot silently fall back to its own environment locale.
struct NFWidgetPresentation {
    let snapshot: NFWidgetSnapshot
    private let bundle: Bundle

    init(snapshot: NFWidgetSnapshot, bundle: Bundle = .main) {
        self.snapshot = snapshot
        self.bundle = bundle
    }

    var locale: Locale { snapshot.language.locale }

    var todayTitle: String {
        localized("Today")
    }

    var widgetDisplayName: String {
        localized("NeuroForge Today")
    }

    var widgetDescription: String {
        localized("Start or continue today’s privacy-safe training plan.")
    }

    var emptyPlanInstruction: String {
        localized("Open NeuroForge to prepare today’s private plan.")
    }

    var planDateLabel: String {
        let calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(secondsFromGMT: 0)!
        return Date.FormatStyle(
            date: .abbreviated,
            time: .omitted,
            locale: locale,
            calendar: calendar,
            timeZone: timeZone,
            capitalizationContext: .unknown
        ).format(planDate)
    }

    var progressPercent: String {
        snapshot.progress.formatted(
            .percent
                .precision(.fractionLength(0))
                .locale(locale)
        )
    }

    func duration(_ rawValue: Int, style: NFWidgetDurationStyle = .full) -> String {
        let value = max(0, rawValue)
        switch style {
        case .compact:
            return formatted("%lld min", Int64(value))
        case .full where value == 1:
            return localized("1 minute")
        case .full:
            return formatted("%lld minutes", Int64(value))
        }
    }

    var actionTitle: String {
        switch snapshot.planState {
        case .noPlan:
            return localized("Open NeuroForge")
        case .ready:
            return formatted("Start · %@ plan", duration(snapshot.scheduledMinutes, style: .compact))
        case .inProgress:
            return formatted("Continue · %@ plan", duration(snapshot.scheduledMinutes, style: .compact))
        case .completed:
            return localized("Review today")
        }
    }

    var accessorySummary: String {
        switch snapshot.planState {
        case .noPlan:
            return localized("No plan yet")
        case .completed:
            return localized("Today’s plan complete")
        case .ready, .inProgress:
            return formatted(
                "%lld/%lld complete",
                Int64(snapshot.completedItems),
                Int64(snapshot.expectedItems)
            )
        }
    }

    var accessibilityLabel: String {
        switch snapshot.planState {
        case .noPlan:
            return formatted(
                "NeuroForge Today, %@. No plan yet. Open NeuroForge.",
                planDateLabel
            )
        case .ready:
            return formatted(
                "NeuroForge Today, %@. %@ plan, not started. Start plan.",
                planDateLabel,
                duration(snapshot.scheduledMinutes)
            )
        case .inProgress:
            return formatted(
                "NeuroForge Today, %@. %lld/%lld complete. Continue plan.",
                planDateLabel,
                Int64(snapshot.completedItems),
                Int64(snapshot.expectedItems)
            )
        case .completed:
            return formatted(
                "NeuroForge Today, %@. Plan complete. Review today’s work.",
                planDateLabel
            )
        }
    }

    private var planDate: Date {
        let dateComponents = snapshot.localDayKey
            .prefix(10)
            .split(separator: "-")
            .compactMap { Int($0) }
        guard dateComponents.count == 3 else { return snapshot.generatedAt }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: dateComponents[0],
            month: dateComponents[1],
            day: dateComponents[2]
        )) ?? snapshot.generatedAt
    }

    private func localized(_ key: String) -> String {
        let localizedBundle: Bundle
        if let path = bundle.path(forResource: snapshot.language.rawValue, ofType: "lproj"),
           let selectedBundle = Bundle(path: path) {
            localizedBundle = selectedBundle
        } else {
            localizedBundle = bundle
        }
        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    private func formatted(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: locale, arguments: arguments)
    }
}

enum NFWidgetPlanState: String, Codable, Equatable, Sendable {
    case noPlan
    case ready
    case inProgress
    case completed

    var deepLink: URL {
        let value = switch self {
        case .noPlan, .ready, .inProgress: "neuroforge://today"
        case .completed: "neuroforge://today?review=completed"
        }
        return URL(string: value)!
    }
}

enum NFWidgetSnapshotStore {
    static let appGroupIdentifier = "group.com.zacrotech.NeuroForge"
    static let snapshotKey = "NeuroForge.WidgetSnapshot.v1"

    static func read() -> NFWidgetSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(NFWidgetSnapshot.self, from: data),
              snapshot.schemaVersion == NFWidgetSnapshot.schemaVersion else {
            return nil
        }
        return snapshot
    }

    static func write(_ snapshot: NFWidgetSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        defaults.set(try encoder.encode(snapshot), forKey: snapshotKey)
    }

    static func delete() {
        defaults.removeObject(forKey: snapshotKey)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}

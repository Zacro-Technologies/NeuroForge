import AppIntents
import Foundation

enum NeuroForgeShortcutRoute: String {
    case startToday
    case continueSession
    case practiceMentalMath
    case openReviews
    case logReadiness
    case importStudyMaterial
}

extension Notification.Name {
    static let neuroForgeShortcutQueued = Notification.Name("NeuroForge.ShortcutQueued")
}

enum NeuroForgeShortcutHandoff {
    private static let routeKey = "NeuroForge.PendingShortcut.Route"
    private static let durationKey = "NeuroForge.PendingShortcut.Duration"
    private static let mentalMathKindKey = "NeuroForge.PendingShortcut.MentalMathKind"
    private static let readinessKey = "NeuroForge.PendingShortcut.Readiness"
    private static let tokenKey = "NeuroForge.PendingShortcut.Token"
    private static let lastConsumedTokenKey = "NeuroForge.PendingShortcut.LastConsumedToken"

    static let allDefaultsKeys: Set<String> = [
        routeKey,
        durationKey,
        mentalMathKindKey,
        readinessKey,
        tokenKey,
        lastConsumedTokenKey
    ]

    static func enqueue(
        _ route: NeuroForgeShortcutRoute,
        duration: Int? = nil,
        mentalMathKind: MentalMathKind? = nil,
        readiness: Readiness? = nil
    ) {
        let defaults = UserDefaults.standard
        if let duration {
            defaults.set(duration, forKey: durationKey)
        } else {
            defaults.removeObject(forKey: durationKey)
        }
        if let mentalMathKind {
            defaults.set(mentalMathKind.rawValue, forKey: mentalMathKindKey)
        } else {
            defaults.removeObject(forKey: mentalMathKindKey)
        }
        if let readiness {
            defaults.set(readiness.rawValue, forKey: readinessKey)
        } else {
            defaults.removeObject(forKey: readinessKey)
        }
        defaults.set(UUID().uuidString, forKey: tokenKey)
        defaults.set(route.rawValue, forKey: routeKey)
        NotificationCenter.default.post(name: .neuroForgeShortcutQueued, object: nil)
    }

    @MainActor
    static func consume(into store: AppStore) {
        let defaults = UserDefaults.standard
        guard
            let rawRoute = defaults.string(forKey: routeKey),
            let route = NeuroForgeShortcutRoute(rawValue: rawRoute)
        else { return }

        let duration = defaults.object(forKey: durationKey) == nil ? nil : defaults.integer(forKey: durationKey)
        let mentalMathKind = defaults.string(forKey: mentalMathKindKey).flatMap(MentalMathKind.init(rawValue:))
        let readiness = defaults.string(forKey: readinessKey).flatMap(Readiness.init(rawValue:))
        let token = defaults.string(forKey: tokenKey) ?? [
            rawRoute,
            duration.map(String.init) ?? "",
            mentalMathKind?.rawValue ?? "",
            readiness?.rawValue ?? ""
        ].joined(separator: "|")

        guard defaults.string(forKey: lastConsumedTokenKey) != token else {
            clearPendingRequest(in: defaults)
            return
        }
        defaults.set(token, forKey: lastConsumedTokenKey)
        clearPendingRequest(in: defaults)

        switch route {
        case .startToday:
            store.requestTodayPlan()
        case .continueSession:
            store.selectedDestination = .today
        case .practiceMentalMath:
            store.requestFocusedMentalMathPractice(
                requestedMinutes: duration,
                preferredMentalMathKind: mentalMathKind
            )
        case .openReviews:
            store.requestReviewsDue()
        case .logReadiness:
            store.updateReadiness(readiness ?? .normal)
            store.selectedDestination = .today
        case .importStudyMaterial:
            store.requestDocumentImport()
        }
    }

    private static func clearPendingRequest(in defaults: UserDefaults) {
        defaults.removeObject(forKey: routeKey)
        defaults.removeObject(forKey: durationKey)
        defaults.removeObject(forKey: mentalMathKindKey)
        defaults.removeObject(forKey: readinessKey)
        defaults.removeObject(forKey: tokenKey)
    }

    static func clearAllState(defaults: UserDefaults = .standard) throws {
        for key in allDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
        guard allDefaultsKeys.allSatisfy({ defaults.object(forKey: $0) == nil }) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

enum MentalMathPracticeDuration: Int, AppEnum {
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case twentyMinutes = 20

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Practice duration"
    }

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [
            .fiveMinutes: "5 minutes",
            .tenMinutes: "10 minutes",
            .fifteenMinutes: "15 minutes",
            .twentyMinutes: "20 minutes"
        ]
    }
}

enum MentalMathShortcutSubskill: String, AppEnum {
    case flexibleCalculation
    case percentages
    case scientificNotation
    case estimation

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Mental math subskill"
    }

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [
            .flexibleCalculation: "Flexible calculation",
            .percentages: "Percentages",
            .scientificNotation: "Scientific notation",
            .estimation: "Estimation"
        ]
    }

    var mentalMathKind: MentalMathKind {
        switch self {
        case .flexibleCalculation: .multiplication
        case .percentages: .percentage
        case .scientificNotation: .scientificNotation
        case .estimation: .estimation
        }
    }
}

enum ReadinessShortcutLevel: String, AppEnum {
    case low
    case normal
    case high

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Readiness"
    }

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [
            .low: "Low",
            .normal: "Normal",
            .high: "High"
        ]
    }
}

struct StartTodaySessionIntent: AppIntent {
    static var title: LocalizedStringResource { "Start Today’s Session" }
    static var description: IntentDescription? {
        "Opens NeuroForge so you can review and start today’s session."
    }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    func perform() async throws -> some IntentResult {
        NeuroForgeShortcutHandoff.enqueue(.startToday)
        return .result(dialog: "Opening today’s NeuroForge plan.")
    }
}

struct ContinueSessionIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Current Session" }
    static var description: IntentDescription? {
        "Brings NeuroForge forward and opens Today. Any active session remains open, and saved unfinished blocks can be resumed."
    }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    func perform() async throws -> some IntentResult {
        NeuroForgeShortcutHandoff.enqueue(.continueSession)
        return .result(dialog: "Opening NeuroForge. An active session remains open; saved unfinished work is available from Today.")
    }
}

struct PracticeMentalMathIntent: AppIntent {
    static var title: LocalizedStringResource { "Practice Mental Math" }
    static var description: IntentDescription? {
        "Opens NeuroForge so you can configure a mental math practice session."
    }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Duration", default: .tenMinutes)
    var duration: MentalMathPracticeDuration

    @Parameter(title: "Subskill")
    var subskill: MentalMathShortcutSubskill?

    func perform() async throws -> some IntentResult {
        NeuroForgeShortcutHandoff.enqueue(
            .practiceMentalMath,
            duration: duration.rawValue,
            mentalMathKind: subskill?.mentalMathKind
        )
        return .result(dialog: "Opening the requested mental math practice in NeuroForge.")
    }
}

struct OpenReviewsDueIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Reviews Due" }
    static var description: IntentDescription? {
        "Starts the first due retention review, or opens Today when nothing is due."
    }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    func perform() async throws -> some IntentResult {
        NeuroForgeShortcutHandoff.enqueue(.openReviews)
        return .result(dialog: "Opening reviews due in NeuroForge.")
    }
}

struct LogReadinessIntent: AppIntent {
    static var title: LocalizedStringResource { "Log Readiness" }
    static var description: IntentDescription? {
        "Opens NeuroForge so you can confirm your readiness before training."
    }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Readiness", default: .normal)
    var level: ReadinessShortcutLevel

    func perform() async throws -> some IntentResult {
        NeuroForgeShortcutHandoff.enqueue(
            .logReadiness,
            readiness: Readiness(rawValue: level.rawValue) ?? .normal
        )
        return .result(dialog: "Your readiness is applied to today’s plan.")
    }
}

struct ImportStudyMaterialIntent: AppIntent {
    static var title: LocalizedStringResource { "Import Study Material" }
    static var description: IntentDescription? {
        "Opens NeuroForge so you can choose study material with the system file picker."
    }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    func perform() async throws -> some IntentResult {
        NeuroForgeShortcutHandoff.enqueue(.importStudyMaterial)
        return .result(dialog: "Opening NeuroForge’s study-material picker.")
    }
}

/// First action in the user-owned Question Writer Shortcut. NeuroForge passes
/// only an opaque request ID in the launch URL. The expiring prompt contains a
/// question brief and, only after per-run source-sharing approval, up to four
/// source excerpts (1,600 characters each and 4,800 total). Each excerpt is
/// bound internally to its exact chunk identity, version, and content hash;
/// original files remain local. The user chooses the provider in Shortcuts, so
/// NeuroForge cannot attest which model handles the prompt.
struct GetPendingAIRequestIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Question Writer Brief" }
    static var description: IntentDescription? {
        "Gets one expiring NeuroForge question brief for the Use Model action in your Shortcut."
    }
    static var supportedModes: IntentModes { .background }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @Parameter(
        title: "Request ID",
        description: "The opaque request ID passed in as Shortcut Input."
    )
    var requestID: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let prompt = try await NFShortcutAuthoringRequestStore.shared.modelPrompt(
            requestID: requestID
        )
        return .result(value: prompt)
    }
}

/// Final action in the user-owned Question Writer Shortcut. It accepts only
/// strict JSON, validates and stores it once, then returns a small receipt for
/// Shortcuts' documented x-callback result instead of putting provider output
/// in the callback URL. The response records the user-configured Shortcut
/// route, not an attested model provider.
struct SubmitAIResultForReviewIntent: AppIntent {
    static var title: LocalizedStringResource { "Submit Question Writer Result" }
    static var description: IntentDescription? {
        "Checks a Question Writer response and returns it to NeuroForge for local review."
    }
    static var supportedModes: IntentModes { .background }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @Parameter(
        title: "Request ID",
        description: "The same opaque request ID supplied to the first NeuroForge action."
    )
    var requestID: String

    @Parameter(
        title: "Question Writer Output",
        description: "The structured text returned by the Use Model action in Shortcuts."
    )
    var modelOutput: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let receipt = try await NFShortcutAuthoringRequestStore.shared.submit(
            requestID: requestID,
            modelOutput: modelOutput
        )
        return .result(value: receipt)
    }
}

struct NeuroForgeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTodaySessionIntent(),
            phrases: ["Start today’s session in \(.applicationName)"],
            shortTitle: "Start Today",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: ContinueSessionIntent(),
            phrases: ["Open my current session in \(.applicationName)"],
            shortTitle: "Current Session",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: PracticeMentalMathIntent(),
            phrases: ["Practice mental math with \(.applicationName)"],
            shortTitle: "Mental Math",
            systemImageName: "function"
        )
        AppShortcut(
            intent: OpenReviewsDueIntent(),
            phrases: ["Open reviews due in \(.applicationName)"],
            shortTitle: "Reviews Due",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: LogReadinessIntent(),
            phrases: ["Log readiness in \(.applicationName)"],
            shortTitle: "Log Readiness",
            systemImageName: "battery.75percent"
        )
        AppShortcut(
            intent: ImportStudyMaterialIntent(),
            phrases: ["Import study material into \(.applicationName)"],
            shortTitle: "Import Material",
            systemImageName: "doc.badge.plus"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .navy }
}

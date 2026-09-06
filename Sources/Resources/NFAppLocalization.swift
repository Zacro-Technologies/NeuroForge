import Foundation

/// Keeps test-host preferences in a disposable domain, including @AppStorage
/// and compatibility helpers that otherwise default to the learner's domain.
enum NFAppPreferenceScope {
    private static let processID = UUID().uuidString
    static var testSuiteName: String? {
        #if DEBUG
        guard NFUITestLaunchConfiguration.isEnabled else { return nil }
        return "com.zacrotech.NeuroForge.ui-testing.\(NFUITestLaunchConfiguration.persistentRunID?.uuidString ?? processID)"
        #else
        return nil
        #endif
    }
    static var defaults: UserDefaults {
        guard let name = testSuiteName else { return .standard }
        guard let defaults = UserDefaults(suiteName: name) else {
            preconditionFailure("Unable to initialize isolated test preferences.")
        }
        return defaults
    }
}

/// Resolves dynamic copy that is materialized as `String` before SwiftUI sees it.
/// Direct SwiftUI literals use the view's locale environment; computed model and
/// status strings use this mirrored preference so they follow the same in-app
/// English/Japanese choice instead of silently falling back to the process locale.
enum NFAppLocalization {
    enum DurationStyle: Sendable {
        case compact
        case full
    }

    static let preferredLanguageDefaultsKey = "nf.localization.preferred-language.v1"

    static var preferredLocale: Locale {
        locale(identifier: preferredLanguageCode)
    }

    static var preferredLanguageCode: String {
        // Process-only command-line overrides remain supported without reading
        // or mutating the production persistent domain in a test process.
        if let argument = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[preferredLanguageDefaultsKey] as? String {
            return normalizedLanguageCode(argument)
        }
        if let stored = NFAppPreferenceScope.defaults.string(forKey: preferredLanguageDefaultsKey) {
            return normalizedLanguageCode(stored)
        }
        return normalizedLanguageCode(Locale.current.identifier)
    }

    static func locale(identifier: String) -> Locale {
        Locale(identifier: normalizedLanguageCode(identifier))
    }

    static func setPreferredLanguageCode(_ identifier: String) {
        NFAppPreferenceScope.defaults.set(
            normalizedLanguageCode(identifier),
            forKey: preferredLanguageDefaultsKey
        )
    }

    /// Resolves both the catalog language and interpolation formatting for an
    /// explicit app locale. Foundation's `locale:` argument formats values but
    /// does not by itself override the bundle's selected localization.
    static func localized(
        _ value: String.LocalizationValue,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main,
        comment: StaticString? = nil
    ) -> String {
        let localizedBundle = localizationBundle(for: locale, in: bundle)
        if let comment {
            return String(
                localized: value,
                bundle: localizedBundle,
                locale: locale,
                comment: comment
            )
        }
        return String(localized: value, bundle: localizedBundle, locale: locale)
    }

    static func localizationBundle(
        for locale: Locale,
        in bundle: Bundle = .main
    ) -> Bundle {
        let languageCode = normalizedLanguageCode(locale.identifier)
        guard let path = bundle.path(forResource: languageCode, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return bundle
        }
        return localizedBundle
    }

    /// Resolves a runtime catalog key for copy stored in model tables or passed
    /// through custom `String`-taking view components. SwiftUI extracts direct
    /// literals automatically, while these keys are registered explicitly in
    /// `NFManualLocalizationInventory`.
    static func localizedCatalogValue(
        _ key: String,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        let localizedBundle = localizationBundle(for: locale, in: bundle)
        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func formattedAnswerCount(
        _ count: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        formattedCount(max(0, count), singular: "1 answer", plural: "\(max(0, count)) answers", locale: locale, bundle: bundle)
    }

    static func formattedScoredAnswerCount(
        _ count: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        formattedCount(max(0, count), singular: "1 scored answer", plural: "\(max(0, count)) scored answers", locale: locale, bundle: bundle)
    }

    static func formattedPersonalAnswerCount(
        _ count: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        formattedCount(max(0, count), singular: "1 personal answer", plural: "\(max(0, count)) personal answers", locale: locale, bundle: bundle)
    }

    static func formattedIndividualAnswerCount(
        _ count: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        formattedCount(max(0, count), singular: "1 individual answer", plural: "\(max(0, count)) individual answers", locale: locale, bundle: bundle)
    }

    static func formattedItemCount(
        _ count: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        formattedCount(max(0, count), singular: "1 item", plural: "\(max(0, count)) items", locale: locale, bundle: bundle)
    }

    static func formattedChapterCount(
        _ count: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        formattedCount(max(0, count), singular: "1 chapter", plural: "\(max(0, count)) chapters", locale: locale, bundle: bundle)
    }

    static func formattedQuestionCount(
        _ count: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        formattedCount(max(0, count), singular: "1 question", plural: "\(max(0, count)) questions", locale: locale, bundle: bundle)
    }

    static func formattedQuestionRange(
        _ first: Int,
        _ second: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        let lower = max(0, min(first, second))
        let upper = max(0, max(first, second))
        guard lower != upper else {
            return formattedQuestionCount(lower, locale: locale, bundle: bundle)
        }
        return localized(
            "\(lower)–\(upper) questions",
            locale: locale,
            bundle: bundle,
            comment: "Range of question counts."
        )
    }

    static func formattedReturnedQuestionCount(
        actual: Int,
        requested: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        let actualText = formattedQuestionCount(actual, locale: locale, bundle: bundle)
        let requestedText = formattedQuestionCount(requested, locale: locale, bundle: bundle)
        return localized(
            "Returned \(actualText) of \(requestedText) requested.",
            locale: locale,
            bundle: bundle,
            comment: "Question-writer validation count mismatch."
        )
    }

    static func formattedPracticeQuestionsReady(
        _ count: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        formattedCount(
            max(0, count),
            singular: "1 practice question ready",
            plural: "\(max(0, count)) practice questions ready",
            locale: locale,
            bundle: bundle
        )
    }

    static func formattedDistinctSourceQuestionSupport(
        _ count: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        formattedCount(
            max(0, count),
            singular: "This source supported 1 distinct question without repeats. Add more prose for a longer set.",
            plural: "This source supported \(max(0, count)) distinct questions without repeats. Add more prose for a longer set.",
            locale: locale,
            bundle: bundle
        )
    }

    static func formattedReadySectionCount(
        _ count: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        formattedCount(max(0, count), singular: "1 section ready", plural: "\(max(0, count)) sections ready", locale: locale, bundle: bundle)
    }

    static func formattedEligibleAnswerCount(
        _ count: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        formattedCount(max(0, count), singular: "1 eligible answer", plural: "\(max(0, count)) eligible answers", locale: locale, bundle: bundle)
    }

    static func formattedAnswerRequirement(
        completed: Int,
        required: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        let completed = max(0, completed)
        let required = max(0, required)
        return formattedCount(
            required,
            singular: "\(completed) of 1 required answer",
            plural: "\(completed) of \(required) required answers",
            locale: locale,
            bundle: bundle
        )
    }

    static func formattedAnnotationCount(_ count: Int, locale: Locale = preferredLocale, bundle: Bundle = .main) -> String {
        formattedCount(max(0, count), singular: "1 annotation", plural: "\(max(0, count)) annotations", locale: locale, bundle: bundle)
    }

    static func formattedCharacterCount(_ count: Int, locale: Locale = preferredLocale, bundle: Bundle = .main) -> String {
        formattedCount(max(0, count), singular: "1 character", plural: "\(max(0, count)) characters", locale: locale, bundle: bundle)
    }

    static func formattedCharactersRemaining(_ count: Int, locale: Locale = preferredLocale, bundle: Bundle = .main) -> String {
        formattedCount(max(0, count), singular: "1 character remains.", plural: "\(max(0, count)) characters remain.", locale: locale, bundle: bundle)
    }

    static func formattedCharactersOverLimit(_ count: Int, locale: Locale = preferredLocale, bundle: Bundle = .main) -> String {
        formattedCount(max(0, count), singular: "1 character over the limit.", plural: "\(max(0, count)) characters over the limit.", locale: locale, bundle: bundle)
    }

    static func formattedColumnCount(_ count: Int, locale: Locale = preferredLocale, bundle: Bundle = .main) -> String {
        formattedCount(max(0, count), singular: "1 column", plural: "\(max(0, count)) columns", locale: locale, bundle: bundle)
    }

    static func formattedDetectedColumnCount(_ count: Int, locale: Locale = preferredLocale, bundle: Bundle = .main) -> String {
        formattedCount(max(0, count), singular: "1 detected column", plural: "\(max(0, count)) detected columns", locale: locale, bundle: bundle)
    }

    static func formattedDataRowCount(_ count: Int, locale: Locale = preferredLocale, bundle: Bundle = .main) -> String {
        formattedCount(max(0, count), singular: "1 data row", plural: "\(max(0, count)) data rows", locale: locale, bundle: bundle)
    }

    static func formattedValueCount(_ count: Int, locale: Locale = preferredLocale, bundle: Bundle = .main) -> String {
        formattedCount(max(0, count), singular: "1 value", plural: "\(max(0, count)) values", locale: locale, bundle: bundle)
    }

    static func formattedDistinctValueCount(_ count: Int, locale: Locale = preferredLocale, bundle: Bundle = .main) -> String {
        formattedCount(max(0, count), singular: "1 distinct value", plural: "\(max(0, count)) distinct values", locale: locale, bundle: bundle)
    }

    static func formattedActiveDayCount(_ count: Int, locale: Locale = preferredLocale, bundle: Bundle = .main) -> String {
        formattedCount(max(0, count), singular: "1 active day", plural: "\(max(0, count)) active days", locale: locale, bundle: bundle)
    }

    static func formattedHintCount(_ count: Int, locale: Locale = preferredLocale, bundle: Bundle = .main) -> String {
        formattedCount(max(0, count), singular: "1 hint", plural: "\(max(0, count)) hints", locale: locale, bundle: bundle)
    }

    static func formattedReportCount(_ count: Int, locale: Locale = preferredLocale, bundle: Bundle = .main) -> String {
        formattedCount(max(0, count), singular: "1 report", plural: "\(max(0, count)) reports", locale: locale, bundle: bundle)
    }

    static func formattedRecordCount(_ count: Int, locale: Locale = preferredLocale, bundle: Bundle = .main) -> String {
        formattedCount(max(0, count), singular: "1 record", plural: "\(max(0, count)) records", locale: locale, bundle: bundle)
    }

    static func formattedResponseCount(_ count: Int, locale: Locale = preferredLocale, bundle: Bundle = .main) -> String {
        formattedCount(max(0, count), singular: "1 response", plural: "\(max(0, count)) responses", locale: locale, bundle: bundle)
    }

    static func formattedChunkCount(_ count: Int, locale: Locale = preferredLocale, bundle: Bundle = .main) -> String {
        formattedCount(max(0, count), singular: "1 citation-stable chunk", plural: "\(max(0, count)) citation-stable chunks", locale: locale, bundle: bundle)
    }

    static func formattedEvidenceItemCount(_ count: Int, locale: Locale = preferredLocale, bundle: Bundle = .main) -> String {
        formattedCount(max(0, count), singular: "1 evidence item", plural: "\(max(0, count)) evidence items", locale: locale, bundle: bundle)
    }

    static func formattedExcludedPrivateNoteWarning(
        _ count: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        formattedCount(
            max(0, count),
            singular: "1 private progress note was intentionally excluded when this backup was created and cannot be restored from it.",
            plural: "\(max(0, count)) private progress notes were intentionally excluded when this backup was created and cannot be restored from it.",
            locale: locale,
            bundle: bundle
        )
    }

    static func formattedQueuedResponseRecovery(
        _ count: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        formattedCount(
            max(0, count),
            singular: "1 response remains queued locally. Keep the app installed and export recovery data before troubleshooting storage.",
            plural: "\(max(0, count)) responses remain queued locally. Keep the app installed and export recovery data before troubleshooting storage.",
            locale: locale,
            bundle: bundle
        )
    }

    static func formattedAttemptCount(
        _ count: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        formattedCount(max(0, count), singular: "1 attempt", plural: "\(max(0, count)) attempts", locale: locale, bundle: bundle)
    }

    static func formattedMinutes(
        _ value: Int,
        style: DurationStyle = .full,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        let value = max(0, value)
        switch style {
        case .compact:
            return localized(
                "\(value) min",
                locale: locale,
                bundle: bundle,
                comment: "Compact duration in minutes."
            )
        case .full where value == 1:
            return localized(
                "1 minute",
                locale: locale,
                bundle: bundle,
                comment: "Singular duration in minutes."
            )
        case .full:
            return localized(
                "\(value) minutes",
                locale: locale,
                bundle: bundle,
                comment: "Duration in minutes."
            )
        }
    }

    static func formattedMaximumMinutesEach(
        _ value: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        let duration = formattedMinutes(value, style: .compact, locale: locale, bundle: bundle)
        return localized(
            "Up to \(duration) each",
            locale: locale,
            bundle: bundle,
            comment: "Maximum compact duration for each item in a group."
        )
    }

    static func formattedNextBlock(
        title: String,
        minutes: Int,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        let duration = formattedMinutes(minutes, style: .compact, locale: locale, bundle: bundle)
        return localized(
            "Next: \(title) · \(duration)",
            locale: locale,
            bundle: bundle,
            comment: "Session-summary next step with a localized title and compact duration."
        )
    }

    static func formattedDate(
        _ value: Date,
        date: Date.FormatStyle.DateStyle,
        time: Date.FormatStyle.TimeStyle,
        locale: Locale = preferredLocale
    ) -> String {
        Date.FormatStyle(date: date, time: time)
            .locale(locale)
            .format(value)
    }

    static func formattedMinuteRange(
        _ first: Int,
        _ second: Int,
        style: DurationStyle = .full,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        let lower = max(0, min(first, second))
        let upper = max(0, max(first, second))
        guard lower != upper else {
            return formattedMinutes(lower, style: style, locale: locale, bundle: bundle)
        }
        switch style {
        case .compact:
            return localized(
                "\(lower)–\(upper) min",
                locale: locale,
                bundle: bundle,
                comment: "Compact duration range in minutes."
            )
        case .full:
            return localized(
                "\(lower)–\(upper) minutes",
                locale: locale,
                bundle: bundle,
                comment: "Duration range in minutes."
            )
        }
    }

    static func formattedSeconds(
        _ value: Double,
        style: DurationStyle = .full,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        let value = max(0, value)
        let formatted = value.formatted(
            .number
                .precision(.fractionLength(0...1))
                .locale(locale)
        )
        switch style {
        case .compact:
            return localized(
                "\(formatted) s",
                locale: locale,
                bundle: bundle,
                comment: "Compact duration in seconds."
            )
        case .full where abs(value - 1) < 0.000_001:
            return localized(
                "1 second",
                locale: locale,
                bundle: bundle,
                comment: "Singular duration in seconds."
            )
        case .full:
            return localized(
                "\(formatted) seconds",
                locale: locale,
                bundle: bundle,
                comment: "Duration in seconds."
            )
        }
    }

    static func formattedSecondRange(
        _ first: Double,
        _ second: Double,
        style: DurationStyle = .full,
        locale: Locale = preferredLocale,
        bundle: Bundle = .main
    ) -> String {
        let lower = max(0, min(first, second))
        let upper = max(0, max(first, second))
        guard abs(lower - upper) >= 0.000_001 else {
            return formattedSeconds(lower, style: style, locale: locale, bundle: bundle)
        }
        let formatStyle = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0...1))
            .locale(locale)
        let lowerText = lower.formatted(formatStyle)
        let upperText = upper.formatted(formatStyle)
        switch style {
        case .compact:
            return localized(
                "\(lowerText)–\(upperText) s",
                locale: locale,
                bundle: bundle,
                comment: "Compact duration range in seconds."
            )
        case .full:
            return localized(
                "\(lowerText)–\(upperText) seconds",
                locale: locale,
                bundle: bundle,
                comment: "Duration range in seconds."
            )
        }
    }

    private static func formattedCount(
        _ count: Int,
        singular: String.LocalizationValue,
        plural: String.LocalizationValue,
        locale: Locale,
        bundle: Bundle
    ) -> String {
        localized(count == 1 ? singular : plural, locale: locale, bundle: bundle)
    }

    private static func normalizedLanguageCode(_ identifier: String) -> String {
        identifier
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .hasPrefix("ja") ? "ja" : "en"
    }
}

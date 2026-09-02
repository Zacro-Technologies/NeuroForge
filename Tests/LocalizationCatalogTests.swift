import Foundation
import XCTest

@testable import NeuroForge

final class LocalizationCatalogTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testEveryExtractedProductionKeyIsCataloged() throws {
        let appKeys = try extractedKeys(in: repositoryRoot.appending(path: "Sources"))
        let widgetKeys = try extractedKeys(
            in: repositoryRoot.appending(path: "Widgets"),
            excluding: ["Localizable.xcstrings"]
        )

        let appCatalogKeys = try catalogKeys(at: repositoryRoot.appending(path: "Sources/Resources/Localizable.xcstrings"))
        let widgetCatalogKeys = try catalogKeys(at: repositoryRoot.appending(path: "Widgets/Localizable.xcstrings"))

        XCTAssertTrue(
            appKeys.isSubset(of: appCatalogKeys),
            "App catalog is missing extracted keys: \(appKeys.subtracting(appCatalogKeys).sorted())"
        )
        XCTAssertTrue(
            widgetKeys.isSubset(of: widgetCatalogKeys),
            "Widget catalog is missing extracted keys: \(widgetKeys.subtracting(widgetCatalogKeys).sorted())"
        )
    }

    func testEveryTranslatableCatalogEntryHasJapaneseAndMatchingPlaceholders() throws {
        let catalogs = [
            repositoryRoot.appending(path: "Sources/Resources/Localizable.xcstrings"),
            repositoryRoot.appending(path: "Sources/Resources/AppShortcuts.xcstrings"),
            repositoryRoot.appending(path: "Widgets/Localizable.xcstrings")
        ]

        for catalogURL in catalogs {
            let root = try catalogObject(at: catalogURL)
            XCTAssertEqual(root["sourceLanguage"] as? String, "en", catalogURL.path)
            let strings = try XCTUnwrap(root["strings"] as? [String: Any])
            for key in strings.keys.sorted() {
                let entry = try XCTUnwrap(strings[key] as? [String: Any])
                if entry["shouldTranslate"] as? Bool == false { continue }
                let localizations = entry["localizations"] as? [String: Any]
                let sourceValues = try XCTUnwrap(
                    localizedValues(in: localizations?["en"], fallback: key)
                )
                let japaneseValues = try XCTUnwrap(
                    localizedValues(in: localizations?["ja"]),
                    "Missing Japanese draft for '\(key)' in \(catalogURL.lastPathComponent)"
                )
                XCTAssertFalse(japaneseValues.isEmpty)
                XCTAssertTrue(
                    japaneseValues.allSatisfy {
                        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                )
                XCTAssertEqual(
                    sourceValues.flatMap(placeholderSignature).sorted(),
                    japaneseValues.flatMap(placeholderSignature).sorted(),
                    "Placeholder mismatch for '\(key)' in \(catalogURL.lastPathComponent)"
                )
                XCTAssertFalse(
                    sourceValues.contains(where: { $0.contains("%arg") }),
                    "Lossy compiler placeholder in source for '\(key)'"
                )
                XCTAssertFalse(
                    japaneseValues.contains(where: { $0.contains("%arg") }),
                    "Lossy compiler placeholder in Japanese for '\(key)'"
                )
            }
        }
    }

    func testCurrentComputedQuestionWriterAndSettingsKeysAreManuallyInventoriedAndCataloged() throws {
        let keys = [
            "Add Question Writer Shortcut",
            "Creating questions…",
            "Question Writer",
            "Use a Shortcut you control. ChatGPT is recommended.",
            "Use Question Writer Shortcut",
            "Question Writer selected",
            "Question Writer unavailable",
            "Offline authoring",
            "Question Writer is selected. Its availability is checked when you create a set; if the Shortcut is missing or changed, reinstall it or create offline.",
            "Add or reinstall Question Writer",
            "Shortcuts lists it as NeuroForge Private Authoring. After adding it, choose ChatGPT in its Use Model action. You can choose another available model; NeuroForge cannot verify which provider you select.",
            "Question sets are created offline.",
            "Practice Studio creates question sets offline.",
            "Question Writer will create a tailored set through your user-configured Shortcut. ChatGPT is recommended.",
            "Question Writer can use up to four excerpts you approve to create source-linked practice.",
            "Send selected excerpts to Question Writer?",
            "Send excerpts and create",
            "Selected sources: %@. NeuroForge will choose and send at most four excerpts (1,600 characters each; 4,800 total) through your user-configured Shortcut. ChatGPT is recommended. Original files remain on this device.",
            "No usable excerpts were found in the selected source. Choose another ready source and try again.",
            "Question Writer Shortcut",
            "Earlier Apple Intelligence Shortcut",
            "The Question Writer Shortcut is not available in this build.",
            "Question Writer needs explicit permission for every selected source. You can create this set offline instead.",
            "This question request expired. Return to NeuroForge and try again.",
            "The generated questions could not be used. Try again.",
            "Created through your Question Writer Shortcut.",
            "Your Question Writer Shortcut created this set from approved excerpts. NeuroForge checked its structure, citation links, response format, and math formatting; the reference remains model-generated.",
            "Your Question Writer Shortcut created this set. NeuroForge checked its structure, topic relevance, response format, and math formatting.",
            "This question set passed NeuroForge’s local checks.",
            "Question Writer is off in Settings. Offline question writing remains available.",
            "How NeuroForge stores and uses your data.",
            "When enabled, NeuroForge sends a question brief to the user-owned Shortcut. ChatGPT is recommended for its Use Model action, but you can choose or edit the provider and NeuroForge cannot verify that choice. Imported sources default to Offline only. You must choose Question Writer + offline for a source before its excerpts are eligible, and NeuroForge asks again before every run. It sends at most four excerpts, no more than 1,600 characters each or 4,800 characters total. Original files remain local. Returned questions are checked on this device, and offline question writing remains available.",
            "Selected files are copied into app-managed storage and are never executed. OCR runs on the device when you request it for a scanned PDF. The Question Writer Shortcut receives only bounded excerpts from sources you approve for that run, never the original file. A document original syncs to iCloud only when you enable sync for that document. Spotlight indexing is optional.",
            "NeuroForge has no advertising or analytics service and does not sell your data. Data leaves the app when you share or export it, enable iCloud sync, or approve sharing a question brief and bounded excerpts from selected sources with the Question Writer Shortcut. Private progress notes are exported only when you include them.",
            "Get Question Writer Brief",
            "Gets one expiring NeuroForge question brief for the Use Model action in your Shortcut.",
            "Submit Question Writer Result",
            "Checks a Question Writer response and returns it to NeuroForge for local review.",
            "Question Writer Output",
            "The structured text returned by the Use Model action in Shortcuts.",
            "Question Writer can use bounded excerpts from this format. Source review remains local.",
            "Offline question sets need complete prose statements. Use Source review for this format.",
            "Store the original in your private iCloud. The extracted index stays local except for bounded excerpts you explicitly approve for Question Writer.",
            "Create questions",
            "Question privacy",
            "Choose how this source may be used to create questions.",
            "Question use",
            "Question Writer + offline",
            "Offline only",
            "Source review only",
            "Question Writer still asks before every run and sends only bounded excerpts. The original file remains local.",
            "Text from this source never enters Question Writer. Offline recall questions remain available when prose is detected.",
            "Question authoring does not use this source. Source review and browsing remain available.",
            "A selected source is set to Source review only. Change its Question privacy setting before creating questions.",
            "Choose a regular file rather than a folder, package, or link.",
            "This file type is not supported for local import.",
            "This file is larger than the 50 MB local import limit.",
            "Local OCR is available for PDFs and supported images.",
            "The image could not be opened for local OCR.",
            "Page %lld could not be rendered for local OCR.",
            "The image could not be rendered safely for local OCR.",
            "Vision did not find readable text. Try a clearer image or an exported text-based copy.",
            "Answer from memory. You will choose confidence before seeing the reference.",
            "Compare your answer with the reference, then rate the match.",
            "Save self-check",
            "iCloud sync setting not saved",
            "Your previous setting is unchanged. Try again after freeing local storage."
        ]
        let inventory = try String(
            contentsOf: repositoryRoot.appending(path: "Sources/Resources/NFManualLocalizationInventory.swift"),
            encoding: .utf8
        )
        let catalog = try catalogKeys(
            at: repositoryRoot.appending(path: "Sources/Resources/Localizable.xcstrings")
        )
        for key in keys {
            XCTAssertTrue(inventory.contains(key), "Missing manual inventory key: \(key)")
            XCTAssertTrue(catalog.contains(key), "Missing catalog key: \(key)")
        }
    }

    func testNewFirstRunAndQuestionWriterJourneysHaveRealJapaneseCopy() throws {
        let keys = [
            "Build an all-round STEM toolkit.",
            "Train six practical abilities through short daily circuits, then apply them across the subjects you care about.",
            "Six connected abilities",
            "Number sense, quantitative thinking, spatial reasoning, scientific evidence, logic and debugging, and research recall.",
            "One adaptive daily circuit",
            "Recall, practice, apply, and reflect in a circuit that fits the time and energy you have.",
            "Progress without punishment",
            "Completed practice builds momentum. Rest days and lower-energy sessions never erase what you have earned.",
            "Shape your balanced practice",
            "Your circuit",
            "Your routine keeps broad STEM coverage over time. Choose contexts and emphasis areas to make it yours.",
            "STEM contexts",
            "Choose the subjects that should frame examples. They do not limit the abilities you train.",
            "Emphasis areas",
            "Choose what should receive extra attention. The full STEM foundation stays in your training mix.",
            "Set your daily circuit",
            "Your rhythm",
            "Choose a length and pace you can sustain. You can adjust either later.",
            "Circuit length",
            "Pace",
            "Start with a skill check",
            "Open the Forge",
            "Question sets",
            "Browse all",
            "Search topics and fields",
            "Create practice for any topic",
            "Create a question set",
            "Start with a question set",
            "Customize",
            "Use your material",
            "Create your set",
            "Create %lld questions",
            "Use Question Writer Shortcut",
            "Use a Shortcut you control. ChatGPT is recommended.",
            "Add Question Writer Shortcut",
            "Question Writer selected",
            "Send selected excerpts to Question Writer?",
            "Send excerpts and create",
            "Question Writer can use bounded excerpts from this format. Source review remains local.",
            "Offline question sets need complete prose statements. Use Source review for this format.",
            "Store the original in your private iCloud. The extracted index stays local except for bounded excerpts you explicitly approve for Question Writer.",
            "Create questions",
            "Question privacy",
            "Question Writer + offline",
            "Offline only",
            "Source review only",
            "Question Writer still asks before every run and sends only bounded excerpts. The original file remains local.",
            "Text from this source never enters Question Writer. Offline recall questions remain available when prose is detected.",
            "Question authoring does not use this source. Source review and browsing remain available.",
            "Import local notes, web or rich text, data, notebooks, code, tables, PDFs, or images.",
            "Import regular files up to 50 MB. Code and structured data are read as text and never run. PDFs stay on device; scanned PDFs use local OCR only when you choose it, while images use local OCR during import."
        ]
        let root = try catalogObject(
            at: repositoryRoot.appending(path: "Sources/Resources/Localizable.xcstrings")
        )
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])

        for key in keys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            let japanese = try XCTUnwrap(
                localizedValues(in: localizations["ja"]),
                "Missing Japanese localization for '\(key)'"
            )
            XCTAssertTrue(
                japanese.allSatisfy(containsJapaneseScript),
                "Japanese copy is not meaningfully localized for '\(key)': \(japanese)"
            )
        }
    }

    func testRemovedNativeAndObsoleteConsentCopyIsAbsentFromShippingCatalog() throws {
        let root = try catalogObject(
            at: repositoryRoot.appending(path: "Sources/Resources/Localizable.xcstrings")
        )
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        let staleKeys = strings.keys.filter { key in
            (key.localizedCaseInsensitiveContains("Apple Intelligence")
                && key != "Earlier Apple Intelligence Shortcut")
                || key.localizedCaseInsensitiveContains("Private Cloud Compute")
                || key.localizedCaseInsensitiveContains("on-device model")
                || key.localizedCaseInsensitiveContains("Foundation Models")
                || key == "On-device Foundation Model"
                || key == "Forge offline"
                || key == "Forge offline instead"
                || key == "Forge with AI"
        }
        let removedJourneyKeys = [
            "Question Writer ready",
            "Question Writer setup needed",
            "Shortcut configured",
            "Ready to verify",
            "Send selected excerpts to your Shortcut?",
            "Include selected excerpts?",
            "Add Private Authoring Shortcut",
            "Use my Private Authoring Shortcut by default",
            "Selected excerpts will be included in this set.",
            "Apple Intelligence will turn the selected material into a tailored question set.",
            "The Shortcut did not return in time. Retry or forge offline.",
            "Add Question Writer once for topic sets. Document sets stay local.",
            "Add Question Writer once. In Shortcuts, it appears as NeuroForge Private Authoring.",
            "Add the Shortcut once. Future sets will use Apple Intelligence automatically.",
            "Apple Intelligence",
            "Apple Intelligence Shortcut",
            "Apple Intelligence is off in Settings.",
            "Apple Intelligence is off in Settings. Offline question writing remains available.",
            "Apple Intelligence will create a tailored set for this topic.",
            "Created with Apple Intelligence.",
            "Practice Studio uses your Apple Intelligence Shortcut by default.",
            "Shortcuts could not be opened. Offline authoring remains available.",
            "Shortcuts lists it as NeuroForge Private Authoring.",
            "Store the original in your private iCloud. Extracted text and generated practice stay on this device.",
            "The Apple Intelligence Shortcut is not available in this build.",
            "The Shortcut did not finish. Check that its two NeuroForge actions surround Apple Intelligence Use Model, then try again.",
            "Topic sets use Question Writer; document sets stay local.",
            "Use Apple Intelligence",
            "Use Apple Intelligence for richer question sets, or keep authoring offline.",
            "Use Apple Intelligence for topic sets; document sets stay local.",
            "When enabled, NeuroForge sends a question brief to the user-owned Shortcut. ChatGPT is recommended for its Use Model action, but you can choose or edit the provider and NeuroForge cannot verify that choice. For each study-material run, NeuroForge identifies the selected sources and asks before sharing bounded excerpts from them. It sends at most four excerpts, no more than 1,600 characters each or 4,800 characters total. Original files remain local. Returned questions are checked on this device, and offline question writing remains available.",
            "When enabled, NeuroForge sends a topic and question brief to your installed Question Writer Shortcut. Imported material is not included; sets created from your documents stay on this device. Returned questions are checked before they appear, and offline question writing remains available.",
            "Your Apple Intelligence Shortcut created this set. NeuroForge checked its structure, topic relevance, response format, and math formatting."
        ]

        XCTAssertEqual(staleKeys, [], "Unreachable native PCC copy remains cataloged: \(staleKeys.sorted())")
        XCTAssertTrue(
            removedJourneyKeys.allSatisfy { strings[$0] == nil },
            "Obsolete route or consent copy remains in the shipping catalog"
        )
        XCTAssertNotNil(
            strings["Earlier Apple Intelligence Shortcut"],
            "The decode-only compatibility label must remain localized"
        )
    }

    func testShortcutPhraseMetadataIsCataloged() throws {
        let sourceURL = repositoryRoot.appending(path: "Sources/Integrations/NeuroForgeIntents.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let expression = try NSRegularExpression(pattern: #"phrases:\s*\[\s*\"([^\"]+)\"\s*\]"#)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let phrases = Set(expression.matches(in: source, range: range).compactMap { match -> String? in
            guard let capture = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[capture]).replacingOccurrences(
                of: #"\(.applicationName)"#,
                with: "${applicationName}"
            )
        })
        let catalog = try catalogKeys(at: repositoryRoot.appending(path: "Sources/Resources/AppShortcuts.xcstrings"))

        XCTAssertEqual(phrases.count, 6, "Unexpected App Shortcut phrase inventory")
        XCTAssertTrue(phrases.isSubset(of: catalog), "Missing shortcut phrases: \(phrases.subtracting(catalog).sorted())")
    }

    func testAppIntentMetadataDoesNotNameApple() throws {
        let sourceURL = repositoryRoot.appending(path: "Sources/Integrations/NeuroForgeIntents.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let expression = try NSRegularExpression(
            pattern: #"description(?:\s*:\s*IntentDescription\?\s*\{\s*|\s*:\s*)\"([^\"]*)\""#
        )
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let descriptions = expression.matches(in: source, range: range).compactMap { match -> String? in
            guard let capture = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[capture])
        }

        XCTAssertFalse(descriptions.isEmpty, "No App Intent descriptions were found")
        XCTAssertEqual(
            descriptions.filter { $0.localizedCaseInsensitiveContains("apple") },
            [],
            "Siri rejects App Intent descriptions containing the word Apple"
        )
    }

    func testDynamicTitlesHonorExplicitAppLocale() {
        let english = TrainingLab.mentalMath.localizedTitle(locale: NFAppLocalization.locale(identifier: "en"))
        let japanese = TrainingLab.mentalMath.localizedTitle(locale: NFAppLocalization.locale(identifier: "ja"))

        XCTAssertEqual(english, "Mental Mathematics")
        XCTAssertEqual(japanese, "メンタル数学")
        XCTAssertNotEqual(english, japanese)
    }

    func testLocaleAwareDateFormattingDiffersAcrossSupportedLanguages() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let english = NFAppLocalization.formattedDate(
            date,
            date: .long,
            time: .omitted,
            locale: NFAppLocalization.locale(identifier: "en")
        )
        let japanese = NFAppLocalization.formattedDate(
            date,
            date: .long,
            time: .omitted,
            locale: NFAppLocalization.locale(identifier: "ja")
        )

        XCTAssertNotEqual(english, japanese)
        XCTAssertTrue(japanese.contains("年") && japanese.contains("月") && japanese.contains("日"))
    }

    func testProductionAvoidsProcessLocaleDateConvenienceFormatting() throws {
        let sources = repositoryRoot.appending(path: "Sources")
        let expression = try NSRegularExpression(pattern: #"\.formatted\s*\(\s*date\s*:"#)
        var violations: [String] = []
        for file in try swiftFiles(in: sources) {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in expression.matches(in: source, range: range) {
                guard let location = Range(match.range, in: source)?.lowerBound else { continue }
                let line = source[..<location].reduce(into: 1) { count, character in
                    if character == "\n" { count += 1 }
                }
                let relativePath = file.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
                violations.append("\(relativePath):\(line)")
            }
        }
        XCTAssertTrue(
            violations.isEmpty,
            "User-facing dates must use NFAppLocalization.formattedDate or an explicit locale-bearing style: \(violations.sorted())"
        )
    }

    func testDeterministicExercisesHonorRequestedJapaneseLocaleAcrossEveryLab() throws {
        for (index, lab) in TrainingLab.allCases.enumerated() {
            let request = NFExerciseGenerationRequest(
                seed: UInt64(7_100 + index),
                index: index,
                lab: lab,
                purpose: .practice,
                localeIdentifier: "ja",
                sourceContext: NFExerciseSourceContext(
                    primaryField: .physics,
                    topic: "orbital dynamics"
                )
            )
            let exercise = try NFFallbackExerciseGenerator.generate(request)

            XCTAssertEqual(exercise.localeIdentifier, "ja")
            XCTAssertTrue(containsJapaneseScript(exercise.title), "Unlocalized title for \(lab.rawValue): \(exercise.title)")
            XCTAssertTrue(containsJapaneseScript(exercise.prompt), "Unlocalized prompt for \(lab.rawValue): \(exercise.prompt)")
            XCTAssertTrue(containsJapaneseScript(exercise.instructions), "Unlocalized instructions for \(lab.rawValue): \(exercise.instructions)")
            XCTAssertTrue(
                exercise.strategies.allSatisfy {
                    containsJapaneseScript($0.title)
                        && containsJapaneseScript($0.summary)
                        && $0.orderedSteps.allSatisfy(containsJapaneseScript)
                        && containsJapaneseScript($0.whenToUse)
                },
                "Unlocalized strategy copy for \(lab.rawValue): \(exercise.strategies)"
            )
            XCTAssertTrue(
                containsJapaneseScript(exercise.feedback.correctTitle)
                    && containsJapaneseScript(exercise.feedback.correctExplanation)
                    && containsJapaneseScript(exercise.feedback.retryTitle)
                    && containsJapaneseScript(exercise.feedback.retryExplanation),
                "Unlocalized feedback for \(lab.rawValue): \(exercise.feedback)"
            )
        }
    }

    func testJapaneseLocalizationDoesNotChangeDeterministicAuthorityTopology() throws {
        for (index, lab) in TrainingLab.allCases.enumerated() {
            func exercise(localeIdentifier: String) throws -> NFExercise {
                try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
                    seed: UInt64(8_100 + index),
                    index: index,
                    lab: lab,
                    purpose: .practice,
                    localeIdentifier: localeIdentifier,
                    sourceContext: NFExerciseSourceContext(primaryField: .engineering)
                ))
            }

            let english = try exercise(localeIdentifier: "en")
            let japanese = try exercise(localeIdentifier: "ja")
            XCTAssertEqual(english.id, japanese.id, lab.rawValue)
            XCTAssertEqual(english.templateID, japanese.templateID, lab.rawValue)
            XCTAssertEqual(english.templateFamily, japanese.templateFamily, lab.rawValue)
            XCTAssertEqual(english.tags, japanese.tags, lab.rawValue)
            XCTAssertEqual(
                authorityTopology(english.interaction),
                authorityTopology(japanese.interaction),
                "Localization changed answer authority for \(lab.rawValue)"
            )
            XCTAssertEqual(
                Set(english.feedback.errorExplanations.keys),
                Set(japanese.feedback.errorExplanations.keys),
                "Localization changed stable error codes for \(lab.rawValue)"
            )
        }
    }

    func testJapaneseMentalMathDomainPacksLocalizeVisibleCopyAndPreserveStableIDs() {
        let english = NFMentalMathDomainPackCatalog.packs(localeIdentifier: "en")
        let japanese = NFMentalMathDomainPackCatalog.packs(localeIdentifier: "ja")

        XCTAssertEqual(english.map(\.id), japanese.map(\.id))
        XCTAssertEqual(english.map { $0.templates.map(\.id) }, japanese.map { $0.templates.map(\.id) })
        for pack in japanese {
            XCTAssertTrue(containsJapaneseScript(pack.title), pack.title)
            XCTAssertTrue(pack.templates.allSatisfy {
                containsJapaneseScript($0.contextFrame) && containsJapaneseScript($0.examplePrompt)
            }, "Unlocalized Japanese domain-pack copy in \(pack.id.rawValue)")
            XCTAssertTrue(pack.templates.allSatisfy {
                !$0.operationFamily.isEmpty && !$0.validatorKind.isEmpty
            })
        }
    }

    func testCompositeResponseLabelsLocalizeWithoutChangingCanonicalKeys() {
        let japanese = NFAppLocalization.locale(identifier: "ja")

        XCTAssertEqual(NFEstimateExactContract.estimateKey, "1 · estimate")
        XCTAssertEqual(NFEstimateExactContract.plausibilityKey, "2 · plausibility")
        XCTAssertEqual(NFEstimateExactContract.exactKey, "3 · exact")
        XCTAssertTrue(containsJapaneseScript(
            NFEstimateExactContract.localizedResponseLabel(
                for: NFEstimateExactContract.estimateKey,
                locale: japanese
            )
        ))
        XCTAssertTrue(containsJapaneseScript(
            NFEstimateExactContract.localizedResponseLabel(
                for: NFEstimateExactContract.plausibilityKey,
                locale: japanese
            )
        ))
        XCTAssertTrue(containsJapaneseScript(
            NFEstimateExactContract.localizedResponseLabel(
                for: NFEstimateExactContract.exactKey,
                locale: japanese
            )
        ))
    }

    func testCentralizedCountAndDurationCopyHandlesSingularPluralRangesAndLocales() {
        let english = NFAppLocalization.locale(identifier: "en")
        let japanese = NFAppLocalization.locale(identifier: "ja")

        XCTAssertEqual(NFAppLocalization.formattedAnswerCount(0, locale: english), "0 answers")
        XCTAssertEqual(NFAppLocalization.formattedAnswerCount(1, locale: english), "1 answer")
        XCTAssertEqual(NFAppLocalization.formattedAnswerCount(2, locale: english), "2 answers")
        XCTAssertEqual(NFAppLocalization.formattedItemCount(1, locale: english), "1 item")
        XCTAssertEqual(NFAppLocalization.formattedChapterCount(2, locale: english), "2 chapters")
        XCTAssertEqual(NFAppLocalization.formattedQuestionCount(1, locale: english), "1 question")
        XCTAssertEqual(NFAppLocalization.formattedQuestionRange(4, 6, locale: english), "4–6 questions")
        XCTAssertEqual(
            NFAppLocalization.formattedReturnedQuestionCount(actual: 1, requested: 2, locale: english),
            "Returned 1 question of 2 questions requested."
        )
        XCTAssertEqual(NFAppLocalization.formattedChunkCount(1, locale: english), "1 citation-stable chunk")
        XCTAssertEqual(NFAppLocalization.formattedChunkCount(2, locale: english), "2 citation-stable chunks")
        XCTAssertEqual(NFAppLocalization.formattedEvidenceItemCount(1, locale: english), "1 evidence item")
        XCTAssertEqual(NFAppLocalization.formattedEvidenceItemCount(2, locale: english), "2 evidence items")
        XCTAssertTrue(NFAppLocalization.formattedExcludedPrivateNoteWarning(1, locale: english).hasPrefix("1 private progress note"))
        XCTAssertTrue(NFAppLocalization.formattedExcludedPrivateNoteWarning(2, locale: english).hasPrefix("2 private progress notes"))
        XCTAssertEqual(NFAppLocalization.formattedAttemptCount(2, locale: english), "2 attempts")
        XCTAssertEqual(NFAppLocalization.formattedPracticeQuestionsReady(1, locale: english), "1 practice question ready")
        XCTAssertEqual(NFAppLocalization.formattedReadySectionCount(1, locale: english), "1 section ready")
        XCTAssertEqual(NFAppLocalization.formattedEligibleAnswerCount(1, locale: english), "1 eligible answer")
        XCTAssertEqual(NFAppLocalization.formattedAnswerRequirement(completed: 1, required: 1, locale: english), "1 of 1 required answer")
        XCTAssertEqual(NFAppLocalization.formattedAnnotationCount(1, locale: english), "1 annotation")
        XCTAssertEqual(NFAppLocalization.formattedCharacterCount(1, locale: english), "1 character")
        XCTAssertEqual(NFAppLocalization.formattedCharactersRemaining(1, locale: english), "1 character remains.")
        XCTAssertEqual(NFAppLocalization.formattedCharactersOverLimit(1, locale: english), "1 character over the limit.")
        XCTAssertEqual(NFAppLocalization.formattedColumnCount(1, locale: english), "1 column")
        XCTAssertEqual(NFAppLocalization.formattedDetectedColumnCount(1, locale: english), "1 detected column")
        XCTAssertEqual(NFAppLocalization.formattedDataRowCount(1, locale: english), "1 data row")
        XCTAssertEqual(NFAppLocalization.formattedValueCount(1, locale: english), "1 value")
        XCTAssertEqual(NFAppLocalization.formattedDistinctValueCount(1, locale: english), "1 distinct value")
        XCTAssertEqual(NFAppLocalization.formattedActiveDayCount(1, locale: english), "1 active day")
        XCTAssertEqual(NFAppLocalization.formattedHintCount(1, locale: english), "1 hint")
        XCTAssertEqual(NFAppLocalization.formattedReportCount(1, locale: english), "1 report")
        XCTAssertEqual(NFAppLocalization.formattedRecordCount(1, locale: english), "1 record")
        XCTAssertEqual(NFAppLocalization.formattedResponseCount(1, locale: english), "1 response")
        XCTAssertTrue(NFAppLocalization.formattedQueuedResponseRecovery(1, locale: english).hasPrefix("1 response remains"))

        XCTAssertEqual(NFAppLocalization.formattedMinutes(1, locale: english), "1 minute")
        XCTAssertEqual(NFAppLocalization.formattedMinutes(2, locale: english), "2 minutes")
        XCTAssertEqual(NFAppLocalization.formattedMinutes(5, style: .compact, locale: english), "5 min")
        XCTAssertEqual(NFAppLocalization.formattedMinuteRange(4, 6, style: .compact, locale: english), "4–6 min")
        XCTAssertEqual(NFAppLocalization.formattedSeconds(1, locale: english), "1 second")
        XCTAssertEqual(NFAppLocalization.formattedSeconds(2.5, locale: english), "2.5 seconds")
        XCTAssertEqual(NFAppLocalization.formattedSecondRange(3.5, 5, style: .compact, locale: english), "3.5–5 s")
        XCTAssertEqual(NFAppLocalization.formattedMaximumMinutesEach(8, locale: english), "Up to 8 min each")
        XCTAssertEqual(NFAppLocalization.formattedNextBlock(title: "Review", minutes: 1, locale: english), "Next: Review · 1 min")

        XCTAssertTrue(containsJapaneseScript(NFAppLocalization.formattedAnswerCount(2, locale: japanese)))
        XCTAssertEqual(NFAppLocalization.formattedChapterCount(1, locale: japanese), "1章")
        XCTAssertEqual(NFAppLocalization.formattedQuestionRange(4, 6, locale: japanese), "4～6問")
        XCTAssertTrue(containsJapaneseScript(
            NFAppLocalization.formattedReturnedQuestionCount(actual: 1, requested: 2, locale: japanese)
        ))
        XCTAssertTrue(containsJapaneseScript(NFAppLocalization.formattedChunkCount(2, locale: japanese)))
        XCTAssertTrue(containsJapaneseScript(NFAppLocalization.formattedEvidenceItemCount(2, locale: japanese)))
        XCTAssertTrue(containsJapaneseScript(NFAppLocalization.formattedExcludedPrivateNoteWarning(2, locale: japanese)))
        XCTAssertEqual(NFAppLocalization.formattedMinutes(2, locale: japanese), "2分")
        XCTAssertEqual(NFAppLocalization.formattedSecondRange(3.5, 5, style: .compact, locale: japanese), "3.5～5秒")
        XCTAssertTrue(containsJapaneseScript(NFAppLocalization.formattedPracticeQuestionsReady(1, locale: japanese)))
        XCTAssertTrue(containsJapaneseScript(NFAppLocalization.formattedCharacterCount(1, locale: japanese)))
        XCTAssertTrue(containsJapaneseScript(NFAppLocalization.formattedQueuedResponseRecovery(2, locale: japanese)))
    }

    func testPersistedDailyPlanPresentationReprojectsForSelectedLocaleWithoutChangingAuthority() throws {
        let kinds = NFDailyPlanBlockKind.allCases
        let blocks = kinds.enumerated().map { index, kind in
            NFDailyPlanBlock(
                id: "localized-plan-block-\(index)",
                kind: kind,
                lab: kind == .unseenTransfer ? .transfer : .mentalMath,
                targetSkillID: TrainingLab.mentalMath.skillID,
                title: "Persisted English title \(index)",
                detail: "Persisted English detail \(index)",
                minutes: 1,
                reasons: [.reviewDue],
                evidenceClass: .practice,
                priority: nil,
                mechanicID: "stable-mechanic-\(index)",
                timed: false,
                offlineReady: true,
                retentionItemIDs: []
            )
        }
        let canonical = NFCanonicalDailyPlan(
            id: "localized-plan",
            profileID: UUID(uuidString: "A4767F46-03BC-43AE-8261-57742167E7AC")!,
            localDayKey: "2026-08-05@04",
            seed: 42,
            policyVersion: 3,
            requestedMinutes: blocks.count,
            scheduledMinutes: blocks.count,
            blocks: blocks,
            prioritySnapshot: [],
            replacement: nil
        )

        let english = canonical.domainPlan(locale: NFAppLocalization.locale(identifier: "en"))
        let japanese = canonical.domainPlan(locale: NFAppLocalization.locale(identifier: "ja"))

        XCTAssertEqual(english.blocks.map(\.id), japanese.blocks.map(\.id))
        XCTAssertEqual(english.blocks.map(\.mechanicID), japanese.blocks.map(\.mechanicID))
        XCTAssertEqual(canonical.blocks.map(\.title), blocks.map(\.title))
        XCTAssertTrue(japanese.blocks.allSatisfy { containsJapaneseScript($0.title) })
        XCTAssertTrue(japanese.blocks.allSatisfy { containsJapaneseScript($0.detail) })
        XCTAssertTrue(japanese.blocks.allSatisfy { !$0.detail.contains("skill.") })
        XCTAssertNotEqual(english.blocks.map(\.title), japanese.blocks.map(\.title))
        XCTAssertNotEqual(english.blocks.map(\.detail), japanese.blocks.map(\.detail))
    }

    func testRuntimeComputedLocalizationAlwaysUsesTheExplicitAppBundleResolver() throws {
        let sources = repositoryRoot.appending(path: "Sources")
        let allowedDirectFoundationFiles: Set<String> = [
            "NFAppLocalization.swift",
            "NFManualLocalizationInventory.swift"
        ]
        let expression = try NSRegularExpression(
            pattern: #"\bString\s*\(\s*localized\s*:"#
        )
        var violations: [String] = []

        for file in try swiftFiles(in: sources)
        where !allowedDirectFoundationFiles.contains(file.lastPathComponent) {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in expression.matches(in: source, range: range) {
                guard let location = Range(match.range, in: source)?.lowerBound else { continue }
                let line = source[..<location].reduce(into: 1) { count, character in
                    if character == "\n" { count += 1 }
                }
                let relativePath = file.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
                violations.append("\(relativePath):\(line)")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Runtime/computed localization must use NFAppLocalization.localized so the saved in-app language selects the correct .lproj bundle: \(violations.sorted())"
        )
    }

    private func extractedKeys(in directory: URL, excluding: Set<String> = []) throws -> Set<String> {
        let files = try swiftFiles(in: directory).filter { !excluding.contains($0.lastPathComponent) }
        let output = FileManager.default.temporaryDirectory
            .appending(path: "NeuroForge-Localization-Audit-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "xcstringstool", "extract",
            "--SwiftUI",
            "--modern-localizable-strings",
            "--legacy-localizable-strings",
            "--avoid-arg-placeholder",
            "--output-format", "xcstrings",
            "--output-directory", output.path
        ] + files.map(\.path)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "xcstringstool source extraction failed")

        let catalog = output.appending(path: "Localizable.xcstrings")
        guard FileManager.default.fileExists(atPath: catalog.path) else { return [] }
        return try catalogKeys(at: catalog)
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return try enumerator.compactMap { value -> URL? in
            guard let url = value as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: Set(keys)).isRegularFile == true else { return nil }
            return url
        }.sorted { $0.path < $1.path }
    }

    private func catalogKeys(at url: URL) throws -> Set<String> {
        let root = try catalogObject(at: url)
        return Set((try XCTUnwrap(root["strings"] as? [String: Any])).keys)
    }

    private func catalogObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func localizedValues(in localization: Any?, fallback: String? = nil) -> [String]? {
        guard let localization = localization as? [String: Any] else {
            return fallback.map { [$0] }
        }
        if let unit = localization["stringUnit"] as? [String: Any],
           let value = unit["value"] as? String {
            return [value]
        }
        if let set = localization["stringSet"] as? [String: Any],
           let values = set["values"] as? [String] {
            return values
        }
        return fallback.map { [$0] }
    }

    private func placeholderSignature(_ value: String) -> [String] {
        let expression = try! NSRegularExpression(
            pattern: #"%(?:(\d+)\$)?(lld|llu|ld|lu|lf|d|u|f|g|@)|\$\{[A-Za-z0-9_.]+\}"#
        )
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        var implicitPosition = 0
        return expression.matches(in: value, range: range).compactMap { match in
            guard let wholeRange = Range(match.range, in: value) else { return nil }
            let token = String(value[wholeRange])
            if token.hasPrefix("${") { return token }

            implicitPosition += 1
            let explicitPosition = Range(match.range(at: 1), in: value).flatMap {
                Int(value[$0])
            }
            guard let typeRange = Range(match.range(at: 2), in: value) else { return nil }
            return "\(explicitPosition ?? implicitPosition):\(value[typeRange])"
        }.sorted()
    }

    private func containsJapaneseScript(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)
                || (0x3400...0x9FFF).contains(scalar.value)
        }
    }

    private func authorityTopology(_ interaction: NFExerciseInteraction) -> String {
        switch interaction {
        case let .numeric(schema):
            return [
                "numeric",
                schema.answer.authoritativeValue.canonicalString,
                String(schema.answer.unitRequired)
            ].joined(separator: "|")
        case let .singleChoice(schema):
            return [
                "singleChoice",
                schema.correctOptionID,
                schema.options.map { "\($0.id):\($0.distractorCode ?? "")" }.sorted().joined(separator: ",")
            ].joined(separator: "|")
        case let .multipleChoice(schema):
            return [
                "multipleChoice",
                schema.correctOptionIDs.sorted().joined(separator: ","),
                schema.options.map { "\($0.id):\($0.distractorCode ?? "")" }.sorted().joined(separator: ","),
                String(schema.minimumSelections),
                String(schema.maximumSelections)
            ].joined(separator: "|")
        case let .orderedSteps(schema):
            return [
                "orderedSteps",
                schema.steps.map(\.id).sorted().joined(separator: ","),
                schema.correctOrder.joined(separator: ",")
            ].joined(separator: "|")
        case let .shortText(schema):
            let ruleTopology: String = switch schema.scoringRule {
            case let .normalizedExact(acceptedAnswers): "normalizedExact:\(acceptedAnswers.count)"
            case let .requiredTerms(terms, minimumMatches): "requiredTerms:\(terms.count):\(minimumMatches)"
            case let .constrainedConcepts(acceptedAnswers, requiredTerms, minimumMatches, rejectedAssertions):
                "constrainedConcepts:\(acceptedAnswers.count):\(requiredTerms.count):\(minimumMatches):\(rejectedAssertions.count)"
            }
            return "shortText|\(schema.maximumCharacters)|\(ruleTopology)"
        case let .selfCheck(schema):
            return "selfCheck|\(schema.criteria.count)|\(schema.asksForReflection)"
        case let .claimEvidence(schema):
            let claims = schema.claims.map(\.id).sorted().joined(separator: ",")
            let evidence = schema.evidence.map(\.id).sorted().joined(separator: ",")
            let pairs = schema.correctPairs
                .map { "\($0.claimID):\($0.evidenceIDs.sorted().joined(separator: ","))" }
                .sorted()
                .joined(separator: "|")
            return "claimEvidence|\(claims)|\(evidence)|\(pairs)"
        case let .logicState(schema):
            let ruleOptions = schema.ruleOptions
                .map { "\($0.id):\($0.distractorCode ?? "")" }
                .sorted()
                .joined(separator: ",")
            return [
                "logicState",
                schema.initialState.keys.sorted().joined(separator: ","),
                schema.expectedFinalState.keys.sorted().joined(separator: ","),
                String(schema.acceptedEquivalentStates.count),
                ruleOptions,
                schema.expectedViolatedRuleID ?? ""
            ].joined(separator: "|")
        }
    }
}

import XCTest
#if os(iOS)
import UIKit
#endif

@MainActor
final class NavigationSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPrimaryNavigationIsAccessibleAndReachesEveryDestination() {
        let app = XCUIApplication()
        app.launchArguments = launchArguments(skipOnboarding: true)
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(
            element(in: app, identifier: "destination-today").waitForExistence(timeout: 15),
            "The deterministic launch should open the Today destination."
        )

        let destinations = [
            (id: "train", expectedLabel: "Practice"),
            (id: "progress", expectedLabel: "Progress"),
            (id: "library", expectedLabel: "Sources"),
            (id: "settings", expectedLabel: "Settings"),
            (id: "today", expectedLabel: "Today")
        ]

        for destination in destinations {
            let navigation = primaryNavigation(
                in: app,
                destinationID: destination.id,
                expectedLabel: destination.expectedLabel
            )
            XCTAssertTrue(
                navigation.waitForExistence(timeout: 5),
                "Missing primary navigation control for \(destination.expectedLabel)."
            )
            XCTAssertEqual(navigation.label, destination.expectedLabel)
            XCTAssertTrue(navigation.isEnabled)

            navigation.tap()
            XCTAssertTrue(
                element(
                    in: app,
                    identifier: "destination-\(destination.id)"
                ).waitForExistence(timeout: 5),
                "Tapping \(destination.expectedLabel) should reveal its destination."
            )
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "destination-\(destination.id)-en-default"
            capture.lifetime = .keepAlways
            add(capture)
        }
    }

    func testOnboardingReflowsAtMaximumAccessibilitySizeOnCompactPhone() throws {
        #if os(iOS)
        let app = XCUIApplication()
        app.launchArguments = launchArguments(
            skipOnboarding: false,
            contentSizeCategory: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        )
        app.launch()
        defer { app.terminate() }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15))

        let primaryAction = element(in: app, identifier: "onboarding-primary-action")
        XCTAssertTrue(primaryAction.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(primaryAction.frame.height, 56, "The accessibility-size layout branch must actually be active.")
        XCTAssertTrue(app.staticTexts["Build an all-round STEM toolkit."].exists)
        assertFullyContained(primaryAction, in: window, context: "welcome primary action")
        XCTAssertTrue(primaryAction.isHittable)

        let setup = app.buttons["Set up my practice"]
        XCTAssertTrue(setup.isHittable)
        setup.tap()
        XCTAssertTrue(app.staticTexts["Shape your balanced practice"].waitForExistence(timeout: 5))
        XCTAssertEqual(primaryAction.label, "Continue")
        assertFullyContained(primaryAction, in: window, context: "profile primary action")
        XCTAssertTrue(primaryAction.isHittable)

        primaryAction.tap()
        XCTAssertTrue(app.staticTexts["Set your daily circuit"].waitForExistence(timeout: 5))
        XCTAssertEqual(primaryAction.label, "Start practice")
        assertFullyContained(primaryAction, in: window, context: "routine primary action")
        XCTAssertTrue(primaryAction.isHittable)

        let skillCheck = element(in: app, identifier: "onboarding-skill-check-action")
        XCTAssertTrue(skillCheck.waitForExistence(timeout: 5))
        assertFullyContained(skillCheck, in: window, context: "routine skill-check action")
        XCTAssertTrue(skillCheck.isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "onboarding-en-largest-accessibility"
        capture.lifetime = .keepAlways
        add(capture)
        #else
        throw XCTSkip("Compact iPhone Dynamic Type coverage runs on the iOS UI-test destination.")
        #endif
    }

    func testMentalMathQuickPracticeStartsAUniversalSession() throws {
        #if os(iOS)
        let app = XCUIApplication()
        app.launchArguments = launchArguments(skipOnboarding: true)
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(
            element(in: app, identifier: "destination-today").waitForExistence(timeout: 15)
        )
        let quickPractice = element(in: app, identifier: "quick-practice-mental-math")
        XCTAssertTrue(scrollUntilHittable(quickPractice, in: app), "Mental-math quick practice was not reachable.")
        quickPractice.tap()

        XCTAssertTrue(
            element(in: app, identifier: "universal-session").waitForExistence(timeout: 10),
            "The quick-practice action should present the universal session flow."
        )
        #else
        throw XCTSkip("The compact quick-practice regression runs on the iOS UI-test destination.")
        #endif
    }

    func testDeclinedQuestionWriterHandoffShowsRecoveryWithoutTerminating() throws {
        #if os(iOS)
        let app = XCUIApplication()
        app.launchArguments = launchArguments(skipOnboarding: true) + [
            "-ui-test-verified-question-writer",
            "-ui-test-decline-external-url"
        ]
        app.launch()
        defer { app.terminate() }

        let practiceTab = app.tabBars.buttons["Practice"]
        XCTAssertTrue(practiceTab.waitForExistence(timeout: 15))
        practiceTab.tap()
        XCTAssertTrue(element(in: app, identifier: "destination-train").waitForExistence(timeout: 5))

        let openStudio = element(in: app, identifier: "open-ai-studio")
        XCTAssertTrue(scrollUntilHittable(openStudio, in: app), "AI Studio entry point was not reachable.")
        openStudio.tap()
        XCTAssertTrue(element(in: app, identifier: "ai-studio-root").waitForExistence(timeout: 8))

        let starterSet = app.descendants(matching: .any)
            .matching(identifier: "ai-studio-starter-set")
            .firstMatch
        XCTAssertTrue(starterSet.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollUntilHittable(starterSet, in: app))
        starterSet.tap()

        let generate = element(in: app, identifier: "ai-studio-generate-action")
        XCTAssertTrue(scrollUntilHittable(generate, in: app), "The generate action was not reachable.")
        XCTAssertTrue(generate.isEnabled)
        generate.tap()

        XCTAssertTrue(app.alerts["Questions could not be prepared"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Try again"].exists)
        XCTAssertTrue(app.buttons["Create offline"].exists)
        XCTAssertTrue(app.buttons["Add or reinstall Question Writer"].exists)
        XCTAssertTrue(app.buttons["Dismiss"].exists)

        app.buttons["Dismiss"].tap()
        XCTAssertTrue(
            element(in: app, identifier: "ai-studio-root").waitForExistence(timeout: 5),
            "A declined external handoff must leave AI Studio available for recovery."
        )
        #else
        throw XCTSkip("Question Writer handoff recovery runs on the iOS UI-test destination.")
        #endif
    }

    func testFreshSampleShowsMeaningfulFeedbackBeforeSetup() {
        let app = XCUIApplication()
        app.launchArguments = launchArguments(skipOnboarding: false)
        app.launch()
        defer { app.terminate() }
        let sample = element(in: app, identifier: "onboarding-primary-action")
        XCTAssertTrue(sample.waitForExistence(timeout: 15))
        XCTAssertEqual(sample.label, "Try a sample")
        // A single ordinary-duration touch keeps event delivery observable on
        // the simulator; all application transitions remain strict assertions.
        sample.press(forDuration: 0.15)
        let check = app.buttons["Check answer"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        XCTAssertFalse(check.isEnabled)
        let choice = app.buttons["30 × 6 − 6"]
        XCTAssertTrue(scrollUntilHittable(choice, in: app))
        choice.press(forDuration: 0.15)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: check)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed, "Choosing an answer must enable Check answer.")
        check.press(forDuration: 0.15)
        XCTAssertTrue(app.staticTexts["Correct"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Correct"].isHittable, "The sample must reveal feedback in the visible viewport.")
        XCTAssertTrue(app.staticTexts["30 groups of 6 make 180. Remove one group of 6: 180 − 6 = 174. So 29 × 6 = 30 × 6 − 6."].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "sample-feedback-en-default"
        capture.lifetime = .keepAlways
        add(capture)
        let personalize = app.buttons["Make this fit me"]
        XCTAssertTrue(personalize.isHittable)
        personalize.press(forDuration: 0.15)
        XCTAssertTrue(app.staticTexts["Shape your balanced practice"].waitForExistence(timeout: 5))
    }

    func testSettingsSearchFindsLanguageAndPreservesDestination() {
        let app = XCUIApplication()
        app.launchArguments = launchArguments(skipOnboarding: true)
        app.launch()
        defer { app.terminate() }
        let settings = primaryNavigation(in: app, destinationID: "settings", expectedLabel: "Settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let search = element(in: app, identifier: "settings-search")
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable)
        search.tap()
        #if os(iOS)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Tapping Search settings must focus the search field.")
        #endif
        search.typeText("language")
        XCTAssertTrue(app.buttons["Open accessibility preferences"].waitForExistence(timeout: 5))
        #if os(iOS)
        let dismissKeyboard = app.buttons["settings-search-done"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 5))
        dismissKeyboard.tap()
        #endif
        let today = primaryNavigation(in: app, destinationID: "today", expectedLabel: "Today")
        today.tap()
        XCTAssertTrue(element(in: app, identifier: "destination-today").waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertEqual(search.value as? String, "language")
        XCTAssertTrue(app.buttons["Open accessibility preferences"].exists)
        search.tap()
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "language".count) + "zzzznomatch")
        XCTAssertTrue(element(in: app, identifier: "settings-no-results").waitForExistence(timeout: 5))
        #if os(iOS)
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 5))
        dismissKeyboard.tap()
        #endif
        let clearSearch = app.buttons["Clear search"]
        XCTAssertTrue(scrollUntilHittable(clearSearch, in: app))
        clearSearch.tap()
        XCTAssertFalse(element(in: app, identifier: "settings-no-results").exists)
    }

    func testQuestionThreeDraftAndFeedbackSurviveColdRelaunchInEnglish() throws {
        try exerciseExactRelaunch(language: "en")
    }

    func testQuestionThreeDraftAndFeedbackSurviveColdRelaunchInJapanese() throws {
        try exerciseExactRelaunch(language: "ja")
    }

    func testNestedHistoryDetailAndSourcesKeepTheirOwnPaths() throws {
        #if os(iOS)
        let app = XCUIApplication()
        let runID = UUID().uuidString
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: true, startSession: true) + ["-ui-test-source-document"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(element(in: app, identifier: "universal-session").waitForExistence(timeout: 15))
        let prompt = element(in: app, identifier: "session-prompt").label
        enterNumericAnswer("1", in: app)
        element(in: app, identifier: "session-submit").tap()
        XCTAssertTrue(element(in: app, identifier: "session-next").waitForExistence(timeout: 8))
        saveAndClose(in: app)

        primaryNavigation(in: app, destinationID: "progress", expectedLabel: "Progress").tap()
        let section = element(in: app, identifier: "progress-section-picker")
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        section.buttons["History"].tap()
        let savedAnswer = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", prompt)).firstMatch
        XCTAssertTrue(scrollUntilHittable(savedAnswer, in: app))
        savedAnswer.press(forDuration: 0.15)
        XCTAssertTrue(app.staticTexts["Your saved answer"].waitForExistence(timeout: 5))

        primaryNavigation(in: app, destinationID: "library", expectedLabel: "Sources").tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI Study Source.txt")).firstMatch
        XCTAssertTrue(scrollUntilHittable(source, in: app))
        source.tap()
        XCTAssertTrue(app.buttons["Read source"].waitForExistence(timeout: 5))
        primaryNavigation(in: app, destinationID: "progress", expectedLabel: "Progress").tap()

        for _ in 0..<3 {
            primaryNavigation(in: app, destinationID: "library", expectedLabel: "Sources").tap()
            XCTAssertTrue(app.buttons["Read source"].waitForExistence(timeout: 5))
            primaryNavigation(in: app, destinationID: "settings", expectedLabel: "Settings").tap()
            XCTAssertTrue(element(in: app, identifier: "settings-search").waitForExistence(timeout: 5))
            primaryNavigation(in: app, destinationID: "progress", expectedLabel: "Progress").tap()
            XCTAssertTrue(app.staticTexts["Your saved answer"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[prompt].exists)
        }
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "nested-history-detail-survives-source-settings-reentry"
        capture.lifetime = .keepAlways
        add(capture)
        #else
        throw XCTSkip("Persistent installed-app navigation runs on the iOS UI-test destination.")
        #endif
    }

    func testWeeklyChartDataOpensExactSavedAnswerHistory() throws {
        #if os(iOS)
        let app = XCUIApplication()
        app.launchArguments = persistentLaunchArguments(runID: UUID().uuidString,
            language: "en", reset: true, startSession: true)
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(element(in: app, identifier: "universal-session").waitForExistence(timeout: 15))
        resumeIfOffered(in: app)
        let prompt = element(in: app, identifier: "session-prompt")
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        let originalPrompt = prompt.label
        enterNumericAnswer("0", in: app)
        let done = app.keyboards.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable)
        done.tap()
        let feedback = element(in: app, identifier: "session-feedback-title")
        XCTAssertTrue(revealResponseControl(feedback, in: app))
        XCTAssertEqual(feedback.label, "Check the answer")
        saveAndClose(in: app)
        primaryNavigation(in: app, destinationID: "progress", expectedLabel: "Progress").tap()
        let section = element(in: app, identifier: "progress-section-picker")
        XCTAssertTrue(section.waitForExistence(timeout: 8))
        section.buttons["Overview"].tap()
        let details = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Explore details")).firstMatch
        XCTAssertTrue(scrollUntilHittable(details, in: app))
        details.tap()
        let data = app.buttons["View weekly chart data"]
        for _ in 0..<8 {
            if data.exists && data.isHittable { break }
            app.scrollViews.firstMatch.swipeDown()
        }
        XCTAssertTrue(data.exists)
        XCTAssertTrue(data.isHittable)
        data.tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "0%", "1 scored answer")).firstMatch
        XCTAssertTrue(scrollUntilHittable(row, in: app))
        XCTAssertTrue(row.isEnabled)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "weekly-chart-date-activity-count-credit-en"
        capture.lifetime = .keepAlways
        add(capture)
        row.tap()
        XCTAssertTrue(app.staticTexts["Saved answers represented by this chart point."].waitForExistence(timeout: 8),
            "Wait for the chart-scoped destination before resolving its scroll view.")
        let original = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", originalPrompt)).firstMatch
        XCTAssertTrue(scrollUntilHittable(original, in: app))
        original.press(forDuration: 0.15)
        XCTAssertTrue(app.staticTexts["Your saved answer"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", originalPrompt)).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["0"].exists)
        let detailCapture = XCTAttachment(screenshot: app.screenshot())
        detailCapture.name = "weekly-chart-matching-original-answer-en"
        detailCapture.lifetime = .keepAlways
        add(detailCapture)
        #else
        throw XCTSkip("Chart-to-history inspection uses the installed iOS app and a real committed response.")
        #endif
    }

    func testSourceRecallColdRelaunchPreservesDraftReferenceAndNeutralResult() throws {
        #if os(iOS)
        let app = XCUIApplication()
        let runID = UUID().uuidString
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: true, startSession: false)
            + ["-ui-test-source-document"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(element(in: app, identifier: "destination-today").waitForExistence(timeout: 15))
        primaryNavigation(in: app, destinationID: "library", expectedLabel: "Sources").tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI Study Source.txt")).firstMatch
        XCTAssertTrue(scrollUntilHittable(source, in: app))
        source.tap()
        let review = app.buttons["Review from memory"]
        XCTAssertTrue(scrollUntilHittable(review, in: app))
        XCTAssertTrue(review.isEnabled)
        review.tap()
        XCTAssertTrue(element(in: app, identifier: "universal-session").waitForExistence(timeout: 10))
        resumeIfOffered(in: app)
        let prompt = element(in: app, identifier: "session-prompt")
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        let originalPrompt = prompt.label
        XCTAssertEqual(originalPrompt, "Recall the main ideas from the cited excerpt in your own words.")
        XCTAssertEqual(element(in: app, identifier: "session-position").value as? String, "1 / 1")
        let excerpt = "A triangle has three sides. This synthetic source is used only for navigation testing."
        XCTAssertFalse(app.staticTexts[excerpt].exists)
        let recall = "A triangle has three sides."
        enterText(recall, in: app.textViews.firstMatch, app: app, minimumHeight: 44)
        let pause = app.buttons["Pause session"]
        XCTAssertTrue(pause.isHittable)
        pause.tap()
        let save = element(in: app, identifier: "session-save-close")
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.buttons["Review from memory"].waitForExistence(timeout: 8), "Closing the review must return to its original document.")
        app.terminate()
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: false, startSession: false)
        app.launch()
        continueSavedSession(in: app)
        XCTAssertEqual(element(in: app, identifier: "session-prompt").label, originalPrompt)
        XCTAssertEqual(element(in: app, identifier: "session-position").value as? String, "1 / 1")
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertEqual(editor.value as? String, recall)
        XCTAssertFalse(app.staticTexts[excerpt].exists)
        submitVisibleResponse(in: app)
        let reference = app.staticTexts[excerpt]
        XCTAssertTrue(revealResponseControl(reference, in: app))
        XCTAssertFalse(editor.isEnabled)
        chooseResponse("Not yet", in: app)
        submitVisibleResponse(in: app)
        let feedback = element(in: app, identifier: "session-feedback-title")
        XCTAssertTrue(revealResponseControl(feedback, in: app))
        XCTAssertEqual(feedback.label, "Self-check saved")
        XCTAssertFalse(app.staticTexts["Incorrect"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "source-exact-recall-cold-resume-neutral-feedback-en"
        capture.lifetime = .keepAlways
        add(capture)
        saveAndClose(in: app)
        app.terminate()
        app.launch()
        continueSavedSession(in: app)
        XCTAssertEqual(element(in: app, identifier: "session-prompt").label, originalPrompt)
        XCTAssertEqual(element(in: app, identifier: "session-position").value as? String, "1 / 1")
        XCTAssertTrue(element(in: app, identifier: "session-next").waitForExistence(timeout: 8))
        XCTAssertTrue(revealResponseControl(feedback, in: app))
        XCTAssertEqual(feedback.label, "Self-check saved")
        #else
        throw XCTSkip("Source continuity uses the installed iOS app and an isolated synthetic source.")
        #endif
    }

    func testGeneratedSetCreatesSeparateRunsAndRestoresSkippedRunThroughColdLaunch() throws {
        #if os(iOS)
        let app = XCUIApplication(), runID = UUID().uuidString
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: true, startSession: false)
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(element(in: app, identifier: "destination-today").waitForExistence(timeout: 15))
        let practice = primaryNavigation(in: app, destinationID: "train", expectedLabel: "Practice")
        XCTAssertTrue(practice.waitForExistence(timeout: 5)); XCTAssertTrue(practice.isHittable)
        XCTAssertGreaterThanOrEqual(practice.frame.height, 44)
        // The recorded 50 ms tap left Today selected on this host. Use one
        // ordinary-duration press and require acknowledgement before scrolling.
        practice.press(forDuration: 0.15)
        XCTAssertTrue(element(in: app, identifier: "destination-train").waitForExistence(timeout: 8),
            "The Practice tab must acknowledge the single navigation gesture before searching its content.")
        XCTAssertTrue(practice.isSelected)
        let studio = element(in: app, identifier: "open-ai-studio")
        XCTAssertTrue(scrollUntilHittable(studio, in: app))
        XCTAssertGreaterThanOrEqual(studio.frame.height, 44)
        studio.tap()
        XCTAssertTrue(element(in: app, identifier: "ai-studio-root").waitForExistence(timeout: 8))
        enterText("Condition reasoning", in: app.textFields["What do you want to practice?"], app: app, minimumHeight: 44)
        let done = app.keyboards.buttons["Done"]
        XCTAssertTrue(done.exists); done.tap()
        let keyboardDismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardDismissed], timeout: 5), .completed)
        let generate = app.buttons["ai-studio-create-offline"]
        XCTAssertTrue(revealResponseControl(generate, in: app)); XCTAssertTrue(generate.isEnabled)
        XCTAssertGreaterThanOrEqual(generate.frame.height, 44)
        generate.tap()
        let start = app.buttons["Start practice"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        XCTAssertTrue(revealResponseControl(start, in: app))
        XCTAssertTrue(start.isEnabled, "A freshly created ready set must be recoverable and available for practice.")
        start.tap()
        let prompt = element(in: app, identifier: "ai-practice-prompt")
        XCTAssertTrue(prompt.waitForExistence(timeout: 10))
        let originalPrompt = prompt.label
        let position = element(in: app, identifier: "ai-practice-position")
        XCTAssertEqual(position.label, "1 / 5")
        let actions = app.buttons["Session actions"]
        XCTAssertTrue(actions.isHittable); actions.tap()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5)); XCTAssertTrue(skip.isEnabled); skip.tap()
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "2 / 5"), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 8), .completed)
        let secondPrompt = prompt.label
        XCTAssertFalse(secondPrompt.isEmpty)
        app.navigationBars.buttons["Save and close"].tap()
        let newRun = app.buttons["Start a new session"]
        XCTAssertTrue(newRun.waitForExistence(timeout: 8))
        XCTAssertTrue(revealResponseControl(newRun, in: app)); newRun.tap()
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        XCTAssertEqual(position.label, "1 / 5")
        XCTAssertEqual(prompt.label, originalPrompt, "Starting a separate run of one retained set begins with its original first question")
        app.navigationBars.buttons["Save and close"].tap()
        app.terminate()
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: false, startSession: false)
        app.launch()
        XCTAssertTrue(element(in: app, identifier: "destination-today").waitForExistence(timeout: 15))
        let continueRun = app.buttons["Continue session"].firstMatch
        XCTAssertTrue(revealResponseControl(continueRun, in: app)); continueRun.tap()
        let resume = app.buttons["Resume"].firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 8)); resume.tap()
        XCTAssertTrue(prompt.waitForExistence(timeout: 8)); XCTAssertEqual(prompt.label, originalPrompt)
        XCTAssertEqual(position.label, "1 / 5")
        actions.tap(); app.buttons["End session"].tap()
        let summary = element(in: app, identifier: "ai-practice-summary")
        XCTAssertTrue(summary.waitForExistence(timeout: 8))
        XCTAssertEqual(summary.label, "Ended after 0 of 5 questions.")
        app.buttons["Done"].tap()
        XCTAssertTrue(revealResponseControl(continueRun, in: app)); continueRun.tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 8)); resume.tap()
        XCTAssertTrue(prompt.waitForExistence(timeout: 8)); XCTAssertEqual(prompt.label, secondPrompt)
        XCTAssertEqual(position.label, "2 / 5", "Ending the newer run must not replace or end the older skipped run")
        actions.tap(); app.buttons["End session"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 8))
        XCTAssertEqual(summary.label, "Ended after 1 of 5 questions.")
        XCTAssertTrue(app.staticTexts["Skipped 1 · Solutions viewed 0"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "generated-two-runs-cold-skip-explicit-end-en"; capture.lifetime = .keepAlways; add(capture)
        app.buttons["Done"].tap()
        XCTAssertFalse(app.buttons["Continue session"].exists, "Both explicitly ended generated runs leave Continue while retaining their activity history")
        #else
        throw XCTSkip("Generated run continuity uses the installed iOS app and isolated on-device authoring.")
        #endif
    }

    func testQuestionSetSourceChooserPreservesSelectionAcrossSearchAndReopen() throws {
        #if os(iOS)
        let app = XCUIApplication()
        app.launchArguments = persistentLaunchArguments(runID: UUID().uuidString,
            language: "en", reset: true, startSession: false) + ["-ui-test-source-document"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(element(in: app, identifier: "destination-today").waitForExistence(timeout: 15))
        primaryNavigation(in: app, destinationID: "train", expectedLabel: "Practice").tap()
        let openStudio = element(in: app, identifier: "open-ai-studio")
        XCTAssertTrue(scrollUntilHittable(openStudio, in: app))
        openStudio.tap()
        XCTAssertTrue(element(in: app, identifier: "ai-studio-root").waitForExistence(timeout: 8))
        let chooser = element(in: app, identifier: "ai-studio-source-chooser")
        XCTAssertTrue(scrollUntilHittable(chooser, in: app))
        chooser.tap()
        let source = app.buttons["UI Study Source.txt"]
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        XCTAssertTrue(source.isEnabled)
        XCTAssertTrue(source.isHittable)
        source.tap()
        XCTAssertTrue(app.staticTexts["Selected sources: 1"].waitForExistence(timeout: 5))
        let search = app.textFields["ai-source-search"]
        XCTAssertTrue(search.isHittable)
        search.tap()
        search.typeText("zz-no-source-match\n")
        XCTAssertTrue(app.staticTexts["No matching sources"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Selected sources: 1"].exists)
        app.buttons["Clear filters"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue((source.value as? String)?.contains("Selected") == true)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "source-chooser-preserves-selection-after-search-en"
        capture.lifetime = .keepAlways
        add(capture)
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(chooser.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollUntilHittable(chooser, in: app))
        chooser.tap()
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Selected sources: 1"].exists)
        source.tap()
        XCTAssertTrue(app.staticTexts["Selected sources: 0"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Done"].tap()
        #else
        throw XCTSkip("Source chooser interaction uses the installed iOS app and isolated synthetic source.")
        #endif
    }

    func testTodayReplacementPreviewCancelsAndAppliesItsExactTitleAfterColdLaunch() throws {
        #if os(iOS)
        let app = XCUIApplication(), runID = UUID().uuidString
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: true, startSession: false)
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(element(in: app, identifier: "destination-today").waitForExistence(timeout: 15))
        let chapter = app.buttons["today-plan-block-1"]
        XCTAssertTrue(revealResponseControl(chapter, in: app)); chapter.tap()
        let title = app.staticTexts["plan-block-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        let originalTitle = title.label
        let reasonMenu = app.buttons["plan-replacement-reason"]
        func chooseReasonAndPreview() {
            XCTAssertTrue(revealResponseControl(reasonMenu, in: app))
            XCTAssertGreaterThanOrEqual(reasonMenu.frame.height, 44); reasonMenu.tap()
            for reason in ["Too easy", "Too hard", "Already familiar", "Want variety", "Accessibility issue"] {
                XCTAssertTrue(app.buttons[reason].exists)
            }
            app.buttons["Too hard"].tap()
            let preview = app.buttons["plan-replacement-preview"]
            XCTAssertTrue(revealResponseControl(preview, in: app))
            XCTAssertGreaterThanOrEqual(preview.frame.height, 44); preview.tap()
            XCTAssertTrue(app.staticTexts["plan-replacement-preview-heading"].waitForExistence(timeout: 5))
        }
        chooseReasonAndPreview()
        let proposed = app.staticTexts["plan-replacement-proposed-title"]
        XCTAssertTrue(revealResponseControl(proposed, in: app))
        XCTAssertFalse(proposed.label.isEmpty); XCTAssertNotEqual(proposed.label, originalTitle)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "today-exact-replacement-title-duration-before-apply-en"; capture.lifetime = .keepAlways; add(capture)
        let cancel = app.buttons["plan-replacement-cancel"]
        XCTAssertTrue(revealResponseControl(cancel, in: app)); cancel.tap()
        XCTAssertFalse(app.staticTexts["plan-replacement-preview-heading"].exists)
        XCTAssertEqual(title.label, originalTitle)
        app.navigationBars.buttons["Close"].tap()
        app.terminate()
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: false, startSession: false)
        app.launch()
        XCTAssertTrue(element(in: app, identifier: "destination-today").waitForExistence(timeout: 15))
        XCTAssertTrue(revealResponseControl(chapter, in: app)); chapter.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 8)); XCTAssertEqual(title.label, originalTitle)
        chooseReasonAndPreview()
        let exactProposedTitle = proposed.label
        let apply = app.buttons["plan-replacement-apply"]
        XCTAssertTrue(revealResponseControl(apply, in: app)); XCTAssertGreaterThanOrEqual(apply.frame.height, 44)
        apply.tap()
        XCTAssertTrue(app.staticTexts["Replacement saved"].waitForExistence(timeout: 8))
        XCTAssertEqual(title.label, exactProposedTitle)
        let acknowledge = app.buttons["Acknowledge replacement"]
        XCTAssertTrue(revealResponseControl(acknowledge, in: app)); XCTAssertGreaterThanOrEqual(acknowledge.frame.height, 44)
        let saved = XCTAttachment(screenshot: app.screenshot())
        saved.name = "today-exact-replacement-saved-acknowledgement-en"; saved.lifetime = .keepAlways; add(saved)
        acknowledge.tap()
        app.navigationBars.buttons["Close"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(element(in: app, identifier: "destination-today").waitForExistence(timeout: 15))
        XCTAssertTrue(revealResponseControl(chapter, in: app)); chapter.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 8)); XCTAssertEqual(title.label, exactProposedTitle)
        XCTAssertFalse(app.buttons["plan-replacement-preview"].exists)
        #else
        throw XCTSkip("Exact Today replacement preview runs in the installed iOS app.")
        #endif
    }

    func testEnergyPreviewCancelPreservesSavedPreferenceAfterRelaunch() throws {
        #if os(iOS)
        let app = XCUIApplication()
        let runID = UUID().uuidString
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: true, startSession: false)
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(element(in: app, identifier: "destination-today").waitForExistence(timeout: 15))
        let picker = element(in: app, identifier: "today-readiness-picker")
        XCTAssertTrue(scrollUntilHittable(picker, in: app))
        let original = try XCTUnwrap(picker.value as? String)
        picker.tap()
        let proposed = original == "Low" ? "High" : "Low"
        let choice = app.buttons[proposed]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        XCTAssertTrue(choice.isHittable)
        choice.tap()
        let effect = element(in: app, identifier: "readiness-preview-effect")
        XCTAssertTrue(effect.waitForExistence(timeout: 8))
        XCTAssertTrue(effect.isHittable)
        XCTAssertTrue(app.staticTexts["Saved answers, completed sections and earned rewards stay unchanged."].exists)
        let apply = element(in: app, identifier: "readiness-preview-apply")
        XCTAssertTrue(apply.isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "energy-change-preview-before-apply-en"
        capture.lifetime = .keepAlways
        add(capture)
        let cancel = app.buttons["readiness-preview-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(cancel.isHittable)
        cancel.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, original)
        app.terminate()
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: false, startSession: false)
        app.launch()
        XCTAssertTrue(element(in: app, identifier: "destination-today").waitForExistence(timeout: 15))
        XCTAssertTrue(scrollUntilHittable(picker, in: app))
        XCTAssertEqual(picker.value as? String, original, "Cancel must not persist the proposed energy value")
        #else
        throw XCTSkip("Energy preview uses the installed iOS app and isolated saved preference.")
        #endif
    }

    private func exerciseExactRelaunch(language: String) throws {
        #if os(iOS)
        let app = XCUIApplication()
        let runID = UUID().uuidString
        app.launchArguments = persistentLaunchArguments(runID: runID, language: language, reset: true, startSession: true)
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(element(in: app, identifier: "universal-session").waitForExistence(timeout: 15))
        XCTAssertTrue(element(in: app, identifier: "session-position").waitForExistence(timeout: 8))
        resumeIfOffered(in: app)
        for _ in 0..<2 {
            let oldPosition = element(in: app, identifier: "session-position").value as? String ?? ""
            enterNumericAnswer("1", in: app)
            element(in: app, identifier: "session-submit").tap()
            let next = element(in: app, identifier: "session-next")
            XCTAssertTrue(next.waitForExistence(timeout: 8))
            XCTAssertTrue(scrollUntilHittable(next, in: app))
            next.press(forDuration: 0.15)
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", oldPosition), object: element(in: app, identifier: "session-position"))
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed)
        }
        let originalPrompt = element(in: app, identifier: "session-prompt").label
        let originalPosition = element(in: app, identifier: "session-position").value as? String ?? ""
        XCTAssertFalse(originalPrompt.isEmpty)
        enterNumericAnswer("17", in: app)
        saveAndClose(in: app)
        app.terminate()
        app.launchArguments = persistentLaunchArguments(runID: runID, language: language, reset: false, startSession: false)
        app.launch()
        continueSavedSession(in: app)
        let answer = element(in: app, identifier: "session-numeric-answer")
        XCTAssertTrue(answer.waitForExistence(timeout: 8))
        XCTAssertEqual(answer.value as? String, "17")
        XCTAssertEqual(element(in: app, identifier: "session-prompt").label, originalPrompt)
        XCTAssertEqual(element(in: app, identifier: "session-position").value as? String ?? "", originalPosition)
        element(in: app, identifier: "session-submit").tap()
        XCTAssertTrue(element(in: app, identifier: "session-next").waitForExistence(timeout: 8))
        saveAndClose(in: app)
        app.terminate()
        app.launch()
        continueSavedSession(in: app)
        XCTAssertTrue(element(in: app, identifier: "session-next").waitForExistence(timeout: 8))
        XCTAssertEqual(element(in: app, identifier: "session-position").value as? String ?? "", originalPosition)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", originalPrompt)).firstMatch.exists || element(in: app, identifier: "session-prompt").label == originalPrompt)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "question-three-exact-feedback-cold-relaunch-\(language)"
        capture.lifetime = .keepAlways
        add(capture)
        #else
        throw XCTSkip("Cold relaunch requires the installed iOS app and an isolated persistent UI-test store.")
        #endif
    }

    func testSpatialLabeledCubeSeparatesCameraFromSavedAnswerAndObjectReplay() throws {
        let directions: [String: (Int, Int, Int)] = ["A": (1,0,0), "B": (-1,0,0), "C": (0,1,0),
            "D": (0,-1,0), "E": (0,0,1), "F": (0,0,-1)]
        try exerciseLabResponse(activity: "spatial.object-rotation", promptFragment: "which face points along", expectedFeedback: "Correct", afterFeedback: { app, prompt in
            let solved = try self.solveVisibleCubeOperations(prompt, originals: directions)
            let step = app.buttons["spatial-structure-step"]
            for _ in prompt.components(separatedBy: "\n").filter({ $0.hasPrefix("1.") || $0.hasPrefix("2.") || $0.hasPrefix("3.") }) {
                XCTAssertTrue(self.revealResponseControl(step, in: app, searchAboveWhenAbsent: true))
                XCTAssertGreaterThanOrEqual(step.frame.height, 44); XCTAssertTrue(step.isEnabled)
                step.tap()
            }
            XCTAssertFalse(step.isEnabled)
            for face in directions.keys.sorted() {
                XCTAssertEqual(self.element(in: app, identifier: "spatial-face-"+face).label,
                    "Face \(face): outward normal \(self.cubeDirection(solved[face]!))")
            }
            let reset = app.buttons["spatial-structure-reset"]
            XCTAssertTrue(self.revealResponseControl(reset, in: app)); XCTAssertGreaterThanOrEqual(reset.frame.height, 44)
            let replay = XCTAttachment(screenshot: app.screenshot()); replay.name = "labeled-cube-worked-rotation-controls-en"
            replay.lifetime = .keepAlways; self.add(replay)
            reset.tap()
            for face in directions.keys.sorted() {
                XCTAssertEqual(self.element(in: app, identifier: "spatial-face-"+face).label,
                    "Face \(face): outward normal \(self.cubeDirection(directions[face]!))")
            }
            XCTAssertFalse(app.buttons["Face \(try self.cubeAnswer(prompt: prompt, transformed: solved))"].isEnabled)
        }) { app, prompt in
            let solved = try self.solveVisibleCubeOperations(prompt, originals: directions)
            for face in directions.keys.sorted() {
                XCTAssertEqual(self.element(in: app, identifier: "spatial-face-"+face).label,
                    "Face \(face): outward normal \(self.cubeDirection(directions[face]!))",
                    "The public face table must give the original object, without a solved orientation.")
            }
            let step = app.buttons["spatial-structure-step"]
            XCTAssertTrue(step.exists); XCTAssertFalse(step.isEnabled)
            let camera = self.element(in: app, identifier: "spatial-structure-camera")
            XCTAssertTrue(self.revealResponseControl(camera, in: app, searchAboveWhenAbsent: true))
            XCTAssertTrue(camera.isEnabled); XCTAssertGreaterThanOrEqual(camera.frame.height, 44)
            camera.tap(); app.buttons["Top"].tap()
            XCTAssertEqual(camera.value as? String, "Top")
            let reset = app.buttons["spatial-structure-camera-reset"]
            XCTAssertTrue(self.revealResponseControl(reset, in: app)); reset.tap()
            XCTAssertEqual(camera.value as? String, "Authored view")
            let rendering = self.element(in: app, identifier: "spatial-structure-rendering-mode")
            XCTAssertTrue(self.revealResponseControl(rendering, in: app, searchAboveWhenAbsent: true)); rendering.tap()
            app.buttons["spatial-structure-mode-static"].tap()
            XCTAssertEqual(rendering.value as? String, "Static 2D")
            for face in directions.keys.sorted() {
                XCTAssertEqual(self.element(in: app, identifier: "spatial-face-"+face).label,
                    "Face \(face): outward normal \(self.cubeDirection(directions[face]!))")
            }
            XCTAssertFalse(step.isEnabled)
            let answer = app.buttons["Face \(try self.cubeAnswer(prompt: prompt, transformed: solved))"]
            XCTAssertTrue(self.revealResponseControl(answer, in: app)); XCTAssertGreaterThanOrEqual(answer.frame.height, 44)
            answer.tap()
        }
    }

    /// Rodrigues' rotation formula reads only the prompt's fixed axes/angles;
    /// it is independent of the app's integer quarter-turn implementation.
    private func solveVisibleCubeOperations(_ prompt: String, originals: [String: (Int, Int, Int)]) throws -> [String: (Int, Int, Int)] {
        let operations = prompt.components(separatedBy: "\n").filter { $0.range(of: #"^\d+\. "#, options: .regularExpression) != nil }
        XCTAssertFalse(operations.isEmpty)
        var result = originals
        for operation in operations {
            let angle = try integers(in: operation, pattern: #"Rotate the object \+(\d+)°"#)[0]
            let axis: (Double, Double, Double)
            if operation.contains("fixed +x axis") { axis = (1,0,0) }
            else if operation.contains("fixed +y axis") { axis = (0,1,0) }
            else if operation.contains("fixed +z axis") { axis = (0,0,1) }
            else { throw NSError(domain: "CubeRotationUI", code: 1) }
            let radians = Double(angle) * .pi / 180, c = cos(radians), s = sin(radians)
            for (face, value) in result {
                let (x,y,z) = (Double(value.0), Double(value.1), Double(value.2))
                let dot = axis.0*x + axis.1*y + axis.2*z
                result[face] = (Int((x*c + (axis.1*z-axis.2*y)*s + axis.0*dot*(1-c)).rounded()),
                    Int((y*c + (axis.2*x-axis.0*z)*s + axis.1*dot*(1-c)).rounded()),
                    Int((z*c + (axis.0*y-axis.1*x)*s + axis.2*dot*(1-c)).rounded()))
            }
        }
        return result
    }
    private func cubeDirection(_ value: (Int, Int, Int)) -> String {
        for (axis, component) in [("x",value.0),("y",value.1),("z",value.2)] where component != 0 {
            return (component > 0 ? "+" : "−") + axis
        }
        return "invalid"
    }
    private func cubeAnswer(prompt: String, transformed: [String: (Int, Int, Int)]) throws -> String {
        let matches = transformed.filter { prompt.contains("which face points along \(cubeDirection($0.value))?") }
        XCTAssertEqual(matches.count, 1)
        guard let answer = matches.keys.first, matches.count == 1 else { throw NSError(domain: "CubeRotationUI", code: 2) }
        return answer
    }

    func testCubeNetRetainsPrintedGivensAcrossCameraAndCommittedFolding() throws {
        try exerciseLabResponse(activity: "spatial.cube-net", promptFragment: "Six unit squares on a grid:", expectedFeedback: "Correct", afterFeedback: { app, prompt in
            let solved = try self.solveVisibleCubeNet(prompt)
            XCTAssertTrue(solved.valid, "This installed fixture must exercise a valid complete fold, unfold and restore; an invalid-only proposal cannot establish that coverage.")
            let oracleRecord = XCTAttachment(string: prompt + "\nValid closed cube: " + String(solved.valid) + "\nIndependent response: " + solved.answers.joined(separator: ", "))
            oracleRecord.name = "cube-net-visible-query-oracle"; oracleRecord.lifetime = .keepAlways; self.add(oracleRecord)
            let original = self.element(in: app, identifier: "net-folding-givens")
            let givens = original.label
            let complete = app.buttons["net-folding-complete"]
            XCTAssertTrue(self.revealResponseControl(complete, in: app, searchAboveWhenAbsent: true))
            XCTAssertGreaterThanOrEqual(complete.frame.height, 44)
            XCTAssertEqual(complete.isEnabled, solved.valid)
            if solved.valid {
                complete.tap()
                let worked = self.element(in: app, identifier: "net-folding-worked-frames")
                XCTAssertTrue(worked.waitForExistence(timeout: 5))
                for line in solved.frames { XCTAssertTrue(worked.label.contains(line), "Every shown face normal and printed arrow must match the independent shared-edge oracle.") }
                XCTAssertFalse(complete.isEnabled)
                let model = self.element(in: app, identifier: "net-folding-model")
                XCTAssertTrue(self.revealResponseControl(model, in: app, searchAboveWhenAbsent: true))
                XCTAssertGreaterThanOrEqual(model.frame.height, 280)
                let modelCapture = XCTAttachment(screenshot: app.screenshot())
                modelCapture.name = "cube-net-completed-model-en"; modelCapture.lifetime = .keepAlways; self.add(modelCapture)
                XCTAssertTrue(self.revealResponseControl(worked, in: app))
                let capture = XCTAttachment(screenshot: app.screenshot())
                capture.name = "cube-net-saved-complete-fold-en"; capture.lifetime = .keepAlways; self.add(capture)
                let unfold = app.buttons["net-folding-unfold"]
                XCTAssertTrue(self.revealResponseControl(unfold, in: app, searchAboveWhenAbsent: true))
                XCTAssertGreaterThanOrEqual(unfold.frame.height, 44); unfold.tap()
                XCTAssertFalse(worked.exists); XCTAssertTrue(complete.isEnabled)
                XCTAssertEqual(original.label, givens)
                XCTAssertTrue(self.revealResponseControl(complete, in: app, searchAboveWhenAbsent: true))
                complete.tap(); XCTAssertTrue(worked.waitForExistence(timeout: 5))
                let restore = app.buttons["net-folding-reset"]
                XCTAssertTrue(self.revealResponseControl(restore, in: app))
                XCTAssertGreaterThanOrEqual(restore.frame.height, 44); restore.tap()
                XCTAssertFalse(worked.exists); XCTAssertTrue(complete.isEnabled)
            } else {
                XCTAssertTrue(self.element(in: app, identifier: "net-folding-invalid-proposal").exists)
                XCTAssertFalse(self.element(in: app, identifier: "net-folding-worked-frames").exists)
            }
            XCTAssertEqual(original.label, givens)
            XCTAssertEqual(self.element(in: app, identifier: "session-prompt").label, prompt)
            for answer in solved.answers {
                let locked = app.buttons[answer]
                XCTAssertTrue(self.revealResponseControl(locked, in: app))
                XCTAssertFalse(locked.isEnabled)
                self.assertSelected(locked)
            }
        }) { app, prompt in
            let original = self.element(in: app, identifier: "net-folding-givens")
            XCTAssertTrue(original.exists); let givens = original.label
            XCTAssertTrue(self.element(in: app, identifier: "net-folding-independent-policy").exists)
            for name in ["net-folding-complete", "net-folding-unfold", "net-folding-reset", "net-folding-worked-frames"] {
                XCTAssertFalse(self.element(in: app, identifier: name).exists)
            }
            let camera = app.buttons["net-folding-camera"]
            XCTAssertTrue(self.revealResponseControl(camera, in: app)); XCTAssertGreaterThanOrEqual(camera.frame.height, 44)
            camera.tap(); app.buttons["Top"].tap(); XCTAssertEqual(camera.value as? String, "Top")
            let reset = app.buttons["net-folding-camera-reset"]
            XCTAssertTrue(self.revealResponseControl(reset, in: app)); XCTAssertGreaterThanOrEqual(reset.frame.height, 44)
            reset.tap(); XCTAssertEqual(camera.value as? String, "Authored view")
            let rendering = app.buttons["net-folding-rendering-mode"]
            XCTAssertTrue(self.revealResponseControl(rendering, in: app, searchAboveWhenAbsent: true))
            XCTAssertGreaterThanOrEqual(rendering.frame.height, 44)
            rendering.tap(); app.buttons["Static 2D"].tap(); XCTAssertEqual(rendering.value as? String, "Static 2D")
            XCTAssertEqual(original.label, givens)
            for answer in try self.solveVisibleCubeNet(prompt).answers { self.chooseResponse(answer, in: app) }
            XCTAssertFalse(self.element(in: app, identifier: "net-folding-worked-frames").exists)
        }
    }

    /// Solve the public grid by assigning its directed shared edges to the 24
    /// oriented faces of a closed cube. No application model, key, fold update
    /// recurrence or rendered geometry is consulted.
    private func solveVisibleCubeNet(_ prompt: String) throws -> (answers: [String], valid: Bool, frames: [String]) {
        typealias V = SIMD3<Int>
        struct Face: Equatable { let center: V, right: V, up: V, normal: V }
        func dot(_ a: V, _ b: V) -> Int { a.x*b.x + a.y*b.y + a.z*b.z }
        func cross(_ a: V, _ b: V) -> V { V(a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x) }
        func add(_ a: V, _ b: V) -> V { V(a.x+b.x,a.y+b.y,a.z+b.z) }
        func scale(_ a: V, _ b: Int) -> V { V(a.x*b,a.y*b,a.z*b) }
        func token(_ a: V) -> String { "\(a.x),\(a.y),\(a.z)" }
        func captures(_ pattern: String, in text: String) throws -> [[String]] {
            let regex = try NSRegularExpression(pattern: pattern)
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
                (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
            }
        }
        let rawCells = try captures(#"([A-F]): \((-?\d+), (-?\d+)\)"#, in: prompt)
        guard rawCells.count == 6 else { throw NSError(domain: "VisibleNetOracle", code: 1) }
        let cells = try rawCells.map { (label: $0[0], x: try XCTUnwrap(Int($0[1])), y: try XCTUnwrap(Int($0[2]))) }
        let axes = [V(1,0,0),V(-1,0,0),V(0,1,0),V(0,-1,0),V(0,0,1),V(0,0,-1)]
        let candidates = axes.flatMap { n in axes.filter { dot(n,$0) == 0 }.map { r in
            Face(center: add(n,V(0,0,-1)), right:r, up:cross(n,r), normal:n)
        } }
        func edge(_ f: Face, dx: Int, dy: Int) -> [V] {
            let center = add(f.center, scale(dx == 0 ? f.up : f.right, dx == 0 ? dy : dx))
            let tangent = dx == 0 ? f.right : f.up
            return [add(center,scale(tangent,-1)),add(center,tangent)]
        }
        var mapped = [cells[0].label: Face(center:V(0,0,0),right:V(1,0,0),up:V(0,1,0),normal:V(0,0,1))]
        var queue = [0], cursor = 0, valid = true
        while cursor < queue.count && valid {
            let a = cells[queue[cursor]]; cursor += 1
            let face = try XCTUnwrap(mapped[a.label])
            for (index,b) in cells.enumerated() where abs(a.x-b.x)+abs(a.y-b.y) == 1 {
                let allowed = candidates.filter { edge(face,dx:b.x-a.x,dy:b.y-a.y) == edge($0,dx:a.x-b.x,dy:a.y-b.y) }
                guard allowed.count == 1, let next = allowed.first else { valid = false; break }
                if let prior = mapped[b.label] { if prior != next { valid = false; break } }
                else { mapped[b.label] = next; queue.append(index) }
            }
        }
        valid = valid && mapped.count == 6 && Set(mapped.values.map(\.normal)).count == 6
        let question = try XCTUnwrap(prompt.components(separatedBy: "\n").last)
        let yes = "Yes — every stated rule holds", no = "No — at least one rule fails"
        let answers: [String]
        if question.hasPrefix("Can this exact pattern") { answers = [valid ? yes : no] }
        else {
            guard valid else { throw NSError(domain:"VisibleNetOracle",code:2) }
            if question.hasPrefix("Which face becomes opposite face ") {
                let label = try XCTUnwrap(captures(#"opposite face ([A-F])\?"#, in:question).first?.first)
                let face = try XCTUnwrap(mapped[label])
                answers = mapped.keys.sorted().filter { dot(mapped[$0]!.normal,face.normal) == -1 }.map { "Face " + $0 }
                XCTAssertEqual(answers.count,1)
            } else if question.hasPrefix("Select every face sharing an edge with face ") {
                let label = try XCTUnwrap(captures(#"with face ([A-F]) on"#, in:question).first?.first)
                let face = try XCTUnwrap(mapped[label])
                answers = mapped.keys.sorted().filter { dot(mapped[$0]!.normal,face.normal) == 0 }.map { "Face " + $0 }
                XCTAssertEqual(answers.count,4)
            } else if question.hasPrefix("After completing the fold") {
                let label = try XCTUnwrap(captures(#"describes ([A-F])'s"#, in:question).first?.first)
                let face = try XCTUnwrap(mapped[label]), value = question.contains("outward normal") ? face.normal : face.up
                let names = ["positive x","negative x","positive y","negative y","positive z","negative z"]
                answers = [names[try XCTUnwrap(axes.firstIndex(of:value))]]
            } else if question.hasPrefix("A proposed completed fold must satisfy BOTH conditions: ") {
                let conditions = question.replacingOccurrences(of:"A proposed completed fold must satisfy BOTH conditions: ",with:"")
                    .components(separatedBy:". Does the exact net")[0].components(separatedBy:"; ")
                guard conditions.count == 2 else { throw NSError(domain:"VisibleNetOracle",code:3) }
                func holds(_ condition: String) throws -> Bool {
                    let pairs = try captures(#"faces ([A-F]) and ([A-F]) (are opposite|share a cube edge)"#,in:condition)
                    if let pair = pairs.first {
                        let a = try XCTUnwrap(mapped[pair[0]]), b = try XCTUnwrap(mapped[pair[1]])
                        return dot(a.normal,b.normal) == (pair[2] == "are opposite" ? -1 : 0)
                    }
                    let parts = try XCTUnwrap(captures(#"face ([A-F]) (has outward normal|has its printed arrow pointing) ([+−][xyz])"#,in:condition).first)
                    let face = try XCTUnwrap(mapped[parts[0]]), symbols = ["+x","−x","+y","−y","+z","−z"]
                    return (parts[1] == "has outward normal" ? face.normal : face.up) == axes[try XCTUnwrap(symbols.firstIndex(of:parts[2]))]
                }
                let first = try holds(conditions[0]), second = try holds(conditions[1])
                answers = [first && second ? yes : no]
            } else { throw NSError(domain:"VisibleNetOracle",code:4) }
        }
        return (answers,valid,valid ? mapped.keys.sorted().map { label in
            let f = mapped[label]!; return "\(label) normal \(token(f.normal)), arrow \(token(f.up))"
        } : [])
    }

    func testSolidSectionUsesOriginalConstraintsBeforeSavedWorkedSection() throws {
        try exerciseLabResponse(activity: "spatial.cross-section", promptFragment: "The plane is", expectedFeedback: "Correct", afterFeedback: { app, prompt in
            let original = self.element(in: app, identifier: "solid-section-original-givens")
            let givens = original.label
            let show = app.buttons["solid-section-show-worked"]
            XCTAssertTrue(self.revealResponseControl(show, in: app, searchAboveWhenAbsent: true))
            XCTAssertGreaterThanOrEqual(show.frame.height, 44); XCTAssertTrue(show.isEnabled)
            show.tap()
            let worked = self.element(in: app, identifier: "solid-section-worked-explanation")
            XCTAssertTrue(worked.waitForExistence(timeout: 5))
            XCTAssertTrue(self.revealResponseControl(worked, in: app))
            XCTAssertFalse(show.isEnabled); XCTAssertEqual(original.label, givens)
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "solid-section-saved-worked-geometry-en"; capture.lifetime = .keepAlways; self.add(capture)
            let reset = app.buttons["solid-section-reset-worked"]
            XCTAssertTrue(self.revealResponseControl(reset, in: app, searchAboveWhenAbsent: true))
            XCTAssertGreaterThanOrEqual(reset.frame.height, 44); reset.tap()
            let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: worked)
            XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
            XCTAssertEqual(original.label, givens); XCTAssertTrue(show.isEnabled)
            XCTAssertEqual(self.element(in: app, identifier: "session-prompt").label, prompt)
        }) { app, prompt in
            let original = self.element(in: app, identifier: "solid-section-original-givens")
            XCTAssertTrue(original.exists); let givens = original.label
            XCTAssertTrue(self.element(in: app, identifier: "solid-section-independent-policy").exists)
            XCTAssertFalse(app.buttons["solid-section-show-worked"].exists)
            XCTAssertFalse(self.element(in: app, identifier: "solid-section-worked-explanation").exists)
            let camera = self.element(in: app, identifier: "solid-section-camera")
            XCTAssertTrue(self.revealResponseControl(camera, in: app)); XCTAssertGreaterThanOrEqual(camera.frame.height, 44)
            camera.tap(); app.buttons["Top"].tap()
            XCTAssertEqual(camera.value as? String, "Top")
            let reset = app.buttons["solid-section-camera-reset"]
            XCTAssertTrue(self.revealResponseControl(reset, in: app)); reset.tap()
            XCTAssertEqual(camera.value as? String, "Authored view")
            let rendering = self.element(in: app, identifier: "solid-section-rendering-mode")
            XCTAssertTrue(self.revealResponseControl(rendering, in: app, searchAboveWhenAbsent: true)); rendering.tap()
            app.buttons["Static 2D"].tap(); XCTAssertEqual(rendering.value as? String, "Static 2D")
            XCTAssertEqual(original.label, givens)
            let answer = try self.solveVisibleSolidSection(prompt)
            if answer.numeric { self.enterNumericAnswer(answer.value, in: app) }
            else { self.chooseResponse(answer.value, in: app) }
            XCTAssertFalse(self.element(in: app, identifier: "solid-section-worked-explanation").exists)
        }
    }

    /// Computes only from the public solid bounds and plane equation. Cube
    /// vertices solve triples of constraint planes; quadrilaterals use diagonal
    /// midpoints and distances, independently of the app's edge traversal.
    private func solveVisibleSolidSection(_ prompt: String) throws -> (numeric: Bool, value: String) {
        func captures(_ pattern: String) throws -> [Double] {
            let regex = try NSRegularExpression(pattern: pattern)
            guard let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)) else {
                throw NSError(domain: "SolidSectionUI", code: 1)
            }
            return try (1..<match.numberOfRanges).map {
                guard let range = Range(match.range(at: $0), in: prompt), let value = Double(prompt[range]) else {
                    throw NSError(domain: "SolidSectionUI", code: 2)
                }
                return value
            }
        }
        let equation = try captures(#"The plane is (-?\d+)x \+ (-?\d+)y \+ (-?\d+)z = (-?\d+(?:\.\d+)?)\."#)
        let normal = Array(equation.prefix(3)), offset = equation[3]
        func near(_ a: Double, _ b: Double) -> Bool { abs(a-b) < 1e-8 }
        func distance(_ p: [Double], _ q: [Double]) -> Double { zip(p,q).map { ($0-$1)*($0-$1) }.reduce(0,+) }
        let shape: String
        if prompt.contains("closed solid ball") {
            let normSquared = normal.map { $0*$0 }.reduce(0,+)
            let squaredRadius = 9-offset*offset/normSquared
            if prompt.contains("square of that section's radius") {
                let denominator = Int(4*normSquared), numerator = 9*denominator-Int(2*offset)*Int(2*offset)
                return (true, "\(numerator)/\(denominator)")
            }
            shape = squaredRadius < 0 ? "No intersection" : near(squaredRadius,0) ? "One contact point" : "Circle"
        } else if prompt.contains("closed right circular cylinder") {
            let horizontalMagnitude = hypot(normal[0],normal[1])
            if near(horizontalMagnitude,0) {
                shape = abs(offset/normal[2]) <= 3 ? "Circle" : "No intersection"
            } else if near(normal[2],0) {
                let distance = abs(offset)/horizontalMagnitude
                shape = distance > 2 ? "No intersection" : near(distance,2) ? "A line segment only" : "Rectangle, not a square"
            } else {
                let centerHeight = offset/normal[2], amplitude = 2*horizontalMagnitude/abs(normal[2])
                let lower = centerHeight-amplitude, upper = centerHeight+amplitude
                if lower > 3 || upper < -3 { shape = "No intersection" }
                else if near(lower,3) || near(upper,-3) { shape = "One contact point" }
                else if lower >= -3 && upper <= 3 { shape = "Ellipse, not a circle" }
                else { shape = "Clipped ellipse with a curved boundary and a straight edge" }
            }
        } else {
            guard prompt.contains("closed cube") else { throw NSError(domain: "SolidSectionUI", code: 3) }
            var vertices: [[Double]] = []
            for free in 0..<3 where normal[free] != 0 {
                let fixed = (0..<3).filter { $0 != free }
                for first in [-2.0,2.0] { for second in [-2.0,2.0] {
                    var point = [0.0,0.0,0.0]; point[fixed[0]] = first; point[fixed[1]] = second
                    point[free] = (offset-normal[fixed[0]]*first-normal[fixed[1]]*second)/normal[free]
                    if point[free] >= -2 && point[free] <= 2 && !vertices.contains(where: { near(distance($0,point),0) }) { vertices.append(point) }
                } }
            }
            switch vertices.count {
            case 0: shape = "No intersection"
            case 1: shape = "One contact point"
            case 2: shape = "A line segment only"
            case 3: shape = "Triangle"
            case 5: shape = "Pentagon"
            case 6: shape = "Hexagon"
            case 4:
                var rectangle = false, rhombus = false
                for opposite in 1..<4 {
                    let others = (1..<4).filter { $0 != opposite }
                    let p = vertices[0], q = vertices[opposite], r = vertices[others[0]], s = vertices[others[1]]
                    guard (0..<3).allSatisfy({ near(p[$0]+q[$0],r[$0]+s[$0]) }) else { continue }
                    rectangle = near(distance(p,q),distance(r,s))
                    let sides = [distance(p,r),distance(p,s),distance(q,r),distance(q,s)]
                    rhombus = sides.allSatisfy { near($0,sides[0]) }
                }
                shape = rectangle ? (rhombus ? "Square" : "Rectangle, not a square") : rhombus ? "Rhombus, not a square" : "Other quadrilateral"
            default: throw NSError(domain: "SolidSectionUI", code: 4)
            }
        }
        if prompt.contains("A proposed slice must satisfy both conditions") {
            let q = try captures(#"Q = \((-?\d+(?:\.\d+)?), (-?\d+(?:\.\d+)?), (-?\d+(?:\.\d+)?)\)"#)
            let containsPoint = near(zip(normal,q).map(*).reduce(0,+),offset)
            let twoDimensional = !["No intersection","One contact point","A line segment only"].contains(shape)
            let matchesShape = prompt.contains("has the shape \(shape); and")
            return (false, containsPoint && twoDimensional && matchesShape ? "All stated conditions hold" : "At least one stated condition fails")
        }
        return (false,shape)
    }

    func testAsymmetricSolidPublicLaunchUsesVisibleProjectionOracleAndColdCompleteSet() throws {
        try spatialAssemblyJourney(title: "3D Object Rotation", orientation: true)
    }
    func testFeasibleReconstructionPublicLaunchUsesCompleteFiniteOracleAndColdAnswerSet() throws {
        try spatialAssemblyJourney(title: "Top-View Decoder", orientation: false)
    }

    private struct AssemblyPublicQuestion {
        let correct: [String]
        let allChoices: [String]
        let candidateSignatures: [String]
        let candidateHeights: [[Int]]
        let originalText: String
    }
    private func spatialAssemblyJourney(title: String, orientation: Bool) throws {
        #if os(iOS)
        let app = XCUIApplication(), runID = UUID().uuidString
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: true, startSession: false)
        app.launch(); defer { app.terminate() }
        let practice = primaryNavigation(in: app, destinationID: "train", expectedLabel: "Practice")
        XCTAssertTrue(practice.waitForExistence(timeout: 15)); practice.press(forDuration: 0.15)
        XCTAssertTrue(element(in: app, identifier: "destination-train").waitForExistence(timeout: 8))
        let spatial = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Spatial")).firstMatch
        XCTAssertTrue(revealResponseControl(spatial, in: app)); spatial.press(forDuration: 0.15)
        XCTAssertTrue(app.navigationBars["Spatial"].waitForExistence(timeout: 8))
        let activity = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(revealResponseControl(activity, in: app)); activity.press(forDuration: 0.15)
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 8))
        let five = app.buttons["5 questions"]
        XCTAssertTrue(revealResponseControl(five, in: app)); five.press(forDuration: 0.15); assertSelected(five)
        XCTAssertTrue(app.buttons["Start practice"].isEnabled, "The ordinary primary launch must remain available.")
        let launch = app.buttons["train-start-spatial-assembly"]
        XCTAssertTrue(revealResponseControl(launch, in: app)); XCTAssertGreaterThanOrEqual(launch.frame.height, 44)
        launch.press(forDuration: 0.15)
        XCTAssertTrue(element(in: app, identifier: "universal-session").waitForExistence(timeout: 15))
        resumeIfOffered(in: app)
        let position = element(in: app, identifier: "session-position")
        XCTAssertEqual(position.value as? String, "1 / 5")
        let prompt = element(in: app, identifier: "session-prompt").label
        let first = try readPublicAssembly(in: app, orientation: orientation)
        XCTAssertTrue(prompt.contains(first.originalText)); XCTAssertFalse(first.correct.isEmpty)
        XCTAssertFalse(app.buttons["spatial-assembly-show"].exists)
        XCTAssertFalse(element(in: app, identifier: "spatial-assembly-worked-model-0").exists)
        if orientation {
            let source = element(in: app, identifier: "spatial-assembly-source-model")
            XCTAssertTrue(revealResponseControl(source, in: app, searchAboveWhenAbsent: true))
            let sourceLabel = source.label
            XCTAssertEqual(try assemblyTuples(sourceLabel, arity: 3).count, 5)
            assemblyCapture(source, in: app, name: "assembly-original-solid-static")
            let camera = app.buttons["spatial-assembly-camera"]
            XCTAssertTrue(revealResponseControl(camera, in: app)); XCTAssertGreaterThanOrEqual(camera.frame.height, 44)
            camera.press(forDuration: 0.15); app.buttons["Top"].tap()
            XCTAssertTrue(camera.label.contains("Top"))
            XCTAssertEqual(source.label, sourceLabel)
            let mode = app.buttons["spatial-assembly-render-mode"]
            XCTAssertTrue(revealResponseControl(mode, in: app)); XCTAssertGreaterThanOrEqual(mode.frame.height, 44)
            mode.press(forDuration: 0.15)
            let nativeMode = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Static 2D"), object: mode)
            XCTAssertEqual(XCTWaiter.wait(for: [nativeMode], timeout: 5), .completed)
            assemblyCapture(source, in: app, name: "assembly-original-solid-native")
            XCTAssertEqual(source.label, sourceLabel)
            XCTAssertTrue(revealResponseControl(mode, in: app)); mode.press(forDuration: 0.15)
            let staticMode = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Interactive 3D"), object: mode)
            XCTAssertEqual(XCTWaiter.wait(for: [staticMode], timeout: 5), .completed)
            let reset = app.buttons["spatial-assembly-reset-view"]
            XCTAssertTrue(revealResponseControl(reset, in: app)); XCTAssertGreaterThanOrEqual(reset.frame.height, 44)
            reset.press(forDuration: 0.15)
            XCTAssertTrue(camera.label.contains("Authored view"))
        }
        for option in first.correct { chooseResponse(option, in: app) }
        saveAndClose(in: app); app.terminate()
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: false, startSession: false)
        app.launch(); continueSavedSession(in: app)
        XCTAssertEqual(element(in: app, identifier: "session-prompt").label, prompt)
        XCTAssertEqual(position.value as? String, "1 / 5")
        let restored = try readPublicAssembly(in: app, orientation: orientation)
        XCTAssertEqual(restored.originalText, first.originalText)
        XCTAssertEqual(restored.candidateSignatures, first.candidateSignatures)
        XCTAssertEqual(restored.candidateHeights, first.candidateHeights)
        for label in first.correct {
            let option = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
            XCTAssertTrue(revealResponseControl(option, in: app)); assertSelected(option)
        }
        XCTAssertFalse(app.buttons["spatial-assembly-show"].exists)
        submitVisibleResponse(in: app)
        try inspectAssemblyFeedback(in: app, question: first, orientation: orientation, expected: "Correct")
        saveAndClose(in: app); app.terminate(); app.launch(); continueSavedSession(in: app)
        XCTAssertEqual(element(in: app, identifier: "session-prompt").label, prompt)
        let savedFeedback = element(in: app, identifier: "session-feedback-title")
        XCTAssertTrue(revealResponseControl(savedFeedback, in: app)); XCTAssertEqual(savedFeedback.label, "Correct")
        let next = element(in: app, identifier: "session-next")
        XCTAssertTrue(revealResponseControl(next, in: app)); next.press(forDuration: 0.15)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "2 / 5"), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 8), .completed)
        let second = try readPublicAssembly(in: app, orientation: orientation)
        XCTAssertFalse(app.buttons["spatial-assembly-show"].exists)
        let falsePositive = try XCTUnwrap(second.allChoices.first { !second.correct.contains($0) })
        for option in second.correct + [falsePositive] { chooseResponse(option, in: app) }
        submitVisibleResponse(in: app)
        try inspectAssemblyFeedback(in: app, question: second, orientation: orientation, expected: "Incorrect")
        XCTAssertEqual(position.value as? String, "2 / 5")
        XCTAssertTrue(revealResponseControl(next, in: app)); next.press(forDuration: 0.15)
        let third = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "3 / 5"), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [third], timeout: 8), .completed)
        XCTAssertTrue(element(in: app, identifier: "session-submit").exists)
        #else
        throw XCTSkip("Spatial assembly journeys require the installed iOS application.")
        #endif
    }

    private func assemblyCapture(_ model: XCUIElement, in app: XCUIApplication, name: String) {
        XCTAssertTrue(revealResponseControl(model, in: app, maximumSwipes: 32, searchAboveWhenAbsent: true))
        XCTAssertTrue(model.isHittable); XCTAssertGreaterThanOrEqual(model.frame.height, 150)
        let top = app.navigationBars.allElementsBoundByIndex.filter(\.isHittable).map(\.frame.maxY).max() ?? app.frame.minY
        let footerTops = ["session-submit", "session-next"].map { element(in: app, identifier: $0) }
            .filter { $0.exists && $0.isHittable }.map(\.frame.minY)
        let bottom = footerTops.min() ?? app.frame.maxY
        XCTAssertGreaterThanOrEqual(model.frame.minY, top, "The entire model must be below native navigation.")
        XCTAssertLessThanOrEqual(model.frame.maxY, bottom, "The entire model must be above the fixed session footer.")
        let geometry = XCTAttachment(string: "Model \(model.identifier) bounds=\(model.frame); visible=\(top)...\(bottom)\nPublic description: \(model.label)")
        geometry.name = name + "-visible-model-bounds"; geometry.lifetime = .keepAlways; add(geometry)
        let capture = XCTAttachment(screenshot: model.screenshot())
        capture.name = name + "-model-en"; capture.lifetime = .keepAlways; add(capture)
        let contextual = XCTAttachment(screenshot: app.screenshot())
        contextual.name = name + "-page-en"; contextual.lifetime = .keepAlways; add(contextual)
    }
    private func inspectAssemblyFeedback(in app: XCUIApplication, question: AssemblyPublicQuestion,
                                         orientation: Bool, expected: String) throws {
        let heading = element(in: app, identifier: "session-feedback-title")
        XCTAssertTrue(revealResponseControl(heading, in: app)); XCTAssertEqual(heading.label, expected)
        XCTAssertEqual(element(in: app, identifier: "spatial-assembly-original").label, question.originalText)
        let show = app.buttons["spatial-assembly-show"]
        XCTAssertTrue(revealResponseControl(show, in: app, maximumSwipes: 32, searchAboveWhenAbsent: true))
        XCTAssertGreaterThanOrEqual(show.frame.height, 44); show.press(forDuration: 0.15)
        let explanation = element(in: app, identifier: "spatial-assembly-worked")
        XCTAssertTrue(revealResponseControl(explanation, in: app)); XCTAssertFalse(explanation.label.isEmpty)
        for i in question.candidateSignatures.indices {
            let model = element(in: app, identifier: "spatial-assembly-worked-model-\(i)")
            XCTAssertTrue(revealResponseControl(model, in: app))
            let cells = try assemblyTuples(model.label, arity: 3)
            XCTAssertEqual(assemblySignature(cells), question.candidateSignatures[i], "The worked solid must project to the exact public candidate.")
            if !orientation {
                let h = (0..<4).map { j in cells.filter { $0[0] == j % 2 && $0[1] == j / 2 }.count }
                XCTAssertEqual(h, question.candidateHeights[i])
            }
            if i == 0 { assemblyCapture(model, in: app, name: "assembly-worked-\(orientation ? "orientation":"reconstruction")-\(expected)") }
        }
        XCTAssertEqual(element(in: app, identifier: "spatial-assembly-original").label, question.originalText)
        let reset = app.buttons["spatial-assembly-reset"]
        XCTAssertTrue(revealResponseControl(reset, in: app, maximumSwipes: 32, searchAboveWhenAbsent: true))
        XCTAssertGreaterThanOrEqual(reset.frame.height, 44); reset.press(forDuration: 0.15)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: explanation)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        XCTAssertEqual(element(in: app, identifier: "spatial-assembly-original").label, question.originalText)
    }

    /// All inputs come from visible labels and supplied candidate grids. This
    /// test target does not import the application module or read a saved key.
    private func readPublicAssembly(in app: XCUIApplication, orientation: Bool) throws -> AssemblyPublicQuestion {
        let original = element(in: app, identifier: "spatial-assembly-original")
        XCTAssertTrue(original.waitForExistence(timeout: 8)); let source = original.label
        XCTAssertFalse(source.isEmpty)
        // Start each scan at the supplied givens, including after cold resume
        // or Next. Lazy candidate projections below this anchor need forward
        // scrolling; their absence is not evidence that they are above us.
        XCTAssertTrue(revealResponseControl(original, in: app, maximumSwipes: 48, searchAboveWhenAbsent: true))
        var signatures: [String] = [], heights: [[Int]] = []
        let count = orientation ? 4 : 8
        for i in 0..<count {
            if orientation {
                let front = element(in: app, identifier: "spatial-assembly-candidate-\(i)-front")
                let side = element(in: app, identifier: "spatial-assembly-candidate-\(i)-side")
                XCTAssertTrue(revealResponseControl(front, in: app, maximumSwipes: 32))
                let f = try assemblyTuples(front.label, arity: 2)
                if i == 0 {
                    assemblyCapture(element(in: app, identifier: "spatial-assembly-candidate-0-front-model"), in: app, name: "assembly-public-occluded-front")
                }
                XCTAssertTrue(revealResponseControl(side, in: app))
                let s = try assemblyTuples(side.label, arity: 2)
                XCTAssertFalse(f.isEmpty); XCTAssertFalse(s.isEmpty)
                signatures.append(assemblyRayKey(f) + "/" + assemblyRayKey(s))
                if i == 0 {
                    assemblyCapture(element(in: app, identifier: "spatial-assembly-candidate-0-side-model"), in: app, name: "assembly-public-occluded-side")
                }
            } else {
                let label = element(in: app, identifier: "spatial-assembly-candidate-heights-\(i)")
                XCTAssertTrue(revealResponseControl(label, in: app, maximumSwipes: 32))
                let rows = try assemblyMatches(label.label, pattern: #"\((\d+),(\d+)\): (\d+)"#)
                XCTAssertEqual(rows.count, 4)
                var h = Array(repeating: -1, count: 4)
                for row in rows { guard row[0] < 2, row[1] < 2 else { throw NSError(domain: "AssemblyUI", code: 1) }; h[row[1] * 2 + row[0]] = row[2] }
                XCTAssertTrue(h.allSatisfy { (0...3).contains($0) }); heights.append(h)
                signatures.append(assemblySignature(assemblyCells(h)))
                if i == 0 { assemblyCapture(element(in: app, identifier: "spatial-assembly-candidate-model-0"), in: app, name: "assembly-public-height-candidate") }
            }
        }
        var accepted: [Int] = []
        if orientation {
            let cells = try assemblyTuples(source, arity: 3)
            XCTAssertEqual(cells.count, 5)
            let proper = assemblyOrientations(cells)
            XCTAssertEqual(proper.count, 24)
            let valid = Set(proper.map(assemblySignature))
            accepted = signatures.indices.filter { valid.contains(signatures[$0]) }
        } else {
            let topLine = try XCTUnwrap(source.components(separatedBy: "\n").first { $0.hasPrefix("Top occupied columns:") })
            let top = Set(try assemblyTuples(topLine, arity: 2))
            let front = try integers(in: source, pattern: #"Front heights at x=0,1: (\d+), (\d+)"#)
            let side = try integers(in: source, pattern: #"Side heights at y=0,1: (\d+), (\d+)"#)
            let total = try integers(in: source, pattern: #"Total cubes: (\d+)"#)[0]
            var feasible: Set<[Int]> = []
            for a in 0...3 { for b in 0...3 { for c in 0...3 { for d in 0...3 {
                let h = [a,b,c,d]
                let occupied = Set(h.indices.filter { h[$0] > 0 }.map { [$0 % 2, $0 / 2] })
                if occupied == top, assemblyConnected(h), [max(a,c),max(b,d)] == front,
                    [max(a,b),max(c,d)] == side, a+b+c+d == total { feasible.insert(h) }
            }}}}
            XCTAssertTrue(feasible.isSubset(of: Set(heights)), "The actual candidate list must contain every feasible arrangement.")
            accepted = heights.indices.filter { feasible.contains(heights[$0]) }
        }
        var all = (0..<count).map { "Candidate " + String(UnicodeScalar(65 + $0)!) }
        if !orientation { all.append("No arrangement satisfies all constraints") }
        let correct = accepted.isEmpty && !orientation ? ["No arrangement satisfies all constraints"] : accepted.map { all[$0] }
        if orientation { XCTAssertFalse(accepted.isEmpty); XCTAssertLessThan(accepted.count, 4) }
        let proof = XCTAttachment(string: source + "\nPublic signatures: \(signatures)\nPublic heights: \(heights)\nIndependent complete answer: \(correct)")
        proof.name = "assembly-public-givens-oracle-en"; proof.lifetime = .keepAlways; add(proof)
        return AssemblyPublicQuestion(correct: correct, allChoices: all, candidateSignatures: signatures, candidateHeights: heights, originalText: source)
    }
    private func assemblyMatches(_ text: String, pattern: String) throws -> [[Int]] {
        let regex = try NSRegularExpression(pattern: pattern)
        return try regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).map { match in
            try (1..<match.numberOfRanges).map { i in
                guard let range = Range(match.range(at: i), in: text), let value = Int(text[range]) else { throw NSError(domain: "AssemblyUI", code: 2) }
                return value
            }
        }
    }
    private func assemblyTuples(_ text: String, arity: Int) throws -> [[Int]] {
        try assemblyMatches(text, pattern: arity == 3 ? #"\((-?\d+),\s*(-?\d+),\s*(-?\d+)\)"# : #"\((-?\d+),\s*(-?\d+)\)"#)
    }
    private func assemblyRayKey(_ rays: [[Int]]) -> String { Set(rays.map { "\($0[0]):\($0[1])" }).sorted().joined(separator: ";") }
    private func assemblySignature(_ cells: [[Int]]) -> String {
        assemblyRayKey(cells.map { [$0[0], $0[2]] }) + "/" + assemblyRayKey(cells.map { [$0[1], $0[2]] })
    }
    private func assemblyCells(_ heights: [Int]) -> [[Int]] {
        heights.enumerated().flatMap { i, count in (0..<count).map { [i % 2, i / 2, $0] } }
    }
    private func assemblyConnected(_ h: [Int]) -> Bool {
        let occupied = Set(h.indices.filter { h[$0] > 0 }); guard let first = occupied.first else { return false }
        var seen: Set<Int> = [first], pending = [first]
        while let i = pending.popLast() { for j in occupied where abs(i % 2 - j % 2) + abs(i / 2 - j / 2) == 1 {
            if seen.insert(j).inserted { pending.append(j) }
        }}
        return seen == occupied
    }
    private func assemblyOrientations(_ source: [[Int]]) -> Set<[[Int]]> {
        func normalize(_ cells: [[Int]]) -> [[Int]] {
            let minimum = (0..<3).map { axis in cells.map { $0[axis] }.min()! }
            return cells.map { zip($0, minimum).map(-) }.sorted { $0.lexicographicallyPrecedes($1) }
        }
        let first = normalize(source); var seen: Set<[[Int]]> = [first], pending = [first]
        while let cells = pending.popLast() {
            for rotated in [cells.map { [$0[0], -$0[2], $0[1]] }, cells.map { [-$0[1], $0[0], $0[2]] }] {
                let next = normalize(rotated); if seen.insert(next).inserted { pending.append(next) }
            }
        }
        return seen
    }

    func testExplicitAffineInferenceFixtureSavesSixTypedCoefficientsThroughColdHistory() throws {
        try coordinateBranchFixtureJourney(query: "inferAffine", activity: "nf.default.spatial.coordinate-rotation")
    }
    func testExplicitOrientationFixedLocusFixtureSavesBothScoredChoicesThroughColdHistory() throws {
        try coordinateBranchFixtureJourney(query: "orientationFixed", activity: "nf.default.spatial.vector-reflection")
    }

    /// Explicit deterministic ordinary fixture coverage. The separate public
    /// launch tests continue to establish the secondary-button navigation.
    private func coordinateBranchFixtureJourney(query: String, activity: String) throws {
        #if os(iOS)
        let app = XCUIApplication(), runID = UUID().uuidString
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: true, startSession: false)
            + ["-ui-test-activity", activity, "-ui-test-coordinate-reasoning-query", query]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(element(in: app, identifier: "universal-session").waitForExistence(timeout: 20))
        resumeIfOffered(in: app)
        let promptElement = element(in: app, identifier: "session-prompt")
        XCTAssertTrue(promptElement.waitForExistence(timeout: 8)); let prompt = promptElement.label
        let original = element(in: app, identifier: "coordinate-reasoning-original")
        XCTAssertTrue(original.waitForExistence(timeout: 8)); let originalText = original.label
        XCTAssertTrue(prompt.contains(originalText)); XCTAssertFalse(originalText.isEmpty)
        let solved = try solvePublicAdvancedCoordinate(prompt)
        let labels: [String: String]
        let entered: [String: String]
        if query == "inferAffine" {
            XCTAssertTrue(prompt.contains("Find the six coefficients"))
            XCTAssertEqual(Set(solved.numbers.keys), ["a", "b", "c", "d", "tx", "ty"])
            XCTAssertTrue(solved.options.isEmpty)
            labels = Dictionary(uniqueKeysWithValues: solved.numbers.keys.map { key in
                (key, key + (["tx", "ty"].contains(key) ? " (grid units)" : " (unitless coefficient)"))
            })
            // Preserve a mathematically equivalent but noncanonical decimal
            // response so history cannot substitute the canonical answer key.
            entered = solved.numbers.mapValues { String($0) + ".0" }
            for key in entered.keys.sorted() {
                enterText(try XCTUnwrap(entered[key]), in: app.textFields["Response for " + (try XCTUnwrap(labels[key]))], app: app, minimumHeight: 44)
            }
        } else {
            XCTAssertTrue(prompt.contains("Select exactly two statements"))
            XCTAssertTrue(solved.numbers.isEmpty); XCTAssertEqual(solved.options.count, 2)
            XCTAssertEqual(solved.options.filter { $0.contains("orientation") }.count, 1)
            labels = [:]; entered = [:]
            for option in solved.options { chooseResponse(option, in: app) }
        }
        let proof = XCTAttachment(string: "Explicit ordinary fixture kind: \(query)\nPublic prompt:\n\(prompt)\nIndependent numerical solution: \(solved.numbers)\nOriginal entered text: \(entered)\nIndependent complete choice set: \(solved.options)")
        proof.name = "coordinate-branch-fixture-public-oracle-\(query)"; proof.lifetime = .keepAlways; add(proof)
        XCTAssertFalse(app.buttons["coordinate-reasoning-show"].exists)
        XCTAssertFalse(element(in: app, identifier: "coordinate-reasoning-worked").exists)
        saveAndClose(in: app); app.terminate()
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: false, startSession: false)
        app.launch(); continueSavedSession(in: app)
        XCTAssertEqual(promptElement.label, prompt); XCTAssertEqual(original.label, originalText)
        XCTAssertEqual(element(in: app, identifier: "session-position").value as? String, "1 / 5")
        for key in entered.keys.sorted() {
            let field = app.textFields["Response for " + (try XCTUnwrap(labels[key]))]
            XCTAssertTrue(revealResponseControl(field, in: app)); XCTAssertEqual(field.value as? String, entered[key]); XCTAssertTrue(field.isEnabled)
        }
        for option in solved.options {
            let choice = app.buttons.matching(NSPredicate(format: "label == %@", option)).firstMatch
            XCTAssertTrue(revealResponseControl(choice, in: app)); assertSelected(choice); XCTAssertTrue(choice.isEnabled)
        }
        XCTAssertFalse(app.buttons["coordinate-reasoning-show"].exists)
        submitVisibleResponse(in: app)
        let heading = element(in: app, identifier: "session-feedback-title")
        XCTAssertTrue(revealResponseControl(heading, in: app)); XCTAssertEqual(heading.label, "Correct")
        XCTAssertEqual(promptElement.label, prompt); XCTAssertEqual(original.label, originalText)
        for key in entered.keys.sorted() {
            let field = app.textFields["Response for " + (try XCTUnwrap(labels[key]))]
            XCTAssertEqual(field.value as? String, entered[key]); XCTAssertFalse(field.isEnabled)
        }
        for option in solved.options { XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", option)).firstMatch.isEnabled) }
        let show = app.buttons["coordinate-reasoning-show"]
        XCTAssertTrue(revealResponseControl(show, in: app, searchAboveWhenAbsent: true)); XCTAssertGreaterThanOrEqual(show.frame.height, 44)
        show.press(forDuration: 0.15)
        let worked = element(in: app, identifier: "coordinate-reasoning-worked")
        XCTAssertTrue(worked.waitForExistence(timeout: 8)); XCTAssertFalse(worked.label.isEmpty)
        XCTAssertEqual(original.label, originalText)
        let feedbackProof = XCTAttachment(string: "Original retained givens:\n\(originalText)\nCommitted worked output:\n\(worked.label)\nActual feedback: \(heading.label)")
        feedbackProof.name = "coordinate-branch-acknowledged-worked-\(query)"; feedbackProof.lifetime = .keepAlways; add(feedbackProof)
        let reset = app.buttons["coordinate-reasoning-reset"]
        XCTAssertTrue(revealResponseControl(reset, in: app, searchAboveWhenAbsent: true)); reset.press(forDuration: 0.15)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: worked)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        let next = element(in: app, identifier: "session-next")
        XCTAssertTrue(revealResponseControl(next, in: app)); next.press(forDuration: 0.15)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "2 / 5"), object: element(in: app, identifier: "session-position"))
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 8), .completed)
        saveAndClose(in: app); app.terminate(); app.launch()
        XCTAssertTrue(element(in: app, identifier: "destination-today").waitForExistence(timeout: 15))
        primaryNavigation(in: app, destinationID: "progress", expectedLabel: "Progress").press(forDuration: 0.15)
        let sections = element(in: app, identifier: "progress-section-picker")
        XCTAssertTrue(sections.waitForExistence(timeout: 8)); sections.buttons["History"].press(forDuration: 0.15)
        let open = app.buttons["Open answer history"]
        XCTAssertTrue(scrollUntilHittable(open, in: app)); open.press(forDuration: 0.15)
        XCTAssertTrue(app.navigationBars["Answer history"].waitForExistence(timeout: 8))
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", prompt))
        XCTAssertTrue(scrollUntilHittable(rows.firstMatch, in: app)); XCTAssertEqual(rows.count, 1)
        rows.firstMatch.press(forDuration: 0.15)
        XCTAssertTrue(app.navigationBars["Answer review"].waitForExistence(timeout: 8))
        XCTAssertEqual(original.label, originalText)
        let savedHeading = app.staticTexts["Your saved answer"]
        XCTAssertTrue(revealResponseControl(savedHeading, in: app, maximumSwipes: 32))
        if !entered.isEmpty {
            let exact = entered.keys.sorted().map { (labels[$0] ?? "") + ": " + (entered[$0] ?? "") }.joined(separator: "\n")
            let text = app.staticTexts.matching(NSPredicate(format: "label == %@", exact)).firstMatch
            XCTAssertTrue(revealResponseControl(text, in: app)); XCTAssertEqual(text.label, exact)
        } else {
            let savedChoices = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", solved.options[0], solved.options[1])).firstMatch
            XCTAssertTrue(revealResponseControl(savedChoices, in: app)); XCTAssertFalse(savedChoices.label.isEmpty)
        }
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "coordinate-explicit-branch-cold-readable-history-\(query)-en"; capture.lifetime = .keepAlways; add(capture)
        #else
        throw XCTSkip("Explicit coordinate branch fixtures require the isolated installed iOS application.")
        #endif
    }

    func testAdvancedCoordinatePublicLaunchSavesOriginalAnswerAndSeparateWorkedMap() throws {
        try advancedCoordinateJourney(title: "Coordinate Rotation")
    }

    func testAdvancedReflectionPublicLaunchSavesOriginalAnswerAndSeparateWorkedMap() throws {
        try advancedCoordinateJourney(title: "Vector Reflection")
    }

    private func advancedCoordinateJourney(title: String) throws {
        try exerciseLabResponse(activity: title == "Coordinate Rotation" ? "spatial.coordinate-rotation" : "spatial.vector-reflection",
            promptFragment: "Coordinates use grid units", expectedFeedback: "Correct", coordinateReasoningTitle: title,
            afterFeedback: { app, prompt in
                let original = self.element(in: app, identifier: "coordinate-reasoning-original")
                let originalText = original.label
                XCTAssertTrue(prompt.contains(originalText)); XCTAssertFalse(originalText.isEmpty)
                let show = app.buttons["coordinate-reasoning-show"]
                XCTAssertTrue(self.revealResponseControl(show, in: app, searchAboveWhenAbsent: true))
                XCTAssertGreaterThanOrEqual(show.frame.height, 44); show.press(forDuration: 0.15)
                let worked = self.element(in: app, identifier: "coordinate-reasoning-worked")
                XCTAssertTrue(self.revealResponseControl(worked, in: app))
                XCTAssertFalse(worked.label.isEmpty)
                XCTAssertEqual(original.label, originalText)
                let capture = XCTAttachment(screenshot: app.screenshot())
                capture.name = "advanced-coordinate-worked-\(title)-en"; capture.lifetime = .keepAlways; self.add(capture)
                let reset = app.buttons["coordinate-reasoning-reset"]
                XCTAssertTrue(self.revealResponseControl(reset, in: app, searchAboveWhenAbsent: true))
                XCTAssertGreaterThanOrEqual(reset.frame.height, 44); reset.press(forDuration: 0.15)
                let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: worked)
                XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
                XCTAssertEqual(original.label, originalText)
            }) { app, prompt in
                let original = self.element(in: app, identifier: "coordinate-reasoning-original")
                XCTAssertTrue(original.exists); XCTAssertFalse(original.label.isEmpty)
                XCTAssertTrue(prompt.contains(original.label))
                XCTAssertFalse(app.buttons["coordinate-reasoning-show"].exists)
                XCTAssertFalse(self.element(in: app, identifier: "coordinate-reasoning-worked").exists)
                let solution = try self.solvePublicAdvancedCoordinate(prompt)
                XCTAssertFalse(solution.numbers.isEmpty && solution.options.isEmpty)
                let proof = XCTAttachment(string: "Public givens:\n\(prompt)\nIndependent numeric answer: \(solution.numbers)\nIndependent options: \(solution.options)")
                proof.name = "advanced-coordinate-public-oracle-\(title)-en"; proof.lifetime = .keepAlways; self.add(proof)
                for (key, value) in solution.numbers.sorted(by: { $0.key < $1.key }) {
                    let units = ["x", "y", "tx", "ty"].contains(key) ? "grid units" : "unitless coefficient"
                    self.enterText(String(value), in: app.textFields["Response for \(key) (\(units))"], app: app, minimumHeight: 44)
                }
                for option in solution.options { self.chooseResponse(option, in: app) }
            }
    }

    /// Reconstructs the response from the visible problem, never the generated
    /// recipe, accepted IDs, saved archive, or application scoring implementation.
    private func solvePublicAdvancedCoordinate(_ prompt: String) throws -> (numbers: [String: Int], options: [String]) {
        func apply(_ point: (Double, Double), operation: String, inverse: Bool) throws -> (Double, Double) {
            let (x, y) = point
            if operation.contains("Rotate actively") {
                let angle = try integers(in: operation, pattern: #"Rotate actively (\d+)°"#)[0]
                let center = try integers(in: operation, pattern: #"about \((-?\d+), (-?\d+)\)"#)
                let radians = Double(angle) * .pi / 180 * (operation.contains("counterclockwise") ? 1 : -1) * (inverse ? -1 : 1)
                let dx = x - Double(center[0]), dy = y - Double(center[1])
                return (Double(center[0]) + cos(radians) * dx - sin(radians) * dy,
                        Double(center[1]) + sin(radians) * dx + cos(radians) * dy)
            }
            if operation.contains("Translate by") {
                let shift = try integers(in: operation, pattern: #"Translate by \((-?\d+), (-?\d+)\)"#)
                return (x + Double(shift[0]) * (inverse ? -1 : 1), y + Double(shift[1]) * (inverse ? -1 : 1))
            }
            if operation.contains("Reflect across") {
                if operation.contains("y = −x") { return (-y, -x) }
                if operation.contains("y = x") { return (y, x) }
                if operation.contains("x = ") { return (Double(2 * (try integers(in: operation, pattern: #"x = (-?\d+)"#)[0])) - x, y) }
                return (x, Double(2 * (try integers(in: operation, pattern: #"y = (-?\d+)"#)[0])) - y)
            }
            throw NSError(domain: "AdvancedCoordinateUI", code: 1)
        }
        let operations = prompt.components(separatedBy: "\n").filter { $0.range(of: #"^\d+\. "#, options: .regularExpression) != nil }
        if prompt.contains("Recover the original point P") {
            let final = try integers(in: prompt, pattern: #"Q = \((-?\d+), (-?\d+)\)"#)
            var point = (Double(final[0]), Double(final[1]))
            XCTAssertFalse(operations.isEmpty)
            for operation in operations.reversed() { point = try apply(point, operation: operation, inverse: true) }
            return (["x": Int(point.0.rounded()), "y": Int(point.1.rounded())], [])
        }
        if prompt.contains("Find the six coefficients") {
            let rows = try ["A", "B", "C"].map { label in
                try integers(in: prompt, pattern: label + #": \((-?\d+), (-?\d+)\) → \((-?\d+), (-?\d+)\)"#)
            }
            // Eliminate the public augmented 3×5 matrix to solve the two
            // affine coordinate equations simultaneously.
            var matrix = rows.map { [Double($0[0]), Double($0[1]), 1, Double($0[2]), Double($0[3])] }
            for column in 0..<3 {
                guard let pivot = (column..<3).max(by: { abs(matrix[$0][column]) < abs(matrix[$1][column]) }), abs(matrix[pivot][column]) > 1e-9 else {
                    throw NSError(domain: "AdvancedCoordinateUI", code: 2)
                }
                matrix.swapAt(column, pivot)
                let divisor = matrix[column][column]
                for j in column..<5 { matrix[column][j] /= divisor }
                for row in 0..<3 where row != column {
                    let factor = matrix[row][column]
                    for j in column..<5 { matrix[row][j] -= factor * matrix[column][j] }
                }
            }
            let values = ["a": matrix[0][3], "b": matrix[1][3], "tx": matrix[2][3],
                          "c": matrix[0][4], "d": matrix[1][4], "ty": matrix[2][4]]
            for value in values.values { XCTAssertLessThan(abs(value - value.rounded()), 1e-9) }
            return (values.mapValues { Int($0.rounded()) }, [])
        }
        guard prompt.contains("Select exactly two statements"), !operations.isEmpty else {
            throw NSError(domain: "AdvancedCoordinateUI", code: 3)
        }
        func map(_ point: (Double, Double)) throws -> (Double, Double) {
            var output = point
            for operation in operations { output = try apply(output, operation: operation, inverse: false) }
            return output
        }
        let origin = try map((0, 0)), e1 = try map((1, 0)), e2 = try map((0, 1))
        let a = e1.0 - origin.0, b = e2.0 - origin.0, c = e1.1 - origin.1, d = e2.1 - origin.1
        let orientation = a * d - b * c > 0 ? "The orientation of A→B→C is preserved." : "The orientation of A→B→C is reversed."
        let rows = [[a - 1, b, -origin.0], [c, d - 1, -origin.1]]
        let nearZero: (Double) -> Bool = { abs($0) < 1e-8 }
        let determinant = rows[0][0] * rows[1][1] - rows[0][1] * rows[1][0]
        let locus: String
        if !nearZero(determinant) { locus = "Exactly one point in the plane is fixed." }
        else if rows.allSatisfy({ nearZero($0[0]) && nearZero($0[1]) }) {
            locus = rows.allSatisfy({ nearZero($0[2]) }) ? "Every point in the plane is fixed." : "There are no fixed points in the plane."
        } else {
            let consistent = nearZero(rows[0][0] * rows[1][2] - rows[0][2] * rows[1][0])
                && nearZero(rows[0][1] * rows[1][2] - rows[0][2] * rows[1][1])
            locus = consistent ? "The fixed points form exactly one complete straight line." : "There are no fixed points in the plane."
        }
        return ([:], [orientation, locus])
    }

    func testSpatialCoordinateEntryRetainsOriginalAndWorkedCopyAfterFeedback() throws {
        try coordinateTransformationJourney(activity: "spatial.coordinate-rotation")
    }

    func testSpatialReflectionEntryRetainsOriginalAndWorkedCopyAfterFeedback() throws {
        try coordinateTransformationJourney(activity: "spatial.vector-reflection")
    }

    private func coordinateTransformationJourney(activity: String) throws {
        try exerciseLabResponse(activity: activity, promptFragment: "axes stay fixed", expectedFeedback: "Correct", afterFeedback: { app, prompt in
            let expected = try self.solveVisibleCoordinateOperations(prompt)
            let original = self.element(in: app, identifier: "coordinate-transform-original")
            let originalLabel = original.label
            let copy = self.element(in: app, identifier: "coordinate-transform-copy")
            let step = app.buttons["coordinate-transform-step"]
            for _ in prompt.components(separatedBy: "\n").filter({ $0.range(of: #"^\d+\. "#, options: .regularExpression) != nil }) {
                XCTAssertTrue(self.revealResponseControl(step, in: app, searchAboveWhenAbsent: true))
                XCTAssertGreaterThanOrEqual(step.frame.height, 44); XCTAssertTrue(step.isEnabled)
                step.tap()
            }
            XCTAssertTrue(self.revealResponseControl(copy, in: app))
            XCTAssertTrue(copy.label.contains("P = (\(expected.0), \(expected.1))"))
            XCTAssertFalse(step.isEnabled)
            let replay = XCTAttachment(screenshot: app.screenshot())
            replay.name = "coordinate-worked-copy-\(activity)-en"; replay.lifetime = .keepAlways; self.add(replay)
            let reset = app.buttons["coordinate-transform-reset"]
            XCTAssertTrue(self.revealResponseControl(reset, in: app)); XCTAssertGreaterThanOrEqual(reset.frame.height, 44)
            reset.tap()
            let givens = try self.integers(in: prompt, pattern: #"Point P starts at \((-?\d+), (-?\d+)\)"#)
            XCTAssertTrue(copy.label.contains("P = (\(givens[0]), \(givens[1]))"))
            XCTAssertEqual(original.label, originalLabel)
            for (axis, value) in [("x", expected.0), ("y", expected.1)] {
                let field = app.textFields["Response for \(axis) (grid units)"]
                XCTAssertTrue(self.revealResponseControl(field, in: app))
                XCTAssertEqual(field.value as? String, String(value)); XCTAssertFalse(field.isEnabled)
            }
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "coordinate-reset-retains-saved-response-\(activity)-en"; capture.lifetime = .keepAlways; self.add(capture)
        }) { app, prompt in
            XCTAssertTrue(self.element(in: app, identifier: "coordinate-transform-original").exists)
            XCTAssertTrue(self.element(in: app, identifier: "coordinate-transform-units").exists)
            XCTAssertFalse(app.buttons["coordinate-transform-step"].exists)
            XCTAssertFalse(self.element(in: app, identifier: "coordinate-transform-copy").exists)
            let expected = try self.solveVisibleCoordinateOperations(prompt)
            self.enterText(String(expected.0), in: app.textFields["Response for x (grid units)"], app: app, minimumHeight: 44)
            self.enterText(String(expected.1), in: app.textFields["Response for y (grid units)"], app: app, minimumHeight: 44)
            for label in ["Use a hint", "Skip — no score"] {
                let control = app.buttons[label]
                XCTAssertTrue(self.revealResponseControl(control, in: app))
                XCTAssertGreaterThanOrEqual(control.frame.height, 44)
                XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            }
            let confidence = app.buttons["Confidence (optional)"]
            if confidence.exists {
                XCTAssertTrue(self.revealResponseControl(confidence, in: app, searchAboveWhenAbsent: true))
                XCTAssertGreaterThanOrEqual(confidence.frame.height, 44)
            }
            let controls = XCTAttachment(string: app.debugDescription)
            controls.name = "coordinate-answer-utility-targets-\(activity)-en"
            controls.lifetime = .keepAlways; self.add(controls)
        }
    }

    /// Independent solution from public givens only; no fixture seed, saved key,
    /// generator implementation, or hidden app state supplies the response.
    private func solveVisibleCoordinateOperations(_ prompt: String) throws -> (Int, Int) {
        let start = try integers(in: prompt, pattern: #"Point P starts at \((-?\d+), (-?\d+)\)"#)
        var x = start[0], y = start[1]
        let operations = prompt.components(separatedBy: "\n").filter { $0.range(of: #"^\d+\. "#, options: .regularExpression) != nil }
        XCTAssertFalse(operations.isEmpty)
        for operation in operations {
            if operation.contains("Rotate actively") {
                let angle = try integers(in: operation, pattern: #"Rotate actively (\d+)°"#)[0]
                let center = try integers(in: operation, pattern: #"C = \((-?\d+), (-?\d+)\)"#)
                let radians = Double(angle) * .pi / 180 * (operation.contains("counterclockwise") ? 1 : -1)
                let dx = Double(x - center[0]), dy = Double(y - center[1])
                x = center[0] + Int((cos(radians) * dx - sin(radians) * dy).rounded())
                y = center[1] + Int((sin(radians) * dx + cos(radians) * dy).rounded())
            } else if operation.contains("Translate by") {
                let vector = try integers(in: operation, pattern: #"vector \((-?\d+), (-?\d+)\)"#)
                x += vector[0]; y += vector[1]
            } else if operation.contains("Reflect") {
                if operation.contains("y = −x") { (x, y) = (-y, -x) }
                else if operation.contains("y = x") { (x, y) = (y, x) }
                else if operation.contains("x = ") { x = 2 * (try integers(in: operation, pattern: #"x = (-?\d+)"#)[0]) - x }
                else { y = 2 * (try integers(in: operation, pattern: #"y = (-?\d+)"#)[0]) - y }
            } else {
                XCTFail("Unsupported visible coordinate operation: \(operation)")
                throw NSError(domain: "CoordinateTransformUI", code: 1)
            }
        }
        return (x, y)
    }

    func testRetrievalFigureUsesItsVisibleSourceDataForTheSavedAnswer() throws {
        try exerciseLabResponse(activity: "retrieval.figure", promptFragment: "", expectedFeedback: "Correct") { app, prompt in
            XCTAssertTrue(self.element(in: app, identifier: "retrieval-source-figure").exists)
            let labels = Set(app.descendants(matching: .any).allElementsBoundByIndex.map(\.label))
            let answer: Int
            let firstRow: XCUIElement
            if prompt.contains("arithmetic mean") {
                let rows = labels.filter { $0.hasPrefix("Observation:") && $0.contains("Value (unitless):") }.sorted()
                XCTAssertEqual(rows.count, 3)
                let values = try rows.flatMap { try self.integers(in: $0, pattern: #"Value \(unitless\): (\d+)"#) }
                XCTAssertEqual(values.count, 3)
                guard values.count == 3 else { throw NSError(domain: "RetrievalFigureUI", code: 1) }
                answer = values.reduce(0, +) / 3
                firstRow = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", rows[0])).firstMatch
            } else if prompt.contains("slope") {
                let rows = labels.filter { $0.hasPrefix("Point:") && $0.contains("x (unitless):") }.sorted()
                XCTAssertEqual(rows.count, 2)
                let values = try rows.map { try self.integers(in: $0, pattern: #"x \(unitless\): (\d+); y \(unitless\): (\d+)"#) }
                guard values.count == 2, values.allSatisfy({ $0.count == 2 }), values[1][0] != values[0][0] else {
                    throw NSError(domain: "RetrievalFigureUI", code: 2)
                }
                answer = (values[1][1] - values[0][1]) / (values[1][0] - values[0][0])
                firstRow = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", rows[0])).firstMatch
            } else {
                XCTAssertTrue(prompt.contains("area of the rectangle"))
                let rows = labels.filter { $0.hasPrefix("Vertex:") && $0.contains("x (m):") }.sorted()
                XCTAssertEqual(rows.count, 4)
                let values = try rows.map { try self.integers(in: $0, pattern: #"x \(m\): (\d+); y \(m\): (\d+)"#) }
                guard values.count == 4, values.allSatisfy({ $0.count == 2 }) else { throw NSError(domain: "RetrievalFigureUI", code: 3) }
                let xs = values.map { $0[0] }, ys = values.map { $0[1] }
                answer = (xs.max()! - xs.min()!) * (ys.max()! - ys.min()!)
                firstRow = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", rows[0])).firstMatch
            }
            XCTAssertTrue(self.revealResponseControl(firstRow, in: app))
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "retrieval-actual-source-figure-and-equivalent-data-en"; capture.lifetime = .keepAlways; self.add(capture)
            self.enterNumericAnswer(String(answer), in: app)
        }
    }

    func testQuantitativeNumberAndUnitShowFeedbackAndAdvance() throws {
        try exerciseLabResponse(activity: "quantitative.proportion", promptFragment: "observed proportion", expectedFeedback: "Correct") { app, prompt in
            let values = try self.integers(in: prompt, pattern: #"(\d+) of (\d+) observations"#)
            XCTAssertEqual(values.count, 2)
            let answer = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), 100 * Double(values[0]) / Double(values[1]))
            self.enterNumericAnswer(answer, in: app)
            self.enterText("25", in: app.textFields["session-data-prediction-input"], app: app, minimumHeight: 44)
            let inspection = app.buttons["session-data-inspection"]
            XCTAssertTrue(self.revealResponseControl(inspection, in: app))
            XCTAssertGreaterThanOrEqual(inspection.frame.height, 44)
            inspection.tap()
            let otherOutcome = app.buttons["Does not meet"]
            XCTAssertTrue(otherOutcome.waitForExistence(timeout: 5))
            XCTAssertTrue(otherOutcome.isHittable)
            otherOutcome.tap()
            let selectedPoint = self.element(in: app, identifier: "session-data-inspected-point")
            XCTAssertTrue(selectedPoint.waitForExistence(timeout: 5))
            XCTAssertTrue(selectedPoint.label.contains("Does not meet"))
            XCTAssertTrue(selectedPoint.label.contains("\(values[1] - values[0]) observations"))
            let table = app.buttons["session-data-table"]
            XCTAssertTrue(self.revealResponseControl(table, in: app))
            table.tap()
            let originalCount = self.element(in: app, identifier: "session-data-row-0")
            XCTAssertTrue(originalCount.waitForExistence(timeout: 5))
            XCTAssertTrue(self.revealResponseControl(originalCount, in: app))
            XCTAssertTrue(originalCount.label.contains("Meets criterion"))
            XCTAssertTrue(originalCount.label.contains("Count (observations)"))
            XCTAssertTrue(originalCount.label.contains(String(values[0])))
            XCTAssertFalse(app.keyboards.firstMatch.exists, "Data inspection should leave the original counts available without the prediction keyboard.")
            XCTAssertEqual(app.textFields["session-numeric-answer"].value as? String, answer,
                "Inspecting the original counts must not change the learner's separate percentage response.")
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "quantitative-original-count-inspection-table-en"
            capture.lifetime = .keepAlways
            self.add(capture)
            self.enterText("%", in: app.textFields["Unit"], app: app, minimumHeight: 44)
        }
    }

    func testTransferRelationshipSurvivesColdLaunchBeforeOneScoredAnswer() throws {
        #if os(iOS)
        let app = XCUIApplication(), runID = UUID().uuidString
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: true, startSession: false)
            + ["-ui-test-activity", "nf.default.transfer.rate"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(element(in: app, identifier: "universal-session").waitForExistence(timeout: 15))
        resumeIfOffered(in: app)
        let prompt = element(in: app, identifier: "session-prompt").label
        let context = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "liquid flows steadily at")).firstMatch
        XCTAssertTrue(context.waitForExistence(timeout: 8))
        let originalContext = context.label
        let quantities = try integers(in: originalContext, pattern: #"liquid flows steadily at (\d+) (?:litres|millilitres) per minute for (\d+) seconds"#)
        XCTAssertEqual(quantities.count, 2)
        let total = String(quantities[0] * quantities[1] / 60)
        let stage = element(in: app, identifier: "transfer-relationship-stage")
        XCTAssertTrue(revealResponseControl(stage, in: app))
        XCTAssertEqual(stage.label, "Transfer stage 1 of 2 · Choose a relationship")
        XCTAssertFalse(app.textFields["transfer-target-total"].exists)
        XCTAssertFalse(element(in: app, identifier: "session-submit").isEnabled)
        let relationship = "Total = rate × duration, after matching the time units."
        chooseResponse(relationship, in: app)
        let clear = app.buttons["Clear relationship choice"]
        XCTAssertTrue(revealResponseControl(clear, in: app)); clear.tap()
        XCTAssertFalse(element(in: app, identifier: "session-submit").isEnabled)
        let undo = app.buttons["Undo relationship choice"]
        XCTAssertTrue(revealResponseControl(undo, in: app)); undo.tap()
        assertSelected(app.buttons[relationship])
        XCTAssertEqual(element(in: app, identifier: "session-submit").label, "Save relationship and continue")
        submitVisibleResponse(in: app)
        XCTAssertTrue(app.textFields["transfer-target-total"].waitForExistence(timeout: 8))
        XCTAssertEqual(stage.label, "Transfer stage 2 of 2 · Solve the target")
        XCTAssertFalse(element(in: app, identifier: "session-feedback-title").exists)
        XCTAssertFalse(element(in: app, identifier: "session-next").exists)
        XCTAssertFalse(element(in: app, identifier: "session-submit").isEnabled)
        saveAndClose(in: app)
        primaryNavigation(in: app, destinationID: "progress", expectedLabel: "Progress").tap()
        let section = element(in: app, identifier: "progress-section-picker")
        XCTAssertTrue(section.waitForExistence(timeout: 8)); section.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Your completed answers will appear here."].waitForExistence(timeout: 8))
        app.terminate()
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: false, startSession: false)
        app.launch(); continueSavedSession(in: app)
        XCTAssertEqual(element(in: app, identifier: "session-prompt").label, prompt)
        XCTAssertEqual(context.label, originalContext)
        XCTAssertEqual(stage.label, "Transfer stage 2 of 2 · Solve the target")
        XCTAssertTrue(app.staticTexts["Relationship saved before calculating"].exists)
        XCTAssertFalse(app.buttons[relationship].exists)
        let field = app.textFields["transfer-target-total"]
        enterText(total, in: field, app: app, minimumHeight: 44)
        submitVisibleResponse(in: app)
        let feedback = element(in: app, identifier: "session-feedback-title")
        XCTAssertTrue(revealResponseControl(feedback, in: app)); XCTAssertEqual(feedback.label, "Correct")
        XCTAssertEqual(field.value as? String, total); XCTAssertFalse(field.isEnabled)
        XCTAssertTrue(revealResponseControl(app.staticTexts["What carried over"], in: app))
        XCTAssertTrue(app.staticTexts["What changed in the target"].exists)
        let result = XCTAttachment(screenshot: app.screenshot())
        result.name = "transfer-cold-relationship-final-feedback-en"; result.lifetime = .keepAlways; add(result)
        let next = element(in: app, identifier: "session-next")
        XCTAssertTrue(revealResponseControl(next, in: app)); next.press(forDuration: 0.15)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "2 / 5"), object: element(in: app, identifier: "session-position"))
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 8), .completed)
        XCTAssertTrue(revealResponseControl(stage, in: app))
        XCTAssertEqual(stage.label, "Transfer stage 1 of 2 · Choose a relationship")
        saveAndClose(in: app)
        primaryNavigation(in: app, destinationID: "progress", expectedLabel: "Progress").tap()
        XCTAssertTrue(section.waitForExistence(timeout: 8)); section.buttons["History"].tap()
        let openHistory = app.buttons["Open answer history"]
        XCTAssertTrue(scrollUntilHittable(openHistory, in: app)); openHistory.press(forDuration: 0.15)
        XCTAssertTrue(app.navigationBars["Answer history"].waitForExistence(timeout: 8))
        let history = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", prompt))
        XCTAssertTrue(scrollUntilHittable(history.firstMatch, in: app)); XCTAssertEqual(history.count, 1)
        XCTAssertTrue(app.staticTexts["1 answer of 1 answer shown"].exists)
        #else
        throw XCTSkip("Linked transfer continuity uses the installed iOS app and isolated ordinary study.")
        #endif
    }

    func testScienceConfoundChoiceShowsFeedbackAndEndsAtFiniteCapacity() throws {
        try exerciseLabResponse(activity: "science.confound", promptFragment: "confound", expectedFeedback: "Correct", expectsExhaustionAfterFirstResponse: true) { app, _ in
            self.chooseResponse("Baseline ability", in: app)
        }
    }

    func testLogicConditionChoiceShowsFeedbackAndEndsAtFiniteCapacity() throws {
        try exerciseLabResponse(activity: "logic.conditions", promptFragment: "condition", expectedFeedback: "Correct", expectsExhaustionAfterFirstResponse: true) { app, _ in
            self.chooseResponse("Sufficient but not necessary", in: app)
        }
    }

    func testRetrievalRecallPrecedesReferenceAndNeutralSelfCheck() throws {
        try exerciseLabResponse(activity: "retrieval.free-recall", promptFragment: "recall", expectedFeedback: "Self-check saved") { app, _ in
            XCTAssertFalse(app.staticTexts["Reference answer"].exists)
            let editor = app.textViews.firstMatch
            self.enterText("I remember a relationship between the quantities.", in: editor, app: app, minimumHeight: 44)
            self.submitVisibleResponse(in: app)
            let reference = app.staticTexts["Reference answer"]
            XCTAssertTrue(reference.waitForExistence(timeout: 8))
            XCTAssertTrue(self.revealResponseControl(reference, in: app))
            XCTAssertFalse(editor.isEnabled, "The original recall must lock before the reference is exposed.")
            self.chooseResponse("Not yet", in: app)
            XCTAssertEqual(self.element(in: app, identifier: "session-submit").label, "Save self-check")
        }
    }

    func testTransferMultipleSelectionsShowFeedbackAndEndAtFiniteCapacity() throws {
        try exerciseLabResponse(activity: "transfer.conditions", promptFragment: "preserve valid reasoning", expectedFeedback: "Correct", expectsExhaustionAfterFirstResponse: true) { app, _ in
            self.chooseResponse("Verify that the original constraints still hold in the new field.", in: app)
            self.chooseResponse("Preserve the underlying quantities while changing their labels.", in: app)
        }
    }

    func testOrderedProofMoveRetainsSubmittedSequenceAndEndsAtFiniteCapacity() throws {
        try exerciseLabResponse(activity: "logic.proof-builder", promptFragment: "proof", expectedFeedback: nil, expectsExhaustionAfterFirstResponse: true) { app, _ in
            let move = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Move step 2 up:")).firstMatch
            XCTAssertTrue(move.waitForExistence(timeout: 8))
            XCTAssertTrue(self.revealResponseControl(move, in: app))
            XCTAssertGreaterThanOrEqual(move.frame.height, 44)
            let originalMoveLabel = move.label
            move.tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", originalMoveLabel), object: move)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, "Moving a proof step must change the visible order before submission.")
            let undo = app.buttons["ordered-response-undo"]
            XCTAssertTrue(self.revealResponseControl(undo, in: app))
            XCTAssertTrue(undo.isEnabled)
            undo.tap()
            XCTAssertTrue(self.revealResponseControl(move, in: app))
            XCTAssertEqual(move.label, originalMoveLabel, "Undo must restore the original visible step order.")
            move.tap()
            let reapplied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", originalMoveLabel), object: move)
            XCTAssertEqual(XCTWaiter.wait(for: [reapplied], timeout: 5), .completed)
        }
    }

    func testReviewedRestoreWaitsForColdLaunchAndCompletionAcknowledgementPersists() throws {
        #if os(iOS)
        let app = XCUIApplication(), runID = UUID().uuidString
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: true, startSession: false)
            + ["-ui-test-restore-fixture"]
        app.launch(); defer { app.terminate() }
        primaryNavigation(in: app, destinationID: "settings", expectedLabel: "Settings").tap()
        let data = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Data and sync")).firstMatch
        XCTAssertTrue(scrollUntilHittable(data, in: app)); data.press(forDuration: 0.15)
        let review = app.buttons["restore-fixture-review"]
        XCTAssertTrue(scrollUntilHittable(review, in: app)); review.press(forDuration: 0.15)
        XCTAssertTrue(app.staticTexts["Restore full backup"].waitForExistence(timeout: 10))
        let save = app.buttons.matching(NSPredicate(format: "label == %@", "Save restore request")).firstMatch
        XCTAssertFalse(save.isEnabled, "Preview must require an explicit conflict policy.")
        let policy = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Choose a policy")).firstMatch
        XCTAssertTrue(scrollUntilHittable(policy, in: app)); policy.press(forDuration: 0.15)
        app.buttons["Keep existing records"].press(forDuration: 0.15)
        XCTAssertTrue(scrollUntilHittable(save, in: app)); XCTAssertTrue(save.isEnabled)
        save.press(forDuration: 0.15)
        let restart = element(in: app, identifier: "restore-restart-required")
        XCTAssertTrue(restart.waitForExistence(timeout: 10))
        XCTAssertFalse(element(in: app, identifier: "restore-completed").exists)
        XCTAssertFalse(element(in: app, identifier: "universal-session").exists)
        let staged = XCTAttachment(screenshot: app.screenshot()); staged.name = "restore-reviewed-request-awaits-restart"
        staged.lifetime = .keepAlways; add(staged)
        app.terminate()
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: false, startSession: false)
            + ["-ui-test-restore-fixture"]
        app.launch()
        let completed = element(in: app, identifier: "restore-completed")
        XCTAssertTrue(completed.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Records and saved details restored: 1; skipped: 0."].exists)
        XCTAssertFalse(element(in: app, identifier: "universal-session").exists)
        app.terminate(); app.launch()
        XCTAssertTrue(completed.waitForExistence(timeout: 15), "Unacknowledged result counts must survive another genuine cold launch.")
        let result = XCTAttachment(screenshot: app.screenshot()); result.name = "restore-cold-completion-counts-retained"
        result.lifetime = .keepAlways; add(result)
        app.buttons["Continue"].press(forDuration: 0.15)
        XCTAssertTrue(element(in: app, identifier: "destination-today").waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(element(in: app, identifier: "destination-today").waitForExistence(timeout: 15))
        XCTAssertFalse(completed.exists, "The acknowledged restore must not replay or reopen completion on a later launch.")
        #else
        throw XCTSkip("Installed restore handoff uses a private iOS fixture with two real SQLite stores.")
        #endif
    }

    func testClaimEvidenceSelectionShowsFeedbackAndAdvances() throws {
        #if os(iOS)
        let app = XCUIApplication(), runID = UUID().uuidString
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: true, startSession: false)
            + ["-ui-test-activity", "nf.default.science.claim-evidence"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(element(in: app, identifier: "universal-session").waitForExistence(timeout: 15))
        resumeIfOffered(in: app)
        let position = element(in: app, identifier: "session-position")
        XCTAssertTrue(position.waitForExistence(timeout: 8))
        XCTAssertEqual(position.value as? String, "1 / 5")
        let originalPrompt = element(in: app, identifier: "session-prompt").label
        XCTAssertTrue(originalPrompt.hasPrefix("Study "))
        XCTAssertTrue(originalPrompt.hasSuffix("connect the claims to the evidence, then choose a follow-up experiment for this same study."))
        let stage = element(in: app, identifier: "science-study-stage")
        XCTAssertTrue(revealResponseControl(stage, in: app))
        XCTAssertEqual(stage.label, "Study stage 1 of 2 · Connect the evidence")
        XCTAssertFalse(element(in: app, identifier: "session-next").exists)
        XCTAssertFalse(element(in: app, identifier: "session-submit").isEnabled)

        let meanEvidence = app.buttons.matching(NSPredicate(format:
            "label BEGINSWITH %@ AND label CONTAINS %@", "The workshop group had the", ": The workshop mean was ")).firstMatch
        XCTAssertTrue(revealResponseControl(meanEvidence, in: app))
        XCTAssertGreaterThanOrEqual(meanEvidence.frame.height, 44)
        let firstPair = meanEvidence.label.components(separatedBy: ": ")
        XCTAssertEqual(firstPair.count, 2)
        let observedClaim = firstPair[0], observedMeans = firstPair[1]
        let means = try integers(in: observedMeans, pattern: #"The workshop mean was (-?\d+) points; the comparison mean was (-?\d+) points\."#)
        XCTAssertNotEqual(means[0], means[1])
        XCTAssertEqual(observedClaim, means[0] > means[1]
            ? "The workshop group had the higher observed final score."
            : "The workshop group had the lower observed final score.",
            "The visible claim must describe these exact visible observations.")
        meanEvidence.tap(); assertSelected(meanEvidence)
        let claimPicker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Claim")).firstMatch
        XCTAssertTrue(revealResponseControl(claimPicker, in: app))
        claimPicker.tap()
        let limitClaim = "This comparison cannot separate a workshop effect from differences in prior skill."
        let secondClaim = app.buttons[limitClaim]
        XCTAssertTrue(secondClaim.waitForExistence(timeout: 5)); secondClaim.tap()
        let assignment = "Participants chose their group instead of being randomly assigned."
        let assignmentEvidence = app.buttons.matching(NSPredicate(format: "label == %@", "\(limitClaim): \(assignment)")).firstMatch
        XCTAssertTrue(revealResponseControl(assignmentEvidence, in: app))
        assignmentEvidence.tap(); assertSelected(assignmentEvidence)
        let priorEvidence = app.buttons.matching(NSPredicate(format:
            "label BEGINSWITH %@ AND label CONTAINS %@", "\(limitClaim): ", "Prior skill predicts the outcome, and its mean was ")).firstMatch
        XCTAssertTrue(revealResponseControl(priorEvidence, in: app))
        let priorObservation = String(priorEvidence.label.dropFirst("\(limitClaim): ".count))
        priorEvidence.tap(); assertSelected(priorEvidence)
        XCTAssertEqual(element(in: app, identifier: "session-submit").label, "Save evidence and continue")
        submitVisibleResponse(in: app)
        let secondStage = XCTNSPredicateExpectation(predicate: NSPredicate(format:
            "label == %@", "Study stage 2 of 2 · Choose the experiment"), object: stage)
        XCTAssertEqual(XCTWaiter.wait(for: [secondStage], timeout: 8), .completed)
        XCTAssertEqual(position.value as? String, "1 / 5")
        XCTAssertEqual(element(in: app, identifier: "session-prompt").label, originalPrompt)
        XCTAssertFalse(element(in: app, identifier: "session-feedback-title").exists)
        XCTAssertFalse(element(in: app, identifier: "session-next").exists)
        XCTAssertFalse(element(in: app, identifier: "session-submit").isEnabled,
            "The saved evidence alone must not submit the still-unanswered experiment criterion.")
        saveAndClose(in: app)
        primaryNavigation(in: app, destinationID: "progress", expectedLabel: "Progress").tap()
        let section = element(in: app, identifier: "progress-section-picker")
        XCTAssertTrue(section.waitForExistence(timeout: 8)); section.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Your completed answers will appear here."].waitForExistence(timeout: 8),
            "The intermediate evidence save must not create a scored attempt.")
        app.terminate()
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: false, startSession: false)
        app.launch()
        continueSavedSession(in: app)
        XCTAssertEqual(element(in: app, identifier: "session-prompt").label, originalPrompt)
        XCTAssertEqual(position.value as? String, "1 / 5")
        XCTAssertTrue(stage.waitForExistence(timeout: 8))
        XCTAssertEqual(stage.label, "Study stage 2 of 2 · Choose the experiment")
        XCTAssertFalse(element(in: app, identifier: "session-submit").isEnabled)
        let savedEvidence = app.buttons["Evidence saved before choosing the experiment"]
        XCTAssertTrue(revealResponseControl(savedEvidence, in: app)); savedEvidence.tap()
        for text in [observedClaim, observedMeans, limitClaim, assignment, priorObservation] {
            XCTAssertTrue(revealResponseControl(app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch, in: app),
                "The cold study must retain each exact first-stage claim and observation.")
        }
        XCTAssertFalse(claimPicker.exists, "The already saved evidence mapping must remain locked after cold continuation.")
        let retained = XCTAttachment(screenshot: app.screenshot())
        retained.name = "linked-science-cold-saved-evidence-en"; retained.lifetime = .keepAlways; add(retained)
        XCTAssertTrue(revealResponseControl(savedEvidence, in: app)); savedEvidence.tap()
        let experiment = "Randomize participants within prior-skill blocks, then give both groups the same calibrated test under blinded scoring."
        chooseResponse(experiment, in: app)
        XCTAssertEqual(element(in: app, identifier: "session-submit").label, "Submit response")
        submitVisibleResponse(in: app)
        let feedback = element(in: app, identifier: "session-feedback-title")
        XCTAssertTrue(revealResponseControl(feedback, in: app)); XCTAssertEqual(feedback.label, "Correct")
        XCTAssertEqual(position.value as? String, "1 / 5")
        XCTAssertEqual(element(in: app, identifier: "session-prompt").label, originalPrompt)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", experiment)).firstMatch.isEnabled)
        XCTAssertTrue(revealResponseControl(app.staticTexts["Your follow-up experiment"], in: app))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Randomization within prior-skill blocks separates assignment from prior skill; the common calibrated test keeps measurement comparable.")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "claim.observed")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "experiment.random-common")).firstMatch.exists)
        let result = XCTAttachment(screenshot: app.screenshot())
        result.name = "linked-science-same-study-experiment-feedback-en"; result.lifetime = .keepAlways; add(result)
        let next = element(in: app, identifier: "session-next")
        XCTAssertTrue(revealResponseControl(next, in: app)); XCTAssertGreaterThanOrEqual(next.frame.height, 44)
        next.press(forDuration: 0.15)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "2 / 5"), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 8), .completed)
        XCTAssertTrue(revealResponseControl(stage, in: app))
        XCTAssertEqual(stage.label, "Study stage 1 of 2 · Connect the evidence")
        XCTAssertFalse(element(in: app, identifier: "session-submit").isEnabled)
        saveAndClose(in: app)
        primaryNavigation(in: app, destinationID: "progress", expectedLabel: "Progress").tap()
        XCTAssertTrue(section.waitForExistence(timeout: 8)); section.buttons["History"].tap()
        let openHistory = app.buttons["Open answer history"]
        XCTAssertTrue(scrollUntilHittable(openHistory, in: app)); openHistory.press(forDuration: 0.15)
        XCTAssertTrue(app.navigationBars["Answer history"].waitForExistence(timeout: 8))
        let history = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", originalPrompt))
        XCTAssertTrue(scrollUntilHittable(history.firstMatch, in: app))
        XCTAssertEqual(history.count, 1, "The two-stage study must create exactly one original answer.")
        XCTAssertTrue(app.staticTexts["1 answer of 1 answer shown"].exists)
        history.firstMatch.press(forDuration: 0.15)
        XCTAssertTrue(app.staticTexts["Your saved answer"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", originalPrompt)).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "claim.observed")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "experiment.random-common")).firstMatch.exists)
        #else
        throw XCTSkip("Linked science continuity uses the installed iOS app and an isolated ordinary study.")
        #endif
    }

    func testLogicStateInputsAndInvariantShowFeedbackAndAdvance() throws {
        try exerciseLabResponse(activity: "logic.state-trace", promptFragment: "Trace the state", expectedFeedback: nil) { app, _ in
            let invariant = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ready must equal (count <=")).firstMatch
            XCTAssertTrue(self.revealResponseControl(invariant, in: app))
            invariant.tap()
            self.assertSelected(invariant)
            self.enterText("0", in: app.textFields["Response for count"], app: app, minimumHeight: 44)
            app.textFields["Response for count"].typeText("\n")
            self.enterText("true", in: app.textFields["Response for ready"], app: app, minimumHeight: 44)
            let inspect = app.buttons["code-trace-start"]
            XCTAssertTrue(self.revealResponseControl(inspect, in: app))
            XCTAssertTrue(inspect.isEnabled)
            inspect.tap()
            let state = self.element(in: app, identifier: "code-trace-state")
            XCTAssertTrue(state.waitForExistence(timeout: 5))
            XCTAssertTrue(self.revealResponseControl(state, in: app))
            XCTAssertTrue(app.staticTexts["Execution inspection is recorded as support. Your first prediction stays saved."].exists)
            let reset = app.buttons["code-trace-reset"]
            XCTAssertTrue(self.revealResponseControl(reset, in: app))
            XCTAssertTrue(reset.isEnabled)
            reset.tap()
            XCTAssertTrue(app.staticTexts["Original starting state"].exists)
            XCTAssertEqual(app.textFields["Response for count"].value as? String, "0")
            XCTAssertEqual(app.textFields["Response for ready"].value as? String, "true")
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "state-trace-saved-prediction-original-input-reset"
            capture.lifetime = .keepAlways
            self.add(capture)
        }
    }

    func testShortTextClarificationRetainsDraftAndAllowsExplicitSkip() throws {
        #if os(iOS)
        let app = XCUIApplication()
        app.launchArguments = persistentLaunchArguments(runID: UUID().uuidString, language: "en", reset: true, startSession: false)
            + ["-ui-test-activity", "nf.default.retrieval.precision-recall"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(element(in: app, identifier: "universal-session").waitForExistence(timeout: 15))
        resumeIfOffered(in: app)
        let position = element(in: app, identifier: "session-position")
        XCTAssertTrue(position.waitForExistence(timeout: 8))
        XCTAssertEqual(position.value as? String, "1 / 5")
        let prompt = element(in: app, identifier: "session-prompt").label
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("Answer from memory"))
        let response = "I am unsure about the relationship."
        let editor = app.textViews.firstMatch
        enterText(response, in: editor, app: app, minimumHeight: 44)
        submitVisibleResponse(in: app)
        let clarification = element(in: app, identifier: "session-answer-clarification")
        XCTAssertTrue(clarification.waitForExistence(timeout: 8), "The pinned reviewed-prose fixture must ask for clarification, not grade unsupported wording.")
        XCTAssertTrue(app.staticTexts["This wording is outside the reviewed answer coverage. Compare it with the reference or report a grading issue."].exists)
        // SwiftUI exposes the explicitly modal session container as AX Alert.
        // Clarification must not present an additional system/save alert.
        XCTAssertFalse(app.alerts.matching(NSPredicate(format: "identifier != %@", "universal-session")).firstMatch.exists)
        XCTAssertFalse(app.alerts["Save interrupted"].exists)
        XCTAssertFalse(element(in: app, identifier: "session-next").exists)
        XCTAssertEqual(position.value as? String, "1 / 5")
        XCTAssertEqual(editor.value as? String, response)
        XCTAssertEqual(element(in: app, identifier: "session-prompt").label, prompt)
        XCTAssertTrue(revealResponseControl(clarification, in: app), "The retained draft's format guidance must be visible above the action footer.")
        XCTAssertTrue(clarification.isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "short-text-clarification-retains-draft-en"
        capture.lifetime = .keepAlways
        add(capture)
        let skip = app.buttons["Skip — no score"]
        XCTAssertTrue(revealResponseControl(skip, in: app))
        XCTAssertTrue(skip.isEnabled)
        skip.tap()
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "2 / 5"), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 8), .completed)
        #else
        throw XCTSkip("Short-text clarification runs in the installed iOS app with the unit-verified fixture authority.")
        #endif
    }

    func testScalingLawPrimaryActionKeepsTheExistingNumericPractice() throws {
        #if os(iOS)
        let app = XCUIApplication()
        app.launchArguments = persistentLaunchArguments(runID: UUID().uuidString, language: "en", reset: true, startSession: false)
        app.launch(); defer { app.terminate() }
        openScalingLawFromPractice(in: app)
        let graph = app.buttons["train-start-graph-construction"]
        XCTAssertTrue(graph.waitForExistence(timeout: 5))
        XCTAssertTrue(graph.isEnabled)
        let primary = app.buttons["Start practice"]
        XCTAssertTrue(primary.isHittable); primary.press(forDuration: 0.15)
        XCTAssertTrue(element(in: app, identifier: "universal-session").waitForExistence(timeout: 10))
        resumeIfOffered(in: app)
        XCTAssertTrue(element(in: app, identifier: "session-numeric-answer").waitForExistence(timeout: 8),
            "The original Scaling Law action must still expose its numeric response.")
        XCTAssertFalse(element(in: app, identifier: "session-graph-construction").exists)
        XCTAssertFalse(element(in: app, identifier: "graph-place-origin").exists)
        XCTAssertEqual(element(in: app, identifier: "session-position").value as? String, "1 / 5")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "scaling-primary-retains-numeric-practice-en"; capture.lifetime = .keepAlways; add(capture)
        #else
        throw XCTSkip("The public catalog graph launch is exercised in the installed iOS app.")
        #endif
    }

    func testGraphPublicLaunchPointerControlsUndoAndColdCoordinatesReachSavedFeedback() throws {
        #if os(iOS)
        let app = XCUIApplication(), runID = UUID().uuidString
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: true, startSession: false)
        app.launch(); defer { app.terminate() }
        openScalingLawFromPractice(in: app)
        let start = app.buttons["train-start-graph-construction"]
        XCTAssertTrue(start.waitForExistence(timeout: 5)); XCTAssertTrue(start.isHittable)
        XCTAssertGreaterThanOrEqual(start.frame.height, 44)
        XCTAssertTrue(app.buttons["Start practice"].isEnabled)
        start.press(forDuration: 0.15)
        XCTAssertTrue(element(in: app, identifier: "universal-session").waitForExistence(timeout: 10))
        resumeIfOffered(in: app)
        let position = element(in: app, identifier: "session-position")
        XCTAssertEqual(position.value as? String, "1 / 5")
        let promptView = element(in: app, identifier: "session-prompt")
        XCTAssertTrue(promptView.waitForExistence(timeout: 8))
        let prompt = promptView.label
        let givens = try integers(in: prompt, pattern: #"travels (\d+) meters in 1 second.*after (\d+) seconds"#)
        XCTAssertEqual(givens.count, 2)
        let x = givens[1], y = givens[0] * givens[1]
        let pointText = "Your point: (\(x) s, \(y) m)"
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Expected point:")).firstMatch.exists)
        let origin = app.buttons["graph-place-origin"], undo = app.buttons["graph-undo-point"]
        XCTAssertTrue(revealResponseControl(origin, in: app)); XCTAssertGreaterThanOrEqual(origin.frame.height, 44)
        XCTAssertFalse(element(in: app, identifier: "session-submit").isEnabled)
        origin.press(forDuration: 0.15)
        assertGraphPointText("Your point: (0 s, 0 m)", in: app)
        XCTAssertTrue(revealResponseControl(undo, in: app)); XCTAssertTrue(undo.isEnabled)
        XCTAssertGreaterThanOrEqual(undo.frame.height, 44); undo.press(forDuration: 0.15)
        XCTAssertTrue(app.staticTexts["No point has been placed on the grid."].waitForExistence(timeout: 5))
        XCTAssertFalse(element(in: app, identifier: "session-submit").isEnabled)
        XCTAssertTrue(revealResponseControl(origin, in: app)); origin.press(forDuration: 0.15)

        let sourceTable = element(in: app, identifier: "graph-source-table")
        XCTAssertTrue(revealResponseControl(sourceTable, in: app))
        let sourcePair = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@",
            "Time (s): 1; Distance (m): \(givens[0])")).firstMatch
        XCTAssertTrue(sourcePair.waitForExistence(timeout: 5), "The real source table exposes both exact measured coordinates and units.")
        let plot = element(in: app, identifier: "graph-point-plot")
        XCTAssertTrue(revealResponseControl(plot, in: app))
        let enablePlacement = app.buttons["graph-enable-point-placement"]
        XCTAssertTrue(revealResponseControl(enablePlacement, in: app))
        XCTAssertGreaterThanOrEqual(enablePlacement.frame.height, 44)
        XCTAssertEqual(enablePlacement.label, "Move point on grid")
        enablePlacement.tap()
        XCTAssertEqual(enablePlacement.label, "Cancel point placement")
        let frame = plot.frame
        XCTAssertGreaterThan(frame.width, 100); XCTAssertGreaterThan(frame.height, 100)
        // These are the renderer's documented plot insets and finite grid.
        // Only the displayed prompt supplies the mathematical answer.
        let width = frame.width - 62, height = frame.height - 62
        let originOnPlot = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.minX + 42, dy: frame.minY + 24 + height))
        let targetOnPlot = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.minX + 42 + CGFloat(x) / 6 * width,
                dy: frame.minY + 24 + CGFloat(50 - y) / 50 * height))
        originOnPlot.press(forDuration: 0.15, thenDragTo: targetOnPlot,
            withVelocity: .slow, thenHoldForDuration: 0.1)
        assertGraphPointText(pointText, in: app)
        XCTAssertEqual(enablePlacement.label, "Move point on grid", "One saved point returns the page to scrolling.")

        let time = element(in: app, identifier: "graph-adjust-x")
        XCTAssertTrue(revealResponseControl(time, in: app))
        XCTAssertEqual(time.label, "Time (s)"); XCTAssertEqual(time.value as? String, String(x))
        let increment = app.buttons["graph-adjust-x-increment"]
        let decrement = app.buttons["graph-adjust-x-decrement"]
        XCTAssertTrue(increment.exists, "The coordinate editor must expose a real labeled non-pointer adjustment control.")
        XCTAssertEqual(increment.label, "Increase Time (s)")
        XCTAssertTrue(revealResponseControl(increment, in: app))
        XCTAssertGreaterThanOrEqual(increment.frame.height, 44)
        XCTAssertGreaterThanOrEqual(increment.frame.width, 44)
        XCTAssertGreaterThanOrEqual(decrement.frame.height, 44)
        XCTAssertTrue(increment.isHittable); increment.press(forDuration: 0.15)
        assertGraphPointText("Your point: (\(x + 1) s, \(y) m)", in: app)
        XCTAssertTrue(revealResponseControl(undo, in: app)); undo.press(forDuration: 0.15)
        assertGraphPointText(pointText, in: app)
        let distance = element(in: app, identifier: "graph-adjust-y")
        XCTAssertTrue(revealResponseControl(distance, in: app))
        XCTAssertEqual(distance.label, "Distance (m)"); XCTAssertEqual(distance.value as? String, String(y))
        let draft = XCTAttachment(screenshot: app.screenshot())
        draft.name = "graph-native-pointer-stepper-undo-exact-draft-en"; draft.lifetime = .keepAlways; add(draft)
        closeGraphSessionAndReturnToday(in: app)
        app.terminate()
        app.launchArguments = persistentLaunchArguments(runID: runID, language: "en", reset: false, startSession: false)
        app.launch(); continueSavedSession(in: app)
        XCTAssertEqual(promptView.label, prompt)
        XCTAssertEqual(position.value as? String, "1 / 5")
        assertGraphPointText(pointText, in: app)
        XCTAssertTrue(revealResponseControl(time, in: app)); XCTAssertEqual(time.value as? String, String(x))
        XCTAssertTrue(revealResponseControl(distance, in: app)); XCTAssertEqual(distance.value as? String, String(y))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Expected point:")).firstMatch.exists)
        submitVisibleResponse(in: app)
        let feedback = element(in: app, identifier: "session-feedback-title")
        XCTAssertTrue(revealResponseControl(feedback, in: app)); XCTAssertEqual(feedback.label, "Correct")
        XCTAssertEqual(position.value as? String, "1 / 5"); XCTAssertEqual(promptView.label, prompt)
        XCTAssertTrue(revealResponseControl(time, in: app)); XCTAssertFalse(time.isEnabled)
        XCTAssertEqual(time.value as? String, String(x))
        XCTAssertTrue(revealResponseControl(distance, in: app)); XCTAssertFalse(distance.isEnabled)
        XCTAssertEqual(distance.value as? String, String(y))
        let expected = app.staticTexts["Expected point: (\(x) s, \(y) m)"]
        XCTAssertTrue(revealResponseControl(expected, in: app)); XCTAssertTrue(expected.exists)
        let saved = XCTAttachment(screenshot: app.screenshot())
        saved.name = "graph-cold-exact-coordinate-feedback-en"; saved.lifetime = .keepAlways; add(saved)
        let next = element(in: app, identifier: "session-next")
        XCTAssertTrue(revealResponseControl(next, in: app)); next.press(forDuration: 0.15)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "2 / 5"), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 8), .completed)
        XCTAssertTrue(revealResponseControl(origin, in: app)); XCTAssertTrue(origin.isEnabled)
        XCTAssertTrue(app.staticTexts["No point has been placed on the grid."].exists)
        XCTAssertFalse(element(in: app, identifier: "session-submit").isEnabled)
        XCTAssertNotEqual(promptView.label, prompt, "Next must select a genuinely different retained graph task.")
        XCTAssertFalse(app.alerts["Save interrupted"].exists)
        closeGraphSessionAndReturnToday(in: app)
        #else
        throw XCTSkip("Graph pointer and native control continuity requires the installed iOS app.")
        #endif
    }

    private func openScalingLawFromPractice(in app: XCUIApplication) {
        let practice = primaryNavigation(in: app, destinationID: "train", expectedLabel: "Practice")
        XCTAssertTrue(practice.waitForExistence(timeout: 15)); practice.press(forDuration: 0.15)
        XCTAssertTrue(element(in: app, identifier: "destination-train").waitForExistence(timeout: 8))
        let quantitative = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Quantitative Intuition")).firstMatch
        XCTAssertTrue(revealResponseControl(quantitative, in: app)); quantitative.tap()
        XCTAssertTrue(app.navigationBars["Quantitative"].waitForExistence(timeout: 8))
        let scaling = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Scaling Law")).firstMatch
        XCTAssertTrue(revealResponseControl(scaling, in: app)); scaling.tap()
        XCTAssertTrue(app.navigationBars["Scaling Law"].waitForExistence(timeout: 8))
        let five = app.buttons["5 questions"]
        XCTAssertTrue(revealResponseControl(five, in: app)); five.tap()
        assertSelected(five)
        XCTAssertTrue(app.buttons["Start practice"].isHittable)
    }

    private func assertGraphPointText(_ expected: String, in app: XCUIApplication) {
        let point = app.staticTexts.matching(NSPredicate(format: "label == %@", expected)).firstMatch
        XCTAssertTrue(point.waitForExistence(timeout: 5), "The visible coordinate pair must match the actual input action.")
        XCTAssertTrue(revealResponseControl(point, in: app))
        XCTAssertEqual(point.label, expected)
    }

    private func closeGraphSessionAndReturnToday(in app: XCUIApplication) {
        let pause = app.buttons["Pause session"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5)); pause.press(forDuration: 0.15)
        let save = element(in: app, identifier: "session-save-close")
        XCTAssertTrue(save.waitForExistence(timeout: 5)); XCTAssertTrue(save.isHittable); save.press(forDuration: 0.15)
        let session = element(in: app, identifier: "universal-session")
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: session)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 8), .completed)
        let today = primaryNavigation(in: app, destinationID: "today", expectedLabel: "Today")
        XCTAssertTrue(today.waitForExistence(timeout: 8)); today.press(forDuration: 0.15)
        XCTAssertTrue(element(in: app, identifier: "destination-today").waitForExistence(timeout: 8))
    }

    private func exerciseLabResponse(
        activity: String,
        promptFragment: String,
        expectedFeedback: String?,
        expectsExhaustionAfterFirstResponse: Bool = false,
        coordinateReasoningTitle: String? = nil,
        afterFeedback: ((XCUIApplication, String) throws -> Void)? = nil,
        answer: (XCUIApplication, String) throws -> Void
    ) throws {
        #if os(iOS)
        let app = XCUIApplication()
        app.launchArguments = persistentLaunchArguments(runID: UUID().uuidString, language: "en", reset: true, startSession: false)
            + (coordinateReasoningTitle == nil ? ["-ui-test-activity", "nf.default.\(activity)"] : [])
        app.launch()
        defer { app.terminate() }
        if let title = coordinateReasoningTitle {
            let practice = primaryNavigation(in: app, destinationID: "train", expectedLabel: "Practice")
            XCTAssertTrue(practice.waitForExistence(timeout: 15)); practice.press(forDuration: 0.15)
            XCTAssertTrue(element(in: app, identifier: "destination-train").waitForExistence(timeout: 8))
            let spatial = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Spatial")).firstMatch
            XCTAssertTrue(revealResponseControl(spatial, in: app)); spatial.press(forDuration: 0.15)
            XCTAssertTrue(app.navigationBars["Spatial"].waitForExistence(timeout: 8))
            let activity = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
            XCTAssertTrue(revealResponseControl(activity, in: app)); activity.press(forDuration: 0.15)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 8))
            let five = app.buttons["5 questions"]
            XCTAssertTrue(revealResponseControl(five, in: app)); five.press(forDuration: 0.15); assertSelected(five)
            let advanced = app.buttons["train-start-coordinate-reasoning"]
            XCTAssertTrue(advanced.waitForExistence(timeout: 5)); XCTAssertTrue(advanced.isHittable)
            XCTAssertGreaterThanOrEqual(advanced.frame.height, 44)
            XCTAssertTrue(app.buttons["Start practice"].isEnabled)
            advanced.press(forDuration: 0.15)
        }
        XCTAssertTrue(element(in: app, identifier: "universal-session").waitForExistence(timeout: 15))
        resumeIfOffered(in: app)
        let position = element(in: app, identifier: "session-position")
        XCTAssertTrue(position.waitForExistence(timeout: 8))
        XCTAssertEqual(position.value as? String, "1 / 5")
        let promptElement = element(in: app, identifier: "session-prompt")
        XCTAssertTrue(promptElement.waitForExistence(timeout: 8))
        let prompt = promptElement.label
        XCTAssertFalse(prompt.isEmpty)
        if !promptFragment.isEmpty {
            XCTAssertTrue(prompt.localizedCaseInsensitiveContains(promptFragment), "The fixture must launch its declared catalog family.")
        }
        try answer(app, prompt)
        // The additional prediction editor can change the global index order
        // as feedback appears. Bind each saved surface to its own stable name.
        let submittedFields = app.textFields.allElementsBoundByIndex.map { field in
            let query = !field.identifier.isEmpty
                ? NSPredicate(format: "identifier == %@", field.identifier)
                : (!field.label.isEmpty ? NSPredicate(format: "label == %@", field.label)
                   : NSPredicate(format: "placeholderValue == %@", field.placeholderValue ?? ""))
            return (app.textFields.matching(query).firstMatch, field.value as? String)
        }
        let submittedEditors = app.textViews.allElementsBoundByIndex.map { editor in
            let query = !editor.identifier.isEmpty
                ? NSPredicate(format: "identifier == %@", editor.identifier)
                : (!editor.label.isEmpty ? NSPredicate(format: "label == %@", editor.label)
                   : NSPredicate(format: "placeholderValue == %@", editor.placeholderValue ?? ""))
            return (app.textViews.matching(query).firstMatch, editor.value as? String)
        }
        submitVisibleResponse(in: app)
        let next = element(in: app, identifier: "session-next")
        XCTAssertTrue(next.waitForExistence(timeout: 8), "A committed ordinary response must expose the forward action.")
        XCTAssertEqual(position.value as? String, "1 / 5", "Feedback must stay on the submitted question.")
        XCTAssertEqual(element(in: app, identifier: "session-prompt").label, prompt)
        XCTAssertTrue(app.staticTexts["Your answer"].exists)
        for (field, value) in submittedFields + submittedEditors {
            XCTAssertTrue(field.exists, "The submitted response surface remains available with feedback.")
            XCTAssertEqual(field.value as? String, value)
            XCTAssertFalse(field.isEnabled, "Feedback must retain and lock the submitted response controls.")
        }
        let feedbackTitle = element(in: app, identifier: "session-feedback-title")
        XCTAssertTrue(feedbackTitle.waitForExistence(timeout: 8))
        XCTAssertTrue(revealResponseControl(feedbackTitle, in: app), "The actual feedback heading must be visible above the forward-action footer.")
        XCTAssertTrue(feedbackTitle.isHittable)
        if let expectedFeedback { XCTAssertEqual(feedbackTitle.label, expectedFeedback) }
        let originalFeedbackTitle = feedbackTitle.label
        try afterFeedback?(app, prompt)
        XCTAssertEqual(feedbackTitle.label, originalFeedbackTitle)
        XCTAssertTrue(revealResponseControl(next, in: app))
        XCTAssertGreaterThanOrEqual(next.frame.height, 44)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "lab-response-feedback-\(activity)-en"
        capture.lifetime = .keepAlways
        add(capture)
        next.press(forDuration: 0.15)
        if expectsExhaustionAfterFirstResponse {
            let shortage = element(in: app, identifier: "session-next-unavailable")
            XCTAssertTrue(shortage.waitForExistence(timeout: 8))
            XCTAssertEqual(shortage.label, "No fresh question is available for this activity. Your completed answers are saved. Choose another activity or return later.")
            XCTAssertEqual(position.value as? String, "1 / 5", "A finite pool must retain the actual saved question instead of publishing a nonexistent second item.")
            XCTAssertEqual(element(in: app, identifier: "session-prompt").label, prompt)
            XCTAssertEqual(feedbackTitle.label, originalFeedbackTitle)
            XCTAssertFalse(next.isEnabled)
            XCTAssertFalse(app.alerts.matching(NSPredicate(format: "identifier != %@", "universal-session")).firstMatch.exists)
            XCTAssertFalse(app.alerts["Save interrupted"].exists)
            XCTAssertTrue(revealResponseControl(shortage, in: app))
            let end = element(in: app, identifier: "session-end-unavailable")
            XCTAssertTrue(revealResponseControl(end, in: app))
            XCTAssertGreaterThanOrEqual(end.frame.height, 44)
            XCTAssertTrue(end.isEnabled)
            let capacityCapture = XCTAttachment(screenshot: app.screenshot())
            capacityCapture.name = "finite-capacity-retains-feedback-\(activity)-en"
            capacityCapture.lifetime = .keepAlways
            add(capacityCapture)
            end.tap()
            XCTAssertTrue(app.staticTexts["Ended after 1 of 5 questions"].waitForExistence(timeout: 8))
            return
        }
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "2 / 5"), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 8), .completed)
        XCTAssertTrue(element(in: app, identifier: "session-submit").waitForExistence(timeout: 8))
        #else
        throw XCTSkip("Seeded response journeys require the installed iOS app in an isolated UI-test store.")
        #endif
    }

    private func chooseResponse(_ label: String, in app: XCUIApplication) {
        let option = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(revealResponseControl(option, in: app))
        XCTAssertTrue(option.exists)
        XCTAssertGreaterThanOrEqual(option.frame.height, 44)
        option.tap()
        assertSelected(option)
    }

    private func assertSelected(_ option: XCUIElement) {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: option)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed, "The visible selection must update before submitting.")
    }

    private func enterText(_ text: String, in field: XCUIElement, app: XCUIApplication, minimumHeight: CGFloat? = nil) {
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertTrue(revealResponseControl(field, in: app))
        if let minimumHeight { XCTAssertGreaterThanOrEqual(field.frame.height, minimumHeight) }
        field.press(forDuration: 0.15)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "The actual response editor must acquire keyboard focus before typing.")
        field.typeText(text)
        let entered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [entered], timeout: 5), .completed)
    }

    private func submitVisibleResponse(in app: XCUIApplication) {
        let submit = element(in: app, identifier: "session-submit")
        XCTAssertTrue(submit.waitForExistence(timeout: 8))
        XCTAssertTrue(revealResponseControl(submit, in: app))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: submit)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        submit.tap()
    }

    private func integers(in text: String, pattern: String) throws -> [Int] {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            XCTFail("The ordinary question must expose the givens needed to select a response.")
            throw NSError(domain: "NeuroForgeUITestFixture", code: 1)
        }
        return try (1..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text), let value = Int(text[range]) else {
                throw NSError(domain: "NeuroForgeUITestFixture", code: 2)
            }
            return value
        }
    }

    private func revealResponseControl(_ target: XCUIElement, in app: XCUIApplication, maximumSwipes: Int = 12, searchAboveWhenAbsent: Bool = false) -> Bool {
        var attempts: [String] = []
        for _ in 0..<maximumSwipes {
            // The last descendant can be an embedded TextEditor scroll view.
            guard let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable }) else { return false }
            let viewport = app.frame
            let keyboardTop = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : viewport.maxY
            let navigationBottom = app.navigationBars.allElementsBoundByIndex
                .filter { $0.isHittable }.map(\.frame.maxY).max() ?? viewport.minY
            let top = max(scroll.frame.minY, viewport.minY, navigationBottom) + 2
            var bottom = min(scroll.frame.maxY, viewport.maxY, keyboardTop) - 2
            if let tabTop = app.tabBars.allElementsBoundByIndex.filter({ $0.isHittable }).map(\.frame.minY).min() {
                bottom = min(bottom, tabTop - 2)
            }
            let targetIdentifier = target.exists ? target.identifier : nil
            let isFooterAction = ["session-submit", "session-next", "session-end-unavailable", "train-start-practice", "train-start-graph-construction", "train-start-coordinate-reasoning", "train-start-spatial-assembly"].contains(targetIdentifier ?? "")
            if isFooterAction, target.exists, target.isHittable,
               target.frame.minY >= viewport.minY, target.frame.maxY <= min(viewport.maxY, keyboardTop) {
                return true
            }
            // XCTest can call a partly occluded scroll child hittable even when
            // its center lies under the persistent footer. Reveal the entire
            // target before one standard tap; absent lazy choices need scrolling.
            for identifier in ["session-submit", "session-next", "train-start-practice", "train-start-graph-construction", "train-start-coordinate-reasoning", "train-start-spatial-assembly"] {
                let footer = element(in: app, identifier: identifier)
                if footer.exists, footer.isHittable, footer.frame.minY > top { bottom = min(bottom, footer.frame.minY - 2) }
            }
            attempts.append("target=\(target.exists ? String(describing: target.frame) : "absent") hittable=\(target.isHittable) scroll=\(scroll.frame) visible=\(top)...\(bottom)")
            if target.exists, target.isHittable,
               target.frame.minY >= top, target.frame.maxY <= bottom { return true }
            guard bottom - top >= 50 else { return false }
            let targetIsAbove = target.exists ? target.frame.minY < top : searchAboveWhenAbsent
            // The center can be a RealityKit orbit surface, a drawing canvas or
            // an editor. Scroll through the page's outer margin so the gesture
            // reaches the containing scroll view without changing the answer.
            let x = scroll.frame.minX + 12
            let available = bottom - top
            let overflow = target.exists
                ? (targetIsAbove ? top - target.frame.minY : target.frame.maxY - bottom)
                : available * 0.5
            // Small controls near a header need a precise drag. A 60pt minimum
            // plus release momentum oscillated the real Data table control
            // between header and footer in the recorded keyboard-visible run.
            let distance = min(available * 0.6, max(16, overflow + 8))
            let startY = top + available * (targetIsAbove ? 0.2 : 0.8)
            let endY = startY + (targetIsAbove ? distance : -distance)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: x, dy: startY)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: x, dy: endY)),
                withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        let attachment = XCTAttachment(string: attempts.joined(separator: "\n"))
        attachment.name = "Response control reveal geometry"
        attachment.lifetime = .keepAlways
        add(attachment)
        return false
    }

    private func persistentLaunchArguments(runID: String, language: String, reset: Bool, startSession: Bool) -> [String] {
        var arguments = ["-ui-testing", "-skip-onboarding", "-ui-test-run-id", runID,
                         "-nf.localization.preferred-language.v1", language,
                         "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ja" ? "ja_JP" : "en_US"]
        if reset { arguments.append("-ui-test-reset-store") }
        if startSession { arguments.append("-ui-test-numeric-session") }
        return arguments
    }

    private func enterNumericAnswer(_ value: String, in app: XCUIApplication) {
        let answer = element(in: app, identifier: "session-numeric-answer")
        XCTAssertTrue(answer.waitForExistence(timeout: 8))
        XCTAssertTrue(revealResponseControl(answer, in: app))
        XCTAssertGreaterThanOrEqual(answer.frame.height, 44, "The numeric input must expose a full-size touch target.")
        answer.press(forDuration: 0.15)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        if let existing = answer.value as? String, !existing.isEmpty, existing.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) {
            answer.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        answer.typeText(value)
        let entered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: answer)
        XCTAssertEqual(XCTWaiter.wait(for: [entered], timeout: 5), .completed, "The typed answer must reach the active answer field.")
        let submit = element(in: app, identifier: "session-submit")
        XCTAssertTrue(scrollUntilHittable(submit, in: app))
    }

    private func saveAndClose(in app: XCUIApplication) {
        let save = element(in: app, identifier: "session-save-close")
        if !save.exists {
            let pause = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Pause session", "セッションを一時停止")).firstMatch
            XCTAssertTrue(pause.waitForExistence(timeout: 5))
            pause.tap()
        }
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(element(in: app, identifier: "destination-today").waitForExistence(timeout: 8))
    }

    private func continueSavedSession(in app: XCUIApplication) {
        let resume = element(in: app, identifier: "continue-session")
        XCTAssertTrue(resume.waitForExistence(timeout: 15))
        XCTAssertTrue(scrollUntilHittable(resume, in: app))
        resume.press(forDuration: 0.15)
        XCTAssertTrue(element(in: app, identifier: "universal-session").waitForExistence(timeout: 8))
        resumeIfOffered(in: app)
    }

    private func resumeIfOffered(in app: XCUIApplication) {
        let explicitResume = element(in: app, identifier: "session-resume")
        if explicitResume.waitForExistence(timeout: 3) {
            let pauseCapture = XCTAttachment(screenshot: app.screenshot())
            pauseCapture.name = "interruption-paused-session-before-explicit-resume"
            pauseCapture.lifetime = .keepAlways
            add(pauseCapture)
            XCTAssertTrue(explicitResume.isHittable, "A paused session must offer a reachable Resume action.")
            // This host intermittently ignored a 50ms native tap at this
            // visible control's center. Use one normal-duration touch; never
            // retry it or bypass the following exact resumed-state checks.
            explicitResume.press(forDuration: 0.15)
            let resumed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: explicitResume)
            XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 8), .completed,
                "The single explicit Resume gesture must be acknowledged before checking saved content.")
        }
    }

    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func launchArguments(
        skipOnboarding: Bool,
        contentSizeCategory: String = "UICTContentSizeCategoryL"
    ) -> [String] {
        var arguments = [
            "-ui-testing",
            "-nf.localization.preferred-language.v1", "en",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", contentSizeCategory
        ]
        if skipOnboarding {
            arguments.append("-skip-onboarding")
        }
        return arguments
    }

    @discardableResult
    private func scrollUntilHittable(
        _ target: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 12
    ) -> Bool {
        for _ in 0..<maximumSwipes {
            if target.exists, target.isHittable { return true }
            if let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                scroll.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        return target.exists && target.isHittable
    }

    private func assertFullyContained(
        _ element: XCUIElement,
        in window: XCUIElement,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frame = element.frame
        let windowFrame = window.frame.insetBy(dx: -1, dy: -1)
        XCTAssertFalse(frame.isEmpty, "\(context) has an empty frame.", file: file, line: line)
        XCTAssertTrue(
            windowFrame.contains(frame),
            "\(context) frame \(frame) extends beyond the compact window \(window.frame).",
            file: file,
            line: line
        )
    }

    private func primaryNavigation(
        in app: XCUIApplication,
        destinationID: String,
        expectedLabel: String
    ) -> XCUIElement {
        #if os(iOS)
        app.tabBars.buttons[expectedLabel]
        #else
        element(in: app, identifier: "primary-navigation-\(destinationID)")
        #endif
    }
}

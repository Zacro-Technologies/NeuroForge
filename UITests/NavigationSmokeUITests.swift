import XCTest

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
            "The deterministic launch should open the Forge destination."
        )

        let destinations = [
            (id: "train", expectedLabel: "Practice"),
            (id: "progress", expectedLabel: "Progress"),
            (id: "library", expectedLabel: "Sources"),
            (id: "settings", expectedLabel: "Settings"),
            (id: "today", expectedLabel: "Forge")
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
        }
    }

    func testOnboardingReflowsAtMaximumAccessibilitySizeOnCompactPhone() throws {
        #if os(iOS)
        let app = XCUIApplication()
        app.launchArguments = launchArguments(
            skipOnboarding: false,
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        )
        app.launch()
        defer { app.terminate() }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15))

        let primaryAction = element(in: app, identifier: "onboarding-primary-action")
        XCTAssertTrue(primaryAction.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Build an all-round STEM toolkit."].exists)
        assertFullyContained(primaryAction, in: window, context: "welcome primary action")
        XCTAssertTrue(primaryAction.isHittable)

        primaryAction.tap()
        XCTAssertTrue(app.staticTexts["Shape your balanced practice"].waitForExistence(timeout: 5))
        XCTAssertEqual(primaryAction.label, "Continue")
        assertFullyContained(primaryAction, in: window, context: "profile primary action")
        XCTAssertTrue(primaryAction.isHittable)

        primaryAction.tap()
        XCTAssertTrue(app.staticTexts["Set your daily circuit"].waitForExistence(timeout: 5))
        XCTAssertEqual(primaryAction.label, "Open the Forge")
        assertFullyContained(primaryAction, in: window, context: "routine primary action")
        XCTAssertTrue(primaryAction.isHittable)

        let skillCheck = element(in: app, identifier: "onboarding-skill-check-action")
        XCTAssertTrue(skillCheck.waitForExistence(timeout: 5))
        assertFullyContained(skillCheck, in: window, context: "routine skill-check action")
        XCTAssertTrue(skillCheck.isHittable)
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
            app.swipeUp()
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

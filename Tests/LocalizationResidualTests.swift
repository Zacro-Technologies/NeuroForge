import Foundation
import XCTest

@testable import NeuroForge

final class LocalizationResidualTests: XCTestCase {
    func testReportStatusesLocalizeInBothSupportedLanguages() {
        let english = NFAppLocalization.locale(identifier: "en")
        let japanese = NFAppLocalization.locale(identifier: "ja")

        XCTAssertEqual(
            NFItemReportStatusCopy.title(for: "quarantined", locale: english),
            "Excluded from future practice"
        )
        XCTAssertEqual(
            NFItemReportStatusCopy.title(for: "active", locale: english),
            "Allowed in future practice"
        )
        XCTAssertEqual(
            NFItemReportStatusCopy.exportLine(for: "active", locale: english),
            "Status: Allowed in future practice"
        )

        XCTAssertTrue(containsJapaneseScript(
            NFItemReportStatusCopy.title(for: "quarantined", locale: japanese)
        ))
        XCTAssertTrue(containsJapaneseScript(
            NFItemReportStatusCopy.title(for: "active", locale: japanese)
        ))
        XCTAssertTrue(containsJapaneseScript(
            NFItemReportStatusCopy.exportLine(for: "active", locale: japanese)
        ))
    }

    func testUnknownScoringCodeNeverReachesLearnerFacingCopy() {
        let unknownCode = "private_future_scoring_code"
        let english = NFAppLocalization.locale(identifier: "en")
        let japanese = NFAppLocalization.locale(identifier: "ja")

        for locale in [english, japanese] {
            let title = NFScoringErrorCopy.title(for: unknownCode, locale: locale)
            XCTAssertFalse(title.contains(unknownCode))
            XCTAssertFalse(title.contains("_"))
            XCTAssertNil(NFUserFacingContentLinter.lint(title))
        }
        XCTAssertTrue(containsJapaneseScript(
            NFScoringErrorCopy.title(for: unknownCode, locale: japanese)
        ))
    }

    func testReportHistorySearchIncludesLocaleFormattedCreatedDate() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-30T14:35:00Z"))
        for locale in [
            NFAppLocalization.locale(identifier: "en"),
            NFAppLocalization.locale(identifier: "ja")
        ] {
            let dateQuery = NFAppLocalization.formattedDate(
                date,
                date: .complete,
                time: .omitted,
                locale: locale
            )
            XCTAssertTrue(NFItemReportHistoryQuery.matches(
                prompt: "Unrelated prompt",
                reason: "Unrelated reason",
                note: "",
                createdAt: date,
                query: dateQuery,
                locale: locale
            ))
            XCTAssertFalse(NFItemReportHistoryQuery.matches(
                prompt: "Unrelated prompt",
                reason: "Unrelated reason",
                note: "",
                createdAt: date,
                query: "not-a-date-or-report-field",
                locale: locale
            ))
        }
    }

    private func containsJapaneseScript(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)
                || (0x3400...0x9FFF).contains(scalar.value)
        }
    }
}

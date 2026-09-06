import Foundation
import XCTest
@testable import NeuroForge

@MainActor
final class NFSourceAIAvailabilityTests: XCTestCase {
    func testSourceLabelsDescribeAIUseAndPreserveStoredPolicyValues() {
        let english = Locale(identifier: "en")
        XCTAssertEqual(NFSourceAIAvailabilityPresentation.title(for: .privateCloudAllowed, locale: english), "Automatic AI")
        XCTAssertEqual(NFSourceAIAvailabilityPresentation.title(for: .onDeviceOnly, locale: english), "On-device AI")
        XCTAssertEqual(NFSourceAIAvailabilityPresentation.title(for: .noAI, locale: english), "Source review only")
        XCTAssertEqual(DocumentAIPolicy(rawValue: "privateCloudAllowed"), .privateCloudAllowed)
        XCTAssertEqual(DocumentAIPolicy(rawValue: "onDeviceOnly"), .onDeviceOnly)
        XCTAssertEqual(DocumentAIPolicy(rawValue: "noAI"), .noAI)
    }

    func testNativeOnDevicePracticeAllowsReadableCodeAndTables() {
        XCTAssertTrue(NFSourceAIAvailabilityPresentation.allowsQuestionSet(
            aiMode: .onDeviceOnly, sourcePolicy: .onDeviceOnly,
            chunkCount: 3, isProcessing: false, hasProseRecall: false))
        XCTAssertTrue(NFSourceAIAvailabilityPresentation.allowsQuestionSet(
            aiMode: .automatic, sourcePolicy: .onDeviceOnly,
            chunkCount: 3, isProcessing: false, hasProseRecall: false))
    }

    func testDisabledAIPreservesProseFallbackButDoesNotInventANonProseFallback() {
        XCTAssertTrue(NFSourceAIAvailabilityPresentation.allowsQuestionSet(
            aiMode: .disabled, sourcePolicy: .onDeviceOnly,
            chunkCount: 2, isProcessing: false, hasProseRecall: true))
        XCTAssertFalse(NFSourceAIAvailabilityPresentation.allowsQuestionSet(
            aiMode: .disabled, sourcePolicy: .privateCloudAllowed,
            chunkCount: 2, isProcessing: false, hasProseRecall: false))
    }

    func testSourceReviewOnlyAndUnreadySourcesCannotLaunchQuestionCreation() {
        XCTAssertFalse(NFSourceAIAvailabilityPresentation.allowsQuestionSet(
            aiMode: .automatic, sourcePolicy: .noAI,
            chunkCount: 2, isProcessing: false, hasProseRecall: true))
        XCTAssertFalse(NFSourceAIAvailabilityPresentation.allowsQuestionSet(
            aiMode: .automatic, sourcePolicy: .privateCloudAllowed,
            chunkCount: 0, isProcessing: false, hasProseRecall: false))
        XCTAssertFalse(NFSourceAIAvailabilityPresentation.allowsQuestionSet(
            aiMode: .automatic, sourcePolicy: .privateCloudAllowed,
            chunkCount: 2, isProcessing: true, hasProseRecall: false))
    }

    func testReadinessUsesTheActualGlobalModeAndSourceRestriction() {
        let automatic = NFDocumentReadinessPresentation.make(indexState: "ready", chunkCount: 2,
            aiPolicy: .privateCloudAllowed, aiMode: .automatic)
        let local = NFDocumentReadinessPresentation.make(indexState: "ready", chunkCount: 2,
            aiPolicy: .onDeviceOnly, aiMode: .automatic)
        let disabled = NFDocumentReadinessPresentation.make(indexState: "ready", chunkCount: 2,
            aiPolicy: .privateCloudAllowed, aiMode: .disabled)
        let review = NFDocumentReadinessPresentation.make(indexState: "ready", chunkCount: 2,
            aiPolicy: .noAI, aiMode: .automatic)
        XCTAssertEqual(Set([automatic.questionStatus, local.questionStatus, disabled.questionStatus, review.questionStatus]).count, 4)
        XCTAssertEqual(automatic.indexStatus, disabled.indexStatus)
    }

    func testNewSourcesDefaultToAutomaticAndExistingExplicitPoliciesStayIntact() {
        let newSource = SourceDocumentRecord(filename: "new-notes.txt", typeIdentifier: "public.plain-text", sizeBytes: 20, localPath: "/synthetic/new-notes.txt")
        XCTAssertEqual(newSource.aiPolicyRaw, DocumentAIPolicy.privateCloudAllowed.rawValue)
        for savedPolicy in [DocumentAIPolicy.onDeviceOnly, .noAI] {
            let existing = SourceDocumentRecord(filename: "saved-notes.txt", typeIdentifier: "public.plain-text", sizeBytes: 20, localPath: "/synthetic/saved-notes.txt")
            existing.aiPolicyRaw = savedPolicy.rawValue
            _ = NFSourceAIAvailabilityPresentation.title(for: savedPolicy)
            _ = NFDocumentReadinessPresentation.make(indexState: "ready", chunkCount: 2,
                aiPolicy: savedPolicy, aiMode: .automatic)
            XCTAssertEqual(existing.aiPolicyRaw, savedPolicy.rawValue)
        }
    }
}

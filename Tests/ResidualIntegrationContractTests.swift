import Foundation
import XCTest

@testable import NeuroForge

final class ResidualIntegrationContractTests: XCTestCase {
    func testDeepLinkParserRoutesDueAndCompletedReviewsSeparately() throws {
        XCTAssertEqual(
            NFExternalRoute.parse(try XCTUnwrap(URL(string: "neuroforge://today?review=due"))),
            .dueTodayReview
        )
        XCTAssertEqual(
            NFExternalRoute.parse(try XCTUnwrap(URL(string: "neuroforge://today?review=completed"))),
            .completedTodayReview
        )
        XCTAssertNil(NFExternalRoute.parse(
            try XCTUnwrap(URL(string: "neuroforge://today?review=unknown"))
        ))
    }

    func testSourceReviewDeepLinkCarriesExactOpaqueDestination() throws {
        let documentID = UUID()
        let reviewID = UUID()
        let url = try XCTUnwrap(URL(string:
            "neuroforge://reviews/\(documentID.uuidString)?chunk=chunk.4f2a&review=\(reviewID.uuidString)"
        ))
        XCTAssertEqual(
            NFExternalRoute.parse(url),
            .sourceReviews(try XCTUnwrap(NFSourceReviewDeepLinkDestination(
                documentID: documentID,
                chunkID: "chunk.4f2a",
                reviewID: reviewID
            )))
        )

        XCTAssertNil(NFExternalRoute.parse(try XCTUnwrap(URL(string:
            "neuroforge://reviews/\(documentID.uuidString)?review=\(reviewID.uuidString)"
        ))), "A saved review ID is ambiguous without its exact chunk")
        XCTAssertNil(NFExternalRoute.parse(try XCTUnwrap(URL(string:
            "neuroforge://reviews/\(documentID.uuidString)?chunk=Private%20Notes.pdf"
        ))), "Learner-facing source names must not be accepted as opaque route IDs")
    }

    func testExactSourceReviewResolverRejectsEveryIdentifierMismatch() throws {
        let documentID = UUID()
        let document = SourceDocumentRecord(
            filename: "Private notes.pdf",
            typeIdentifier: "com.adobe.pdf",
            sizeBytes: 12,
            localPath: "/private/redacted"
        )
        document.id = documentID
        let chunkID = "chunk.4f2a"
        let chunk = SourceChunkRecord(chunk: NFSourceChunk(
            id: chunkID,
            documentID: documentID,
            documentVersion: 1,
            sourceName: document.filename,
            locator: NFSourceLocator(page: 1, lineStart: nil, lineEnd: nil, section: nil),
            text: "Private source text",
            contentHash: "4f2a",
            ordinal: 0
        ))
        let attempt = AttemptRecord(
            sessionID: UUID(),
            lab: .retrieval,
            itemID: "source-review",
            prompt: "Exact saved prompt",
            response: "Exact saved response",
            correctAnswer: "Self-checked",
            isCorrect: true,
            confidence: .fairlyConfident,
            evidenceClass: .documentPractice,
            source: .focused,
            sourceDocumentIDs: [documentID],
            sourceChunkIDs: [chunkID],
            responseFormat: NFSourceReviewRotation.responseFormat
        )
        let destination = try XCTUnwrap(NFSourceReviewDeepLinkDestination(
            documentID: documentID,
            chunkID: chunkID,
            reviewID: attempt.id
        ))
        XCTAssertTrue(NFSourceReviewDestinationResolver.savedReview(
            for: destination,
            documents: [document],
            chunks: [chunk],
            attempts: [attempt]
        ) === attempt)

        let wrongReview = try XCTUnwrap(NFSourceReviewDeepLinkDestination(
            documentID: documentID,
            chunkID: chunkID,
            reviewID: UUID()
        ))
        XCTAssertNil(NFSourceReviewDestinationResolver.savedReview(
            for: wrongReview,
            documents: [document],
            chunks: [chunk],
            attempts: [attempt]
        ))
        let wrongChunk = try XCTUnwrap(NFSourceReviewDeepLinkDestination(
            documentID: documentID,
            chunkID: "chunk.other",
            reviewID: attempt.id
        ))
        XCTAssertNil(NFSourceReviewDestinationResolver.savedReview(
            for: wrongChunk,
            documents: [document],
            chunks: [chunk],
            attempts: [attempt]
        ))
    }

    @MainActor
    func testSessionCommandCapabilitiesFollowConsumablePhase() {
        let readyItem = NFSessionCommandCapabilities.resolve(
            stage: .item,
            isPaused: false,
            canSubmit: true
        )
        XCTAssertTrue(readyItem.canAdvance)
        XCTAssertTrue(readyItem.canTogglePause)
        XCTAssertTrue(readyItem.canShowScratchpad)

        let incompleteItem = NFSessionCommandCapabilities.resolve(
            stage: .item,
            isPaused: false,
            canSubmit: false
        )
        XCTAssertFalse(incompleteItem.canAdvance)
        XCTAssertTrue(incompleteItem.canTogglePause)

        let paused = NFSessionCommandCapabilities.resolve(
            stage: .selfCheckComparison,
            isPaused: true,
            canSubmit: true
        )
        XCTAssertFalse(paused.canAdvance)
        XCTAssertTrue(paused.canTogglePause, "Resume remains consumable")
        XCTAssertFalse(paused.canShowScratchpad)

        let confidence = NFSessionCommandCapabilities.resolve(
            stage: .confidence,
            isPaused: false,
            canSubmit: true
        )
        XCTAssertFalse(confidence.canAdvance, "Confidence must be chosen in the phase UI")
        XCTAssertTrue(confidence.canTogglePause)
        XCTAssertTrue(confidence.canShowScratchpad)

        let feedback = NFSessionCommandCapabilities.resolve(
            stage: .feedback,
            isPaused: false,
            canSubmit: false
        )
        XCTAssertTrue(feedback.canAdvance, "Submit or Next must advance visible feedback")
        XCTAssertTrue(feedback.canTogglePause)
        XCTAssertTrue(feedback.canShowScratchpad)

        let pausedFeedback = NFSessionCommandCapabilities.resolve(
            stage: .feedback,
            isPaused: true,
            canSubmit: false
        )
        XCTAssertFalse(pausedFeedback.canAdvance)
        XCTAssertTrue(pausedFeedback.canTogglePause, "Resume remains consumable from feedback")
        XCTAssertFalse(pausedFeedback.canShowScratchpad)

        XCTAssertEqual(
            NFSessionCommandCapabilities.resolve(
                stage: .summary,
                isPaused: true,
                canSubmit: true
            ),
            .inactive,
            "Completed summaries must not consume session commands"
        )
    }

    func testGeneratedPracticeCommandCapabilitiesExposeSubmitAndFeedbackNext() {
        XCTAssertEqual(
            NFAIGeneratedPracticeCommandPolicy.resolve(stage: 0, canSubmit: false),
            .inactive
        )

        let response = NFAIGeneratedPracticeCommandPolicy.resolve(stage: 0, canSubmit: true)
        XCTAssertTrue(response.canAdvance)
        XCTAssertFalse(response.canTogglePause)
        XCTAssertFalse(response.canShowScratchpad)

        XCTAssertTrue(
            NFAIGeneratedPracticeCommandPolicy.resolve(stage: 4, canSubmit: true).canAdvance,
            "Self-check comparison consumes Submit"
        )
        XCTAssertTrue(
            NFAIGeneratedPracticeCommandPolicy.resolve(stage: 2, canSubmit: false).canAdvance,
            "Feedback consumes Next"
        )
        XCTAssertEqual(
            NFAIGeneratedPracticeCommandPolicy.resolve(stage: 3, canSubmit: true),
            .inactive,
            "Completed summary consumes no command"
        )
    }

    @MainActor
    func testSessionCommandBridgeTargetsOnlyCurrentRequestAndRejectsStaleUpdates() {
        let bridge = NFSessionCommandBridge()
        let firstID = UUID()
        let secondID = UUID()
        bridge.activate(
            requestID: firstID,
            capabilities: NFSessionCommandCapabilities(
                canAdvance: true,
                canTogglePause: true,
                canShowScratchpad: true
            )
        )
        bridge.activate(requestID: secondID, capabilities: .inactive)
        bridge.update(
            requestID: firstID,
            capabilities: NFSessionCommandCapabilities(
                canAdvance: true,
                canTogglePause: true,
                canShowScratchpad: true
            )
        )
        XCTAssertEqual(bridge.activeRequestID, secondID)
        XCTAssertEqual(bridge.capabilities, .inactive)
        XCTAssertFalse(bridge.send(.advance, center: NotificationCenter()))

        let center = NotificationCenter()
        let targetedNotification = XCTNSNotificationExpectation(
            name: .neuroForgeAdvanceUniversalSession,
            object: nil,
            notificationCenter: center
        )
        targetedNotification.handler = { notification in
            notification.object as? UUID == secondID
        }
        bridge.update(
            requestID: secondID,
            capabilities: NFSessionCommandCapabilities(
                canAdvance: true,
                canTogglePause: false,
                canShowScratchpad: false
            )
        )
        XCTAssertTrue(bridge.send(.advance, center: center))
        wait(for: [targetedNotification], timeout: 1)

        bridge.deactivate(requestID: firstID)
        XCTAssertTrue(bridge.hasConsumer)
        bridge.deactivate(requestID: secondID)
        XCTAssertFalse(bridge.hasConsumer)
        XCTAssertEqual(bridge.capabilities, .inactive)
    }
}

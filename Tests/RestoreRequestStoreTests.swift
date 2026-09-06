import XCTest
import Foundation
@testable import NeuroForge

@MainActor final class RestoreRequestStoreTests: XCTestCase {
    private func fixture() throws -> (URL, NFApplicationStoreLease, NFRestoreRestartRequest) {
        let root = FileManager.default.temporaryDirectory.appending(path: "NF-RestoreRequest-\(UUID().uuidString)")
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let bytes = Data("{\"validated-permitted-fixture\":true}".utf8)
        let request = NFRestoreRestartRequest(version: 1, transactionID: UUID(),
            namespace: String(repeating: "a", count: 64), installationOwnerID: UUID(),
            sourceDigest: String(repeating: "b", count: 64), sourceByteCount: bytes.count,
            sourceFilename: "Backup.json", permittedPayload: bytes,
            permittedPayloadDigest: NFRestoreJournalCodec.digest(bytes),
            reviewedDestinationDigest: String(repeating: "c", count: 64),
            policyRaw: NFDataArchiveRestorePolicy.keepExisting.rawValue, localeIdentifier: "ja", compiledAtReferenceSeconds: 800_000_000)
        return (root, lease, request)
    }

    func testPrivateRequestColdLoadRetainsEveryReviewedByteAndAcceptsOnlyIdenticalRetry() async throws {
        let (root, lease, request) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = NFRestoreRequestStore.root(applicationSupportURL: root)
        let first = NFRestoreRequestStore(root: directory, lease: lease)
        try await first.stage(request)
        let cold = NFRestoreRequestStore(root: directory, lease: lease)
        let loaded = try await cold.load(transactionID: request.transactionID, namespace: request.namespace, owner: request.installationOwnerID)
        XCTAssertEqual(loaded, request)
        try await cold.stage(request)
        let entries = try await cold.inspectAll()
        XCTAssertEqual(entries.count, 1); XCTAssertNil(entries[0].receipt)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int, 0o700)
        let payload = directory.appending(path: request.transactionID.uuidString.lowercased() + ".request")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: payload.path)[.posixPermissions] as? Int, 0o600)
        let changed = NFRestoreRestartRequest(version: 1, transactionID: request.transactionID,
            namespace: request.namespace, installationOwnerID: request.installationOwnerID,
            sourceDigest: request.sourceDigest, sourceByteCount: request.sourceByteCount,
            sourceFilename: request.sourceFilename, permittedPayload: request.permittedPayload,
            permittedPayloadDigest: request.permittedPayloadDigest,
            reviewedDestinationDigest: String(repeating: "d", count: 64), policyRaw: request.policyRaw,
            localeIdentifier: request.localeIdentifier, compiledAtReferenceSeconds: request.compiledAtReferenceSeconds)
        do { try await cold.stage(changed); XCTFail("An old command cannot acquire a changed preview.") }
        catch { XCTAssertEqual(error as? NFRestoreJournalError, .conflictingPlan) }
    }

    func testReceiptSurvivesCleanupFailureAndPermanentlyPreventsDelayedRestaging() async throws {
        let (root, lease, request) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = NFRestoreRequestStore.root(applicationSupportURL: root)
        let failing = NFRestoreRequestStore(root: directory, lease: lease) { boundary in
            if boundary == .beforePayloadCleanup { throw NFRestoreJournalError.ioFailure }
        }
        try await failing.stage(request)
        do { _ = try await failing.resolve(request, resolution: .cancelled); XCTFail("Expected injected cleanup failure") }
        catch { XCTAssertEqual(error as? NFRestoreJournalError, .ioFailure) }
        let cold = NFRestoreRequestStore(root: directory, lease: lease)
        let entries = try await cold.inspectAll()
        XCTAssertEqual(entries.count, 1); XCTAssertTrue(entries[0].cleanupRequired)
        let receipt = try XCTUnwrap(entries[0].receipt)
        XCTAssertEqual(receipt.resolution, .cancelled)
        do { try await cold.stage(request); XCTFail("Cancellation must win before cleanup succeeds.") }
        catch { XCTAssertEqual(error as? NFRestoreJournalError, .invalidated) }
        try await cold.finishReceiptCleanup(receipt)
        let after = try await cold.inspectAll()
        XCTAssertFalse(after[0].cleanupRequired)
        do { _ = try await cold.load(transactionID: request.transactionID, namespace: request.namespace, owner: request.installationOwnerID); XCTFail("Cancelled bytes cannot become a plan.") }
        catch { XCTAssertEqual(error as? NFRestoreJournalError, .invalidated) }
    }

    func testRequestPublicationLostAcknowledgementReconcilesExactBytesWithoutAnotherCommand() async throws {
        let (root, lease, request) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = NFRestoreRequestStore.root(applicationSupportURL: root)
        let failing = NFRestoreRequestStore(root: directory, lease: lease) { boundary in
            if boundary == .afterRequestPublish { throw NFRestoreJournalError.ioFailure }
        }
        do { try await failing.stage(request); XCTFail("Expected lost acknowledgement") }
        catch { XCTAssertEqual(error as? NFRestoreJournalError, .ioFailure) }
        let cold = NFRestoreRequestStore(root: directory, lease: lease)
        try await cold.stage(request)
        let loaded = try await cold.load(transactionID: request.transactionID, namespace: request.namespace, owner: request.installationOwnerID)
        XCTAssertEqual(loaded, request)
    }

    func testUnpublishedRequestFailureLeavesNoAcceptedRequest() async throws {
        for boundary in [NFRestoreRequestStore.Boundary.beforeRequestWrite, .afterRequestWrite, .beforeRequestPublish] {
            let (root, lease, request) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            let directory = NFRestoreRequestStore.root(applicationSupportURL: root)
            let failing = NFRestoreRequestStore(root: directory, lease: lease) { current in
                if current == boundary { throw NFRestoreJournalError.ioFailure }
            }
            do { try await failing.stage(request); XCTFail("Expected unpublished boundary failure") } catch { }
            let cold = NFRestoreRequestStore(root: directory, lease: lease)
            let entries = try await cold.inspectAll()
            XCTAssertTrue(entries.isEmpty)
        }
    }

    func testUnknownArtifactsAndNonregularPayloadsBlockWithoutDiscardingOriginals() async throws {
        for kind in ["unknown", "symlink", "fifo"] {
            let (root, lease, request) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
            let directory = NFRestoreRequestStore.root(applicationSupportURL: root)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let artifact = directory.appending(path: kind == "unknown" ? ".interrupted.tmp" : request.transactionID.uuidString.lowercased() + ".request")
            if kind == "unknown" { try Data("retained-private-original".utf8).write(to: artifact) }
            else if kind == "symlink" { try FileManager.default.createSymbolicLink(atPath: artifact.path, withDestinationPath: "/dev/null") }
            else { XCTAssertEqual(mkfifo(artifact.path, 0o600), 0) }
            let store = NFRestoreRequestStore(root: directory, lease: lease)
            do { _ = try await store.inspectAll(); XCTFail("Unknown/private originals require recovery.") } catch { }
            var info = stat(); XCTAssertEqual(lstat(artifact.path, &info), 0)
        }
    }

    func testColdStartupReclaimsOnlyRecognizedUnpublishedRegularTemporaryBytes() async throws {
        let (root, lease, request) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = NFRestoreRequestStore.root(applicationSupportURL: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appending(path: ".unpublished-\(UUID().uuidString.lowercased()).tmp")
        try Data("interrupted-before-request-publication".utf8).write(to: temporary)
        let cold = NFRestoreRequestStore(root: directory, lease: lease)
        let entries = try await cold.inspectAll()
        XCTAssertTrue(entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
        try await cold.stage(request)
        let published = try await cold.load(transactionID: request.transactionID, namespace: request.namespace, owner: request.installationOwnerID)
        XCTAssertEqual(published, request)
        let special = directory.appending(path: ".unpublished-\(UUID().uuidString.lowercased()).tmp")
        XCTAssertEqual(mkfifo(special.path, 0o600), 0)
        do { _ = try await cold.inspectAll(); XCTFail("A reserved name does not permit removing a special file.") } catch { }
        var metadata = stat(); XCTAssertEqual(lstat(special.path, &metadata), 0)
    }

    func testWrongOwnerCannotLoadAndSealedProducerCannotStage() async throws {
        let (root, lease, request) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease)
        try await store.stage(request)
        do { _ = try await store.load(transactionID: request.transactionID, namespace: request.namespace, owner: UUID()); XCTFail("The imported profile never grants installation ownership.") }
        catch { XCTAssertEqual(error as? NFRestoreJournalError, .conflictingPlan) }
        await store.seal()
        do { try await store.stage(request); XCTFail("A stale account/deletion producer stays sealed.") }
        catch { XCTAssertEqual(error as? NFRestoreJournalError, .invalidated) }
        let loaded = try await store.load(transactionID: request.transactionID, namespace: request.namespace, owner: request.installationOwnerID)
        XCTAssertEqual(loaded, request, "Sealing a producer does not silently destroy accepted review bytes.")
    }

    func testCompletedReceiptIsIdempotentAndCannotBeReinterpretedAsCancellation() async throws {
        let (root, lease, request) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease)
        try await store.stage(request)
        let digest = String(repeating: "d", count: 64), counts = ["restored.attempts": 3]
        let receipt = try await store.resolve(request, resolution: .completed, acceptedPlanDigest: digest, counts: counts)
        let retry = try await store.resolve(request, resolution: .completed, acceptedPlanDigest: digest, counts: counts)
        XCTAssertEqual(receipt, retry)
        do { _ = try await store.resolve(request, resolution: .cancelled); XCTFail("Completion cannot lose its verified counts.") }
        catch { XCTAssertEqual(error as? NFRestoreJournalError, .conflictingPlan) }
        let entries = try await store.inspectAll()
        XCTAssertEqual(entries.first?.receipt?.counts, counts)
        XCTAssertFalse(entries.first?.cleanupRequired ?? true)
    }

    func testCompletionRemainsUnacknowledgedAcrossColdOpenUntilReceiptBoundAcknowledgement() async throws {
        let (root, lease, request) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = NFRestoreRequestStore.root(applicationSupportURL: root)
        let store = NFRestoreRequestStore(root: directory, lease: lease)
        try await store.stage(request)
        let receipt = try await store.resolve(request, resolution: .completed,
            acceptedPlanDigest: String(repeating: "d", count: 64), counts: ["restored.attempts": 3])
        let cold = NFRestoreRequestStore(root: directory, lease: lease)
        let initial = try await cold.inspectAll()
        XCTAssertEqual(initial.first?.receipt, receipt)
        XCTAssertEqual(initial.first?.completionAcknowledged, false)
        try await cold.acknowledgeCompletion(receipt)
        try await cold.acknowledgeCompletion(receipt)
        let reopened = NFRestoreRequestStore(root: directory, lease: lease)
        let after = try await reopened.inspectAll()
        XCTAssertEqual(after.first?.receipt, receipt, "Acknowledgement never erases verified counts or permits replay.")
        XCTAssertEqual(after.first?.completionAcknowledged, true)
        do { try await reopened.stage(request); XCTFail("Acknowledgement cannot make an old request eligible again.") }
        catch { XCTAssertEqual(error as? NFRestoreJournalError, .invalidated) }
    }

    func testCompletionAcknowledgementRejectsChangedCountsAndUnboundOrMalformedMarker() async throws {
        let (root, lease, request) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = NFRestoreRequestStore.root(applicationSupportURL: root)
        let store = NFRestoreRequestStore(root: directory, lease: lease)
        try await store.stage(request)
        let receipt = try await store.resolve(request, resolution: .completed,
            acceptedPlanDigest: String(repeating: "d", count: 64), counts: ["restored.attempts": 3])
        let changed = NFRestoreRequestReceipt(version: receipt.version, transactionID: receipt.transactionID,
            namespace: receipt.namespace, installationOwnerID: receipt.installationOwnerID,
            requestDigest: receipt.requestDigest, resolution: receipt.resolution,
            acceptedPlanDigest: receipt.acceptedPlanDigest, counts: ["restored.attempts": 4])
        do { try await store.acknowledgeCompletion(changed); XCTFail("Only the actual displayed receipt can be acknowledged.") }
        catch { XCTAssertEqual(error as? NFRestoreJournalError, .conflictingPlan) }
        let marker = directory.appending(path: request.transactionID.uuidString.lowercased() + ".ack")
        try Data(String(repeating: "f", count: 64).utf8).write(to: marker)
        do { _ = try await store.inspectAll(); XCTFail("A mismatched marker cannot hide an unacknowledged completion.") }
        catch { XCTAssertEqual(error as? NFRestoreJournalError, .digestMismatch) }
        try FileManager.default.removeItem(at: marker)
        let unbound = directory.appending(path: UUID().uuidString.lowercased() + ".ack")
        try Data(String(repeating: "f", count: 64).utf8).write(to: unbound)
        do { _ = try await store.inspectAll(); XCTFail("An orphan acknowledgement requires recovery.") }
        catch { XCTAssertEqual(error as? NFRestoreJournalError, .malformed) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: unbound.path))
    }
}

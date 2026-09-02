import Foundation
import SwiftData
import XCTest
@testable import NeuroForge

final class DocumentImportLifecycleTests: XCTestCase {
    func testBatchReadinessCountsDoNotTreatExtractionFailureAsReady() {
        var counts = NFImportReadinessCounts()
        counts.record(indexState: "ready")
        counts.record(indexState: "extractionFailed")
        counts.record(indexState: "extracting")

        XCTAssertEqual(counts.readyCount, 1)
        XCTAssertEqual(counts.needsReprocessingCount, 2)
        XCTAssertEqual(
            NFInterruptedImportSummary.classify(
                readyCount: counts.readyCount,
                needsReprocessingCount: counts.needsReprocessingCount
            ),
            .needsReprocessing(count: 2, hasReadySources: true)
        )
        XCTAssertEqual(
            NFInterruptedImportSummary.classify(readyCount: 0, needsReprocessingCount: 0),
            .noSavedSources
        )
    }

    @MainActor
    func testAsyncImportPublishesOrderedStagesAndCommitsReadyDocument() async throws {
        let (store, container, documentRoot) = try makeStore()
        defer {
            _ = container
            try? FileManager.default.removeItem(at: documentRoot)
        }
        let sourceURL = FileManager.default.temporaryDirectory
            .appending(path: "import-lifecycle-\(UUID().uuidString).md")
        try Data("# Conservation\nA closed-system balance tracks inflow, outflow, and accumulation.".utf8)
            .write(to: sourceURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        var stages: [NFDocumentImportStage] = []
        let document = try await store.importDocumentAsync(from: sourceURL) { stages.append($0) }

        XCTAssertEqual(stages, [.copying, .extracting, .saving, .complete])
        XCTAssertEqual(document.indexState, "ready")
        XCTAssertGreaterThan(document.chunkCount, 0)
        XCTAssertNotEqual(document.localPath, sourceURL.path)
        XCTAssertTrue(document.localPath.hasPrefix(documentRoot.standardizedFileURL.path + "/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: document.localPath))
        XCTAssertEqual(store.chunks(for: document).count, document.chunkCount)

        try store.deleteDocument(document)
        XCTAssertFalse(FileManager.default.fileExists(atPath: document.localPath))
    }

    @MainActor
    func testExtractionFailureIsDurableAndRetryRebuildsLocalChunks() async throws {
        let (store, container, documentRoot) = try makeStore()
        defer {
            _ = container
            try? FileManager.default.removeItem(at: documentRoot)
        }
        let sourceURL = FileManager.default.temporaryDirectory
            .appending(path: "empty-import-\(UUID().uuidString).txt")
        try Data().write(to: sourceURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let document = try await store.importDocumentAsync(from: sourceURL) { _ in }
        XCTAssertEqual(document.indexState, "extractionFailed")
        XCTAssertEqual(document.chunkCount, 0)
        XCTAssertNotNil(document.indexError)

        try Data("A repaired local source now contains enough text to index.".utf8)
            .write(to: URL(fileURLWithPath: document.localPath), options: .atomic)
        try await store.retryDocumentExtraction(for: document)

        XCTAssertEqual(document.indexState, "ready")
        XCTAssertGreaterThan(document.chunkCount, 0)
        XCTAssertNil(document.indexError)
        XCTAssertEqual(store.chunks(for: document).count, document.chunkCount)

        try store.deleteDocument(document)
    }

    func testManagedCopyRejectsUnsupportedNonregularAndOversizedInputs() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "NF-Import-Gates-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let managedRoot = folder.appending(path: "Managed", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let unsupported = folder.appending(path: "unsupported.docx")
        try Data("not an OOXML import".utf8).write(to: unsupported)
        do {
            _ = try await NFDocumentImportPipeline.copyIntoManagedStorage(
                from: unsupported,
                managedStorageRootURL: managedRoot
            )
            XCTFail("Unsupported extensions must fail before copying")
        } catch {
            XCTAssertEqual(error as? NFDocumentImportValidationError, .unsupportedType)
        }

        let disguisedDirectory = folder.appending(path: "folder.md", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: disguisedDirectory, withIntermediateDirectories: true)
        do {
            _ = try await NFDocumentImportPipeline.copyIntoManagedStorage(
                from: disguisedDirectory,
                managedStorageRootURL: managedRoot
            )
            XCTFail("Directories must fail before copying")
        } catch {
            XCTAssertEqual(error as? NFDocumentImportValidationError, .notRegularFile)
        }

        let target = folder.appending(path: "target.md")
        let link = folder.appending(path: "linked.md")
        try Data("A regular target must not make a symbolic link importable.".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        do {
            _ = try await NFDocumentImportPipeline.copyIntoManagedStorage(
                from: link,
                managedStorageRootURL: managedRoot
            )
            XCTFail("Symbolic links must fail before copying")
        } catch {
            XCTAssertEqual(error as? NFDocumentImportValidationError, .notRegularFile)
        }

        let oversized = folder.appending(path: "oversized.txt")
        try Data().write(to: oversized)
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(NFDocumentImportPipeline.maximumImportSizeBytes + 1))
        try handle.close()
        do {
            _ = try await NFDocumentImportPipeline.copyIntoManagedStorage(
                from: oversized,
                managedStorageRootURL: managedRoot
            )
            XCTFail("Files above 50 MB must fail before copying")
        } catch {
            XCTAssertEqual(error as? NFDocumentImportValidationError, .fileTooLarge)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: managedRoot.path))
    }

    @MainActor
    private func makeStore() throws -> (AppStore, ModelContainer, URL) {
        let container = try ModelContainer(
            for: Schema(NFSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let documentRoot = FileManager.default.temporaryDirectory.appending(
            path: "NF-Import-Lifecycle-Documents-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        return (
            AppStore(
                context: container.mainContext,
                documentStorageRootURL: documentRoot
            ),
            container,
            documentRoot
        )
    }
}

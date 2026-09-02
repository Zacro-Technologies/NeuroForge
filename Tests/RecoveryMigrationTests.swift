import Foundation
import SwiftData
import XCTest

@testable import NeuroForge

final class RecoveryMigrationTests: XCTestCase {
    func testReleaseSchemaIsExplicitlyVersioned() {
        XCTAssertEqual(NFSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(NFSchemaMigrationPlan.schemas.count, 1)
        XCTAssertTrue(NFSchemaMigrationPlan.stages.isEmpty)
        XCTAssertGreaterThanOrEqual(NFSchemaV1.models.count, 9)
    }

    @MainActor
    func testDurableAndDisposableModelsUseDisjointSwiftDataConfigurations() throws {
        let durableNames = Set(NFPersistentStoreLocation.durableModels.map { String(reflecting: $0) })
        let localNames = Set(NFPersistentStoreLocation.localOnlyModels.map { String(reflecting: $0) })
        XCTAssertTrue(durableNames.isDisjoint(with: localNames))
        XCTAssertEqual(durableNames.union(localNames).count, NFSchemaV1.models.count)
        XCTAssertTrue(durableNames.contains { $0.contains("AttemptRecord") })
        XCTAssertTrue(durableNames.contains { $0.contains("ProgressAnnotationRecord") })
        XCTAssertTrue(localNames.contains { $0.contains("AIGenerationRecord") })
        XCTAssertTrue(durableNames.contains { $0.contains("DailyPlanRecord") })
        XCTAssertTrue(localNames.contains { $0.contains("SourceDocumentRecord") })
        XCTAssertFalse(durableNames.contains { $0.contains("SourceDocumentRecord") })
        XCTAssertTrue(localNames.contains { $0.contains("SourceChunkRecord") })

        let configurations = try NFPersistentStoreLocation.configurations(inMemory: true)
        XCTAssertEqual(configurations.count, 2)
        XCTAssertEqual(Set(configurations.map(\.name)), ["NeuroForgeDurable", "NeuroForgeLocalOnly"])
        XCTAssertTrue(configurations.allSatisfy(\.isStoredInMemoryOnly))

        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NFSchemaMigrationPlan.self,
            configurations: configurations
        )
        container.mainContext.insert(AttemptRecord(
            sessionID: UUID(),
            lab: .mentalMath,
            itemID: "durable-partition-test",
            prompt: "1 + 1",
            response: "2",
            correctAnswer: "2",
            isCorrect: true,
            confidence: .certain
        ))
        container.mainContext.insert(InputCalibrationRecord(
            profileID: UUID(),
            preferredAnswerMode: .keyboard,
            keyboardLatencyMilliseconds: 80,
            touchLatencyMilliseconds: nil,
            pencilLatencyMilliseconds: nil
        ))
        try container.mainContext.save()
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<AttemptRecord>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<InputCalibrationRecord>()), 1)
    }

    func testRecoveryPackageCopiesStoreAndSidecarsWithoutMutatingOriginals() throws {
        let sourceFolder = FileManager.default.temporaryDirectory
            .appending(path: "NF-Recovery-Test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceFolder) }
        let recoveryRoot = sourceFolder.appending(path: "recovery", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: recoveryRoot, withIntermediateDirectories: true)
        let storeURL = sourceFolder.appending(path: "default.store")
        let storeData = Data("private-store".utf8)
        let walData = Data("private-wal".utf8)
        try storeData.write(to: storeURL)
        try walData.write(to: URL(fileURLWithPath: storeURL.path + "-wal"))

        let package = NFStoreRecoveryService.preparePackage(
            storeURL: storeURL,
            openingError: RecoveryTestError.couldNotOpen,
            recoveryRootURL: recoveryRoot
        )

        XCTAssertEqual(try Data(contentsOf: storeURL), storeData)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: storeURL.path + "-wal")), walData)
        let copiedStore = try XCTUnwrap(package.artifactURLs.first { $0.lastPathComponent == "default.store" })
        let copiedWAL = try XCTUnwrap(package.artifactURLs.first { $0.lastPathComponent == "default.store-wal" })
        XCTAssertEqual(try Data(contentsOf: copiedStore), storeData)
        XCTAssertEqual(try Data(contentsOf: copiedWAL), walData)
        XCTAssertTrue(package.artifactURLs.contains { $0.lastPathComponent == "Recovery-Read-Me.txt" })
    }

    func testRepeatedRecoveryRotatesOneProtectedPackageInsteadOfAccumulatingPrivateCopies() throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appending(path: "NF-Recovery-Lifecycle-\(UUID().uuidString)", directoryHint: .isDirectory)
        let sourceFolder = testRoot.appending(path: "source", directoryHint: .isDirectory)
        let recoveryRoot = testRoot.appending(path: "recovery", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recoveryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        // Simulate a prerelease package that used a unique suffix.
        let superseded = recoveryRoot.appending(
            path: "\(NFStoreRecoveryService.packageFolderName)-superseded",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: superseded, withIntermediateDirectories: true)
        try Data("old-private-copy".utf8).write(to: superseded.appending(path: "default.store"))

        let storeURL = sourceFolder.appending(path: "default.store")
        try Data("first-private-store".utf8).write(to: storeURL)
        let first = NFStoreRecoveryService.preparePackage(
            storeURL: storeURL,
            openingError: RecoveryTestError.couldNotOpen,
            recoveryRootURL: recoveryRoot
        )
        XCTAssertEqual(recoveryPackageFolders(in: recoveryRoot).count, 1)

        try Data("second-private-store".utf8).write(to: storeURL, options: .atomic)
        let second = NFStoreRecoveryService.preparePackage(
            storeURL: storeURL,
            openingError: RecoveryTestError.couldNotOpen,
            recoveryRootURL: recoveryRoot
        )

        let recoveryFolders = recoveryPackageFolders(in: recoveryRoot)
        XCTAssertEqual(recoveryFolders.map(\.lastPathComponent), [NFStoreRecoveryService.packageFolderName])
        XCTAssertEqual(first.artifactURLs.first?.deletingLastPathComponent(), second.artifactURLs.first?.deletingLastPathComponent())
        let copiedStore = try XCTUnwrap(second.artifactURLs.first { $0.lastPathComponent == "default.store" })
        XCTAssertEqual(try Data(contentsOf: copiedStore), Data("second-private-store".utf8))
        XCTAssertEqual(try Data(contentsOf: storeURL), Data("second-private-store".utf8))

        #if os(macOS) || os(Linux)
        let permissions = try FileManager.default.attributesOfItem(atPath: copiedStore.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        #endif
    }

    private func recoveryPackageFolders(in root: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(NFStoreRecoveryService.packageFolderName) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private enum RecoveryTestError: Error { case couldNotOpen }
}

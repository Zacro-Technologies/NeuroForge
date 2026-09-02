import Foundation
import UniformTypeIdentifiers

enum NFDocumentImportTypeRegistry {
    static let imageFilenameExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp"
    ]
    static let supportedFilenameExtensions = NFSemanticSourceParser.supportedFilenameExtensions
        .union(["pdf"])
        .union(imageFilenameExtensions)

    static func supports(filename: String) -> Bool {
        supportedFilenameExtensions.contains(
            URL(fileURLWithPath: filename).pathExtension.lowercased()
        )
    }

    static func isImage(filename: String) -> Bool {
        imageFilenameExtensions.contains(
            URL(fileURLWithPath: filename).pathExtension.lowercased()
        )
    }

    static var contentTypes: [UTType] {
        var seenIdentifiers: Set<String> = []
        return supportedFilenameExtensions
            .sorted()
            .compactMap { UTType(filenameExtension: $0) }
            .filter { seenIdentifiers.insert($0.identifier).inserted }
    }
}

enum NFDocumentImportValidationError: Error, LocalizedError, Equatable {
    case notRegularFile
    case unsupportedType
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .notRegularFile:
            NFAppLocalization.localized(
                "Choose a regular file rather than a folder, package, or link.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Study-material import validation error."
            )
        case .unsupportedType:
            NFAppLocalization.localized(
                "This file type is not supported for local import.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Study-material import validation error."
            )
        case .fileTooLarge:
            NFAppLocalization.localized(
                "This file is larger than the 50 MB local import limit.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Study-material import validation error. MB means megabytes."
            )
        }
    }
}

enum NFDocumentImportStage: String, Sendable {
    case copying
    case extracting
    case saving
    case complete

    var title: String {
        switch self {
        case .copying: NFAppLocalization.localized("Copying into private app storage", locale: NFAppLocalization.preferredLocale, comment: "Document-import progress stage.")
        case .extracting: NFAppLocalization.localized("Extracting and chunking locally", locale: NFAppLocalization.preferredLocale, comment: "Document-import progress stage.")
        case .saving: NFAppLocalization.localized("Saving the local index", locale: NFAppLocalization.preferredLocale, comment: "Document-import progress stage.")
        case .complete: NFAppLocalization.localized("Import complete", locale: NFAppLocalization.preferredLocale, comment: "Document-import completion stage.")
        }
    }
}

struct NFManagedDocumentCopy: Sendable {
    let documentID: UUID
    let filename: String
    let typeIdentifier: String
    let sizeBytes: Int64
    let destinationURL: URL
}

struct NFPreparedSyncedDocumentCopy: Sendable {
    let copy: NFManagedDocumentCopy
    let createdDestination: Bool
}

struct NFSyncedDocumentFileInspection: Sendable {
    let localContentHash: String?
}

enum NFDocumentImportPipeline {
    static let maximumImportSizeBytes: Int64 = 50 * 1_024 * 1_024

    static func copyIntoManagedStorage(
        from sourceURL: URL,
        managedStorageRootURL: URL? = nil
    ) async throws -> NFManagedDocumentCopy {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
            }

            let fileManager = FileManager.default
            let values = try validateImportFile(
                at: sourceURL,
                filename: sourceURL.lastPathComponent
            )
            let folder: URL
            if let managedStorageRootURL {
                folder = managedStorageRootURL.standardizedFileURL
            } else {
                let support = try fileManager.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                folder = support
                    .appending(path: "NeuroForge/Documents", directoryHint: .isDirectory)
                    .standardizedFileURL
            }
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let filename = boundedDisplayFilename(for: sourceURL)
            let documentID = UUID()
            let destination = folder.appending(
                path: "\(documentID.uuidString)-\(filename)",
                directoryHint: .notDirectory
            )
            do {
                try fileManager.copyItem(at: sourceURL, to: destination)
                let copiedValues = try validateImportFile(
                    at: destination,
                    filename: filename
                )
                try Task.checkCancellation()
                return NFManagedDocumentCopy(
                    documentID: documentID,
                    filename: filename,
                    typeIdentifier: values.contentType?.identifier ?? "public.data",
                    sizeBytes: Int64(copiedValues.fileSize ?? values.fileSize ?? 0),
                    destinationURL: destination
                )
            } catch {
                try? fileManager.removeItem(at: destination)
                throw error
            }
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func extract(
        _ copy: NFManagedDocumentCopy,
        csvSelection: NFCSVColumnSelection? = nil
    ) async throws -> NFSourceExtraction {
        _ = try validateImportFile(at: copy.destinationURL, filename: copy.filename)
        if NFDocumentImportTypeRegistry.isImage(filename: copy.filename) {
            return try await NFOCRService.recognizeImage(
                documentID: copy.documentID,
                sourceName: copy.filename,
                url: copy.destinationURL
            )
        }
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let extraction = try NFSourceExtractor.extract(
                documentID: copy.documentID,
                sourceName: copy.filename,
                url: copy.destinationURL,
                csvSelection: csvSelection
            )
            try Task.checkCancellation()
            return extraction
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func csvPreview(_ copy: NFManagedDocumentCopy) async throws -> NFCSVSchemaPreview {
        _ = try validateImportFile(at: copy.destinationURL, filename: copy.filename)
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let preview = try NFSourceExtractor.csvPreview(url: copy.destinationURL)
            try Task.checkCancellation()
            return preview
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func inspectSyncedOriginal(
        remoteURL: URL,
        expectedContentHash: String,
        localURL: URL
    ) async throws -> NFSyncedDocumentFileInspection {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard try NFContentAddressedAssetHasher.sha256(
                fileURL: remoteURL,
                checkingCancellation: true
            ) == expectedContentHash else {
                throw NFDocumentAssetIntegrityError.contentHashMismatch
            }
            let localContentHash = try? NFContentAddressedAssetHasher.sha256(
                fileURL: localURL,
                checkingCancellation: true
            )
            try Task.checkCancellation()
            return NFSyncedDocumentFileInspection(localContentHash: localContentHash)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func copyVerifiedSyncedOriginal(
        from sourceURL: URL,
        expectedContentHash: String,
        managedStorageRootURL: URL,
        storageFilename: String,
        documentID: UUID,
        displayFilename: String,
        typeIdentifier: String,
        sizeBytes: Int64
    ) async throws -> NFPreparedSyncedDocumentCopy {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let fileManager = FileManager.default
            let root = managedStorageRootURL.standardizedFileURL
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

            let safeStorageFilename = URL(fileURLWithPath: storageFilename).lastPathComponent
            guard !safeStorageFilename.isEmpty else {
                throw NFDocumentAssetIntegrityError.unreadableFile
            }
            let destination = root.appending(
                path: safeStorageFilename,
                directoryHint: .notDirectory
            ).standardizedFileURL
            guard destination.deletingLastPathComponent() == root else {
                throw NFDocumentAssetIntegrityError.unreadableFile
            }

            let temporary = root.appending(
                path: ".pending-synced-copy-\(UUID().uuidString)",
                directoryHint: .notDirectory
            )
            var createdDestination = false
            do {
                guard try NFContentAddressedAssetHasher.sha256(
                    fileURL: sourceURL,
                    checkingCancellation: true
                ) == expectedContentHash else {
                    throw NFDocumentAssetIntegrityError.contentHashMismatch
                }

                if fileManager.fileExists(atPath: destination.path) {
                    guard try NFContentAddressedAssetHasher.sha256(
                        fileURL: destination,
                        checkingCancellation: true
                    ) == expectedContentHash else {
                        throw NFDocumentAssetIntegrityError.contentHashMismatch
                    }
                } else {
                    try fileManager.copyItem(at: sourceURL, to: temporary)
                    guard try NFContentAddressedAssetHasher.sha256(
                        fileURL: temporary,
                        checkingCancellation: true
                    ) == expectedContentHash else {
                        throw NFDocumentAssetIntegrityError.contentHashMismatch
                    }
                    try Task.checkCancellation()
                    do {
                        try fileManager.moveItem(at: temporary, to: destination)
                        createdDestination = true
                    } catch {
                        guard fileManager.fileExists(atPath: destination.path),
                              try NFContentAddressedAssetHasher.sha256(
                                fileURL: destination,
                                checkingCancellation: true
                              ) == expectedContentHash else {
                            throw error
                        }
                        try? fileManager.removeItem(at: temporary)
                    }
                }

                try Task.checkCancellation()
                return NFPreparedSyncedDocumentCopy(
                    copy: NFManagedDocumentCopy(
                        documentID: documentID,
                        filename: displayFilename,
                        typeIdentifier: typeIdentifier,
                        sizeBytes: sizeBytes,
                        destinationURL: destination
                    ),
                    createdDestination: createdDestination
                )
            } catch {
                try? fileManager.removeItem(at: temporary)
                if createdDestination { try? fileManager.removeItem(at: destination) }
                throw error
            }
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func removeManagedFile(
        at fileURL: URL,
        managedStorageRootURL: URL
    ) async {
        await Task.detached(priority: .utility) {
            let root = managedStorageRootURL.standardizedFileURL
            let candidate = fileURL.standardizedFileURL
            guard candidate.deletingLastPathComponent() == root else { return }
            try? FileManager.default.removeItem(at: candidate)
        }.value
    }

    static func removeManagedCopy(_ copy: NFManagedDocumentCopy) {
        try? FileManager.default.removeItem(at: copy.destinationURL)
    }

    private static func validateImportFile(
        at url: URL,
        filename: String
    ) throws -> URLResourceValues {
        guard NFDocumentImportTypeRegistry.supports(filename: filename) else {
            throw NFDocumentImportValidationError.unsupportedType
        }
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentTypeKey
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw NFDocumentImportValidationError.notRegularFile
        }
        guard let fileSize = values.fileSize,
              Int64(fileSize) <= maximumImportSizeBytes else {
            throw NFDocumentImportValidationError.fileTooLarge
        }
        return values
    }

    private static func boundedDisplayFilename(for sourceURL: URL) -> String {
        let sourceFilename = URL(fileURLWithPath: sourceURL.lastPathComponent).lastPathComponent
        guard !sourceFilename.isEmpty else {
            return NFAppLocalization.localized(
                "Imported Document",
                locale: NFAppLocalization.preferredLocale,
                comment: "Fallback filename for a study-material import."
            )
        }
        guard sourceFilename.count > 180 else { return sourceFilename }

        let pathExtension = sourceURL.pathExtension
        guard !pathExtension.isEmpty else { return String(sourceFilename.prefix(180)) }
        let suffix = ".\(pathExtension)"
        let stemLength = max(1, 180 - suffix.count)
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        return "\(stem.prefix(stemLength))\(suffix)"
    }
}

import CryptoKit
import Foundation
import Darwin

struct NFAILearningArtifactFile: Codable, Equatable, Sendable {
    let relativePath: String
    let bytes: Data
    let digest: String

    init(relativePath: String, bytes: Data) {
        self.relativePath = relativePath
        self.bytes = bytes
        self.digest = NFAILearningArtifactArchive.digest(bytes)
    }
}

/// Portable copies contain exact learning artifacts, never provider credentials
/// or lock files. The restore journal owns publication and rollback.
enum NFAILearningArtifactArchive {
    enum Failure: Error, LocalizedError {
        case unsupported, invalidArtifact, oversized, ioFailure, unsafePath
        var errorDescription: String? {
            switch self {
            case .unsupported: "Saved AI learning data needs a compatible version of NeuroForge."
            case .invalidArtifact: "Saved AI learning data could not be verified. The original files have been kept."
            case .oversized: "The AI learning archive exceeds the supported restore size. No saved explanations were removed."
            case .ioFailure: "AI learning files could not be read or updated. Try again."
            case .unsafePath: "The AI learning archive contains an unsupported file path."
            }
        }
    }

    static let maximumFiles = 2_048
    static let maximumBytes = 8 * 1_024 * 1_024
    static let maximumFileBytes = 2 * 1_024 * 1_024

    struct Location: Equatable, Sendable {
        let domain: NFRestoreJournalFileOperation.Domain
        let filename: String
        let operationID: String
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func location(for relativePath: String) throws -> Location {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { throw Failure.unsafePath }
        let name = parts[1]
        if parts[0] == "Tutor", name.hasSuffix(".json") {
            let key = String(name.dropLast(5))
            guard key.count == 64, key == key.lowercased(), key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw Failure.unsafePath }
            return .init(domain: .aiTutor, filename: name, operationID: "ai-tutor-" + key)
        }
        if parts[0] == "Grading", name.hasPrefix("grade-"), name.hasSuffix(".json") {
            let key = String(name.dropFirst(6).dropLast(5))
            guard let id = UUID(uuidString: key), id.uuidString.lowercased() == key else { throw Failure.unsafePath }
            return .init(domain: .aiGrading, filename: name, operationID: "ai-grading-" + key)
        }
        throw Failure.unsafePath
    }

    static func validate(_ files: [NFAILearningArtifactFile]) throws {
        guard files.count <= maximumFiles else { throw Failure.oversized }
        guard Set(files.map(\.relativePath)).count == files.count else { throw Failure.invalidArtifact }
        var total = 0
        for file in files {
            guard file.bytes.count <= maximumFileBytes, total <= maximumBytes - file.bytes.count else { throw Failure.oversized }
            total += file.bytes.count
            try validate(file)
        }
    }

    static func decodeEntries(_ object: Any) throws -> [NFAILearningArtifactFile] {
        guard let rows = object as? [[String: Any]], rows.count <= maximumFiles,
              rows.allSatisfy({ Set($0.keys) == Set(["relativePath", "bytes", "digest"]) }) else { throw Failure.unsupported }
        let values = try JSONDecoder().decode([NFAILearningArtifactFile].self,
            from: JSONSerialization.data(withJSONObject: rows))
        try validate(values)
        return values
    }

    static func validateArchiveVersion(_ object: [String: Any]) throws {
        guard let version = object["archiveVersion"] as? Int, version < 19 else { return }
        func containsAIFields(_ value: Any, depth: Int = 0) throws -> Bool {
            guard depth <= 48 else { throw Failure.oversized }
            if let object = value as? [String: Any] {
                for (key, child) in object {
                    if ["aiRubric", "aiGrade", "aiGradingRequest", "aiGradeReviews", "aiLearningArtifacts"].contains(key),
                       !(child is NSNull), (child as? [Any])?.isEmpty != true { return true }
                    if key == "payload", let encoded = child as? String,
                       encoded.utf8.count <= maximumBytes * 2, let bytes = Data(base64Encoded: encoded),
                       bytes.count <= maximumBytes, let decoded = try? JSONSerialization.jsonObject(with: bytes),
                       try containsAIFields(decoded, depth: depth + 1) { return true }
                    if try containsAIFields(child, depth: depth + 1) { return true }
                }
            } else if let values = value as? [Any] {
                for child in values {
                    if try containsAIFields(child, depth: depth + 1) { return true }
                }
            }
            return false
        }
        if try containsAIFields(object) { throw Failure.unsupported }
    }

    static func validate(_ file: NFAILearningArtifactFile) throws {
        let location = try location(for: file.relativePath)
        guard file.bytes.count <= maximumFileBytes, file.digest == digest(file.bytes) else { throw Failure.invalidArtifact }
        let known: Data
        do {
            switch location.domain {
            case .aiTutor:
                let transcript = try JSONDecoder().decode(NFAITutorTranscript.self, from: file.bytes)
                guard transcript.isValid, location.filename == transcript.contextKey + ".json" else { throw Failure.invalidArtifact }
                known = try JSONEncoder().encode(transcript)
            case .aiGrading:
                let job = try JSONDecoder().decode(NFAIGradingJob.self, from: file.bytes)
                try NFAIGradingJobStore.validate(job)
                guard location.filename == "grade-\(job.id.uuidString.lowercased()).json" else { throw Failure.invalidArtifact }
                known = try JSONEncoder().encode(job)
            default: throw Failure.unsafePath
            }
        } catch let error as Failure { throw error }
        catch { throw Failure.unsupported }
        guard try knownFields(JSONSerialization.jsonObject(with: file.bytes), JSONSerialization.jsonObject(with: known)) else {
            throw Failure.unsupported
        }
    }

    static func capture(at artifactDirectoryURL: URL?) throws -> [NFAILearningArtifactFile] {
        guard let root = artifactDirectoryURL else { return [] }
        guard root.isFileURL else { throw Failure.unsafePath }
        var info = stat()
        if lstat(root.path, &info) != 0 {
            if errno == ENOENT { return [] }
            throw Failure.ioFailure
        }
        guard info.st_mode & S_IFMT == S_IFDIR else { throw Failure.unsafePath }
        var result: [NFAILearningArtifactFile] = []
        for child in try entries(root) {
            if child.lastPathComponent == ".DS_Store" { continue }
            guard ["Tutor", "Grading"].contains(child.lastPathComponent) else { throw Failure.unsupported }
            result += try captureDirectory(child, folder: child.lastPathComponent)
        }
        try validate(result)
        return result.sorted { $0.relativePath < $1.relativePath }
    }

    static func captureDirectory(_ directory: URL, folder: String) throws -> [NFAILearningArtifactFile] {
        guard ["Tutor", "Grading"].contains(folder) else { throw Failure.unsafePath }
        var values: [NFAILearningArtifactFile] = []
        for file in try entries(directory) {
            let name = file.lastPathComponent
            if name == ".DS_Store" { continue }
            if folder == "Grading", name.hasSuffix(".json.lock"),
               (try? location(for: "Grading/" + String(name.dropLast(5)))) != nil { continue }
            if folder == "Grading", name.hasPrefix(".grade-"), name.hasSuffix(".tmp"),
               UUID(uuidString: String(name.dropFirst(7).dropLast(4))) != nil { continue }
            if isRestoreTemporary(name, folder: folder) { continue }
            let path = folder + "/" + name
            _ = try location(for: path)
            values.append(.init(relativePath: path, bytes: try read(file)))
        }
        try validate(values)
        return values.sorted { $0.relativePath < $1.relativePath }
    }

    private static func isRestoreTemporary(_ name: String, folder: String) -> Bool {
        guard name.hasPrefix(".restore-domain-"), name.hasSuffix(".tmp") else { return false }
        let body = String(name.dropFirst(16).dropLast(4))
        guard body.count > 37, UUID(uuidString: String(body.prefix(36))) != nil,
              body.dropFirst(36).first == "-" else { return false }
        let operation = String(body.dropFirst(37))
        let filename: String
        if folder == "Tutor", operation.hasPrefix("ai-tutor-") {
            filename = String(operation.dropFirst(9)) + ".json"
        } else if folder == "Grading", operation.hasPrefix("ai-grading-") {
            filename = "grade-" + String(operation.dropFirst(11)) + ".json"
        } else { return false }
        return (try? location(for: folder + "/" + filename))?.operationID == operation
    }

    /// Only the existing explicit local-data erase calls this method. Invalid
    /// content still gets erased; no export or ordinary read invokes deletion.
    static func removeAll(at artifactDirectoryURL: URL?) throws {
        guard let root = artifactDirectoryURL else { return }
        guard root.isFileURL, root.lastPathComponent == "AILearning" else { throw Failure.unsafePath }
        var info = stat()
        if lstat(root.path, &info) != 0 {
            if errno == ENOENT { return }
            throw Failure.ioFailure
        }
        guard info.st_mode & S_IFMT == S_IFDIR else { throw Failure.unsafePath }
        try FileManager.default.removeItem(at: root)
        guard lstat(root.path, &info) != 0, errno == ENOENT else { throw Failure.ioFailure }
    }

    struct Selection {
        let operations: [NFRestoreJournalFileOperation]
        let restored: Int
        let skipped: Int
    }

    static func operations(existing: [NFAILearningArtifactFile], incoming: [NFAILearningArtifactFile],
                           policy: NFDataArchiveRestorePolicy) throws -> Selection {
        try validate(existing); try validate(incoming)
        let old = Dictionary(uniqueKeysWithValues: existing.map { ($0.relativePath, $0) })
        let new = Dictionary(uniqueKeysWithValues: incoming.map { ($0.relativePath, $0) })
        let overlap = Set(old.keys).intersection(new.keys)
        let conflicts = overlap.filter { old[$0] != new[$0] }
        if policy == .abortOnConflict, !conflicts.isEmpty {
            throw NFDataArchiveRestoreError.conflictsRequireDecision(conflicts.count)
        }
        let selected: [String: NFAILearningArtifactFile]
        switch policy {
        case .replaceAll: selected = new
        case .replaceMatching: selected = old.merging(new) { _, incoming in incoming }
        case .keepExisting, .abortOnConflict: selected = old.merging(new) { existing, _ in existing }
        }
        try validate(Array(selected.values))
        let paths = Set(old.keys).union(selected.keys).sorted()
        let operations = try paths.map { path in
            let location = try location(for: path)
            return NFRestoreJournalFileOperation(id: location.operationID, domain: location.domain,
                relativePath: location.filename, before: old[path]?.bytes, after: selected[path]?.bytes)
        }
        let skipped = policy == .keepExisting ? overlap.count : 0
        return .init(operations: operations, restored: incoming.count - skipped, skipped: skipped)
    }

    static func files(from operations: [NFRestoreJournalFileOperation], before: Bool) throws -> [NFAILearningArtifactFile] {
        let files = try operations.compactMap { operation -> NFAILearningArtifactFile? in
            let folder: String
            switch operation.domain {
            case .aiTutor: folder = "Tutor"
            case .aiGrading: folder = "Grading"
            default: return nil
            }
            let path = folder + "/" + operation.relativePath
            let location = try location(for: path)
            guard location.operationID == operation.id else { throw Failure.unsafePath }
            guard let bytes = before ? operation.before : operation.after else { return nil }
            return .init(relativePath: path, bytes: bytes)
        }
        try validate(files)
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private static func knownFields(_ original: Any, _ known: Any) -> Bool {
        if let object = original as? [String: Any], let reference = known as? [String: Any] {
            return object.allSatisfy { key, value in
                guard let expected = reference[key] else { return value is NSNull }
                return knownFields(value, expected)
            }
        }
        if let values = original as? [Any], let reference = known as? [Any] {
            return values.count == reference.count && zip(values, reference).allSatisfy { knownFields($0.0, $0.1) }
        }
        return true
    }

    private static func entries(_ directoryURL: URL) throws -> [URL] {
        let fd = Darwin.open(directoryURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0, let directory = fdopendir(fd) else { if fd >= 0 { Darwin.close(fd) }; throw Failure.unsafePath }
        defer { closedir(directory) }
        var result: [URL] = []
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw Failure.ioFailure }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(validatingCString: $0) }
            }
            guard let name else { throw Failure.unsafePath }
            if name == "." || name == ".." { continue }
            guard result.count < maximumFiles * 3 + 4 else { throw Failure.oversized }
            result.append(directoryURL.appendingPathComponent(name))
        }
        return result
    }

    private static func read(_ url: URL) throws -> Data {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.ioFailure }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { throw Failure.unsafePath }
        guard info.st_size >= 0, info.st_size <= maximumFileBytes else { throw Failure.oversized }
        let data = try handle.read(upToCount: maximumFileBytes + 1) ?? Data()
        guard data.count == info.st_size, data.count <= maximumFileBytes else { throw Failure.oversized }
        return data
    }
}

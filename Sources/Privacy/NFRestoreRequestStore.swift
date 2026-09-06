import Foundation
import Darwin

/// A private request to compile after a genuine process restart. These bytes
/// grant no database or file mutation authority; only an accepted journal plan
/// compiled against the exact reviewed destination can do that.
struct NFRestoreRestartRequest: Codable, Equatable, Sendable {
    let version: Int
    let transactionID: UUID
    let namespace: String
    let installationOwnerID: UUID
    let sourceDigest: String
    let sourceByteCount: Int
    let sourceFilename: String
    let permittedPayload: Data
    let permittedPayloadDigest: String
    let reviewedDestinationDigest: String
    let policyRaw: String
    let localeIdentifier: String
    let compiledAtReferenceSeconds: Double

    func validate() throws {
        guard version == 1 else { throw NFRestoreJournalError.unsupportedVersion }
        guard NFRestoreJournalCodec.isDigest(namespace),
              NFRestoreJournalCodec.isDigest(sourceDigest),
              NFRestoreJournalCodec.isDigest(reviewedDestinationDigest),
              NFRestoreJournalCodec.digest(permittedPayload) == permittedPayloadDigest,
              (0...NFRestoreRequestStore.maximumPayloadBytes).contains(sourceByteCount),
              !permittedPayload.isEmpty, permittedPayload.count <= NFRestoreRequestStore.maximumPayloadBytes,
              sourceFilename.utf8.count <= 1_024, !sourceFilename.utf8.contains(0),
              !localeIdentifier.isEmpty, localeIdentifier.utf8.count <= 128, compiledAtReferenceSeconds.isFinite,
              NFDataArchiveRestorePolicy(rawValue: policyRaw) != nil else {
            throw NFRestoreJournalError.malformed
        }
    }
}

struct NFRestoreRequestReceipt: Codable, Equatable, Sendable {
    enum Resolution: String, Codable, Sendable { case cancelled, completed }
    let version: Int
    let transactionID: UUID
    let namespace: String
    let installationOwnerID: UUID
    let requestDigest: String
    let resolution: Resolution
    let acceptedPlanDigest: String?
    let counts: [String: Int]

    func validate() throws {
        guard version == 1 else { throw NFRestoreJournalError.unsupportedVersion }
        guard NFRestoreJournalCodec.isDigest(namespace), NFRestoreJournalCodec.isDigest(requestDigest),
              counts.count <= 64, counts.keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }),
              counts.values.allSatisfy({ $0 >= 0 }),
              resolution == .completed
                ? acceptedPlanDigest.map(NFRestoreJournalCodec.isDigest) == true
                : acceptedPlanDigest == nil && counts.isEmpty else { throw NFRestoreJournalError.malformed }
        var total = 0
        for count in counts.values {
            let sum = total.addingReportingOverflow(count)
            guard !sum.overflow else { throw NFRestoreJournalError.malformed }
            total = sum.partialValue
        }
    }
}

struct NFRestoreRequestInspection: Equatable, Sendable {
    let transactionID: UUID
    let namespace: String
    let installationOwnerID: UUID
    let receipt: NFRestoreRequestReceipt?
    let cleanupRequired: Bool
    let completionAcknowledged: Bool
}

/// All mutations retain the process-lifetime store lease. A separate advisory
/// lock serializes independently constructed actors within the same process.
/// A receipt is published and synced before payload cleanup. Its retained ID
/// prevents a delayed stage call from resurrecting a cancelled/completed request.
actor NFRestoreRequestStore {
    static let folderName = "NeuroForge/RestoreRequests"
    static let maximumPayloadBytes = 64 * 1_024 * 1_024
    static let maximumRequestBytes = 90 * 1_024 * 1_024
    private static let maximumReceiptBytes = 32 * 1_024
    enum Boundary: CaseIterable, Sendable {
        case beforeRequestWrite, afterRequestWrite, beforeRequestPublish, afterRequestPublish
        case beforeReceiptPublish, afterReceiptPublish, beforePayloadCleanup, afterPayloadCleanup
    }
    private let root: URL
    private let lease: NFApplicationStoreLease
    private let fault: @Sendable (Boundary) throws -> Void
    private var sealed = false

    init(root: URL, lease: NFApplicationStoreLease,
         fault: @escaping @Sendable (Boundary) throws -> Void = { _ in }) {
        self.root = root; self.lease = lease; self.fault = fault
    }

    static func root(applicationSupportURL: URL) -> URL {
        applicationSupportURL.appending(path: folderName, directoryHint: .isDirectory)
    }

    /// A deletion or account transition seals the old producer before any
    /// asynchronous caller can publish a new request using its stale identity.
    func seal() { sealed = true }

    func inspectAll() throws -> [NFRestoreRequestInspection] {
        guard exists(root) else { return [] }
        return try withLock { fd in try inspect(fd: fd) }
    }

    func stage(_ request: NFRestoreRestartRequest) throws {
        guard !sealed else { throw NFRestoreJournalError.invalidated }
        try request.validate()
        let bytes = try NFRestoreJournalCodec.encode(request, maximumBytes: Self.maximumRequestBytes)
        try withLock { fd in
            let entries = try inspect(fd: fd)
            guard !entries.contains(where: { $0.receipt == nil && $0.transactionID != request.transactionID }) else {
                throw NFRestoreJournalError.conflictingPlan
            }
            if let old = entries.first(where: { $0.transactionID == request.transactionID }) {
                guard old.namespace == request.namespace, old.installationOwnerID == request.installationOwnerID,
                      old.receipt == nil else { throw NFRestoreJournalError.invalidated }
                guard try read(name(request.transactionID, "request"), fd: fd, limit: Self.maximumRequestBytes) == bytes else {
                    throw NFRestoreJournalError.conflictingPlan
                }
                return
            }
            guard entries.count < 32 else { throw NFRestoreJournalError.tooManyTransactions }
            try fault(.beforeRequestWrite)
            try publish(bytes, name: name(request.transactionID, "request"), fd: fd,
                beforePublish: { try fault(.afterRequestWrite); try fault(.beforeRequestPublish) })
            try fault(.afterRequestPublish)
        }
    }

    func load(transactionID: UUID, namespace: String, owner: UUID) throws -> NFRestoreRestartRequest {
        try withLock { fd in
            if try read(name(transactionID, "receipt"), fd: fd, limit: Self.maximumReceiptBytes) != nil {
                throw NFRestoreJournalError.invalidated
            }
            let request = try request(transactionID, fd: fd)
            guard request.namespace == namespace, request.installationOwnerID == owner else {
                throw NFRestoreJournalError.conflictingPlan
            }
            return request
        }
    }

    func resolve(_ request: NFRestoreRestartRequest, resolution: NFRestoreRequestReceipt.Resolution,
                 acceptedPlanDigest: String? = nil, counts: [String: Int] = [:]) throws -> NFRestoreRequestReceipt {
        try request.validate()
        let requestBytes = try NFRestoreJournalCodec.encode(request, maximumBytes: Self.maximumRequestBytes)
        let receipt = NFRestoreRequestReceipt(version: 1, transactionID: request.transactionID,
            namespace: request.namespace, installationOwnerID: request.installationOwnerID,
            requestDigest: NFRestoreJournalCodec.digest(requestBytes), resolution: resolution,
            acceptedPlanDigest: acceptedPlanDigest, counts: counts)
        try receipt.validate()
        return try withLock { fd in
            let receiptName = name(request.transactionID, "receipt")
            let receiptBytes = try NFRestoreJournalCodec.encode(receipt, maximumBytes: Self.maximumReceiptBytes)
            if let prior = try read(receiptName, fd: fd, limit: Self.maximumReceiptBytes) {
                guard prior == receiptBytes else { throw NFRestoreJournalError.conflictingPlan }
            } else {
                guard try read(name(request.transactionID, "request"), fd: fd, limit: Self.maximumRequestBytes) == requestBytes else {
                    throw NFRestoreJournalError.conflictingPlan
                }
                try fault(.beforeReceiptPublish)
                try publish(receiptBytes, name: receiptName, fd: fd)
                try fault(.afterReceiptPublish)
            }
            try cleanup(request.transactionID, fd: fd)
            return receipt
        }
    }

    func finishReceiptCleanup(_ receipt: NFRestoreRequestReceipt) throws {
        try receipt.validate()
        try withLock { fd in
            guard try read(name(receipt.transactionID, "receipt"), fd: fd, limit: Self.maximumReceiptBytes)
                == NFRestoreJournalCodec.encode(receipt, maximumBytes: Self.maximumReceiptBytes) else {
                throw NFRestoreJournalError.conflictingPlan
            }
            try cleanup(receipt.transactionID, fd: fd)
        }
    }

    /// Acknowledgement is independent of recovery authority and payload cleanup.
    /// Until this receipt-bound marker is durable, a cold launch shows the same
    /// verified counts without applying the completed plan again.
    func acknowledgeCompletion(_ receipt: NFRestoreRequestReceipt) throws {
        try receipt.validate()
        guard receipt.resolution == .completed else { throw NFRestoreJournalError.conflictingPlan }
        try withLock { fd in
            let bytes = try NFRestoreJournalCodec.encode(receipt, maximumBytes: Self.maximumReceiptBytes)
            guard try read(name(receipt.transactionID, "receipt"), fd: fd, limit: Self.maximumReceiptBytes) == bytes else {
                throw NFRestoreJournalError.conflictingPlan
            }
            let acknowledgement = Data(NFRestoreJournalCodec.digest(bytes).utf8)
            let filename = name(receipt.transactionID, "ack")
            if let prior = try read(filename, fd: fd, limit: 64) {
                guard prior == acknowledgement else { throw NFRestoreJournalError.digestMismatch }
            } else { try publish(acknowledgement, name: filename, fd: fd) }
        }
    }

    private func cleanup(_ id: UUID, fd: Int32) throws {
        try fault(.beforePayloadCleanup)
        guard unlinkat(fd, name(id, "request"), 0) == 0 || errno == ENOENT else { throw NFRestoreJournalError.ioFailure }
        guard fsync(fd) == 0 else { throw NFRestoreJournalError.ioFailure }
        try fault(.afterPayloadCleanup)
    }

    private func name(_ id: UUID, _ suffix: String) -> String { id.uuidString.lowercased() + "." + suffix }
    private func request(_ id: UUID, fd: Int32) throws -> NFRestoreRestartRequest {
        guard let bytes = try read(name(id, "request"), fd: fd, limit: Self.maximumRequestBytes) else {
            throw NFRestoreJournalError.malformed
        }
        let value = try NFRestoreJournalCodec.decode(NFRestoreRestartRequest.self, bytes: bytes, maximumBytes: Self.maximumRequestBytes)
        try value.validate()
        guard value.transactionID == id else { throw NFRestoreJournalError.malformed }
        return value
    }

    private func inspect(fd: Int32) throws -> [NFRestoreRequestInspection] {
        guard let directory = fdopendir(dup(fd)) else { throw NFRestoreJournalError.ioFailure }
        defer { closedir(directory) }
        var ids = Set<UUID>(), payloadIDs = Set<UUID>(), receiptIDs = Set<UUID>(), acknowledgementIDs = Set<UUID>(), count = 0
        errno = 0
        while let entry = readdir(directory) {
            let filename = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if [".", "..", "requests.lock"].contains(filename) { continue }
            count += 1
            guard count <= 96 else { throw NFRestoreJournalError.tooManyTransactions }
            if filename.hasPrefix(".unpublished-"), filename.hasSuffix(".tmp") {
                let token = String(filename.dropFirst(".unpublished-".count).dropLast(".tmp".count))
                guard let id = UUID(uuidString: token), token == id.uuidString.lowercased() else {
                    throw NFRestoreJournalError.malformed
                }
                // The actor holds both the process lease and the publication
                // lock: no writer can still own these explicitly unaccepted
                // bytes. A published request/receipt has a different name.
                _ = try read(filename, fd: fd, limit: Self.maximumRequestBytes)
                guard unlinkat(fd, filename, 0) == 0, fsync(fd) == 0 else { throw NFRestoreJournalError.ioFailure }
                errno = 0
                continue
            }
            let parts = filename.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 2, let id = UUID(uuidString: String(parts[0])),
                  filename == name(id, String(parts[1])), ["request", "receipt", "ack"].contains(parts[1]) else {
                throw NFRestoreJournalError.malformed
            }
            ids.insert(id)
            if parts[1] == "request" { payloadIDs.insert(id) }
            else if parts[1] == "receipt" { receiptIDs.insert(id) }
            else { acknowledgementIDs.insert(id) }
            errno = 0
        }
        guard errno == 0, ids.count <= 32 else { throw NFRestoreJournalError.ioFailure }
        return try ids.sorted { $0.uuidString < $1.uuidString }.map { id in
            if receiptIDs.contains(id) {
                guard let bytes = try read(name(id, "receipt"), fd: fd, limit: Self.maximumReceiptBytes) else {
                    throw NFRestoreJournalError.malformed
                }
                let receipt = try NFRestoreJournalCodec.decode(NFRestoreRequestReceipt.self, bytes: bytes, maximumBytes: Self.maximumReceiptBytes)
                try receipt.validate()
                guard receipt.transactionID == id else { throw NFRestoreJournalError.malformed }
                if acknowledgementIDs.contains(id) {
                    guard receipt.resolution == .completed,
                          try read(name(id, "ack"), fd: fd, limit: 64) == Data(NFRestoreJournalCodec.digest(bytes).utf8) else {
                        throw NFRestoreJournalError.digestMismatch
                    }
                }
                if payloadIDs.contains(id) {
                    let original = try request(id, fd: fd)
                    guard original.namespace == receipt.namespace, original.installationOwnerID == receipt.installationOwnerID,
                          NFRestoreJournalCodec.digest(try NFRestoreJournalCodec.encode(original, maximumBytes: Self.maximumRequestBytes)) == receipt.requestDigest else {
                        throw NFRestoreJournalError.digestMismatch
                    }
                }
                return .init(transactionID: id, namespace: receipt.namespace, installationOwnerID: receipt.installationOwnerID,
                    receipt: receipt, cleanupRequired: payloadIDs.contains(id), completionAcknowledged: acknowledgementIDs.contains(id))
            }
            guard !acknowledgementIDs.contains(id) else { throw NFRestoreJournalError.malformed }
            let value = try request(id, fd: fd)
            return .init(transactionID: id, namespace: value.namespace, installationOwnerID: value.installationOwnerID,
                receipt: nil, cleanupRequired: false, completionAcknowledged: false)
        }
    }

    private func exists(_ url: URL) -> Bool { var metadata = stat(); return lstat(url.path, &metadata) == 0 || errno != ENOENT }
    private func withLock<T>(_ body: (Int32) throws -> T) throws -> T {
        _ = lease
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw NFRestoreJournalError.ioFailure }
        defer { Darwin.close(fd) }
        guard fchmod(fd, 0o700) == 0 else { throw NFRestoreJournalError.ioFailure }
        let lock = openat(fd, "requests.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard lock >= 0 else { throw NFRestoreJournalError.ioFailure }
        defer { Darwin.close(lock) }
        var metadata = stat()
        guard fstat(lock, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG, metadata.st_nlink == 1,
              fchmod(lock, 0o600) == 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw NFRestoreJournalError.ioFailure }
        defer { flock(lock, LOCK_UN) }
        return try body(fd)
    }

    private func read(_ name: String, fd: Int32, limit: Int) throws -> Data? {
        let file = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard file >= 0 else {
            if errno == ENOENT { return nil }
            throw NFRestoreJournalError.ioFailure
        }
        defer { Darwin.close(file) }
        var metadata = stat()
        guard fstat(file, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_nlink == 1, metadata.st_size >= 0, metadata.st_size <= limit else {
            throw NFRestoreJournalError.malformed
        }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = Darwin.read(file, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw NFRestoreJournalError.ioFailure }
            if count == 0 { break }
            guard count <= limit - data.count else { throw NFRestoreJournalError.oversized }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    private func publish(_ bytes: Data, name: String, fd: Int32, beforePublish: () throws -> Void = {}) throws {
        let temporary = ".unpublished-" + UUID().uuidString.lowercased() + ".tmp"
        let file = openat(fd, temporary, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard file >= 0 else { throw NFRestoreJournalError.ioFailure }
        defer { Darwin.close(file) }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: root.appendingPathComponent(temporary).path)
        #endif
        var published = false
        defer { if !published { _ = unlinkat(fd, temporary, 0) } }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(file, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw NFRestoreJournalError.ioFailure }
                offset += count
            }
        }
        guard fsync(file) == 0 else { throw NFRestoreJournalError.ioFailure }
        guard try read(temporary, fd: fd, limit: bytes.count) == bytes else { throw NFRestoreJournalError.digestMismatch }
        try beforePublish()
        guard renameat(fd, temporary, fd, name) == 0 else { throw NFRestoreJournalError.ioFailure }
        published = true
        guard fsync(fd) == 0 else { throw NFRestoreJournalError.ioFailure }
    }
}

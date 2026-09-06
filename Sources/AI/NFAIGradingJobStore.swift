import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A grading job is independent of the view that requested it. The frozen
/// request and accepted receipt never change during transport retries.
struct NFAIGradingJob: Codable, Equatable, Sendable, Identifiable {
    enum Status: String, Codable, Sendable {
        case queued, dispatching, pending, cancelled, accepted
    }
    struct Event: Codable, Equatable, Sendable {
        let revision: Int
        let status: Status
        let occurredAt: Date
        let reason: String?
    }
    var schemaVersion = 1
    var id: UUID { request.id }
    let ownerDeviceID: UUID
    let request: NFAIGradeRequest
    var revision: Int
    var status: Status
    var dispatchCount: Int
    var receipt: NFAIGradeReceipt?
    var events: [Event]

    var isAccepted: Bool { status == .accepted && receipt != nil }
}

/// Versioned per-job files live beside this repository's local archive. A nil
/// directory is deliberately an isolated in-memory store for disposable work.
actor NFAIGradingJobStore {
    enum Failure: Error, LocalizedError, Sendable {
        case unavailable, incompatible, conflictingRequest, staleRevision, cancelled, tooLarge
        var errorDescription: String? {
            switch self {
            case .unavailable: "The grading request could not be saved. Your answer is retained."
            case .incompatible: "This saved grading request needs a compatible version of NeuroForge."
            case .conflictingRequest: "This grading request does not match the saved answer."
            case .staleRevision: "The saved grading request changed. Reload it before retrying."
            case .cancelled: "Evaluation was cancelled. Your saved answer is retained."
            case .tooLarge: "This grading request is too large to save. Your original answer is retained."
            }
        }
    }
    enum WriteStage: Equatable, Sendable { case beforeCommit, committed }
    private let directoryURL: URL?
    private var memory: [UUID: NFAIGradingJob] = [:]
    #if DEBUG
    var writeObserver: (@Sendable (WriteStage) -> Void)?
    func setWriteObserver(_ observer: (@Sendable (WriteStage) -> Void)?) { writeObserver = observer }
    #endif
    private static let maximumBytes = 2 * 1_024 * 1_024
    private static let maximumEvents = 256

    init(directoryURL: URL?) { self.directoryURL = directoryURL?.appendingPathComponent("Grading", isDirectory: true) }

    func create(_ request: NFAIGradeRequest, ownerDeviceID: UUID) throws -> NFAIGradingJob {
        try Task.checkCancellation()
        return try transaction(id: request.id) { existing in
            if let existing {
                try Self.requireBinding(existing, request: request, owner: ownerDeviceID)
                return existing
            }
            return NFAIGradingJob(ownerDeviceID: ownerDeviceID, request: request,
                revision: 0, status: .queued, dispatchCount: 0, receipt: nil,
                events: [.init(revision: 0, status: .queued, occurredAt: request.createdAt, reason: nil)])
        }
    }

    func load(id: UUID, ownerDeviceID: UUID) throws -> NFAIGradingJob? {
        if directoryURL == nil {
            guard let value = memory[id] else { return nil }
            try Self.validate(value)
            guard value.ownerDeviceID == ownerDeviceID else { throw Failure.conflictingRequest }
            return value
        }
        return try withFileLock(id: id) { url in
            guard let value = try Self.read(url) else { return nil }
            try Self.validate(value)
            guard value.id == id, value.ownerDeviceID == ownerDeviceID else { throw Failure.conflictingRequest }
            // A preceding rename may have succeeded while directory verification
            // failed. Reading alone is not permission to publish its result.
            try Self.verifyDirectory(url.deletingLastPathComponent())
            return value
        }
    }

    func beginDispatch(_ request: NFAIGradeRequest, ownerDeviceID: UUID, expectedRevision: Int) throws -> NFAIGradingJob {
        try change(request, owner: ownerDeviceID, expected: expectedRevision, status: .dispatching, reason: nil) { value in
            guard value.status != .accepted, value.dispatchCount < 32 else { throw Failure.incompatible }
            value.dispatchCount += 1
        }
    }

    func markPending(_ request: NFAIGradeRequest, ownerDeviceID: UUID,
                     expectedRevision: Int, reason: String) throws -> NFAIGradingJob {
        try change(request, owner: ownerDeviceID, expected: expectedRevision, status: .pending,
                   reason: String(reason.prefix(256))) { value in
            guard value.status == .dispatching || value.status == .pending else { throw Failure.staleRevision }
        }
    }

    func cancel(_ request: NFAIGradeRequest, ownerDeviceID: UUID, expectedRevision: Int) throws -> NFAIGradingJob {
        try change(request, owner: ownerDeviceID, expected: expectedRevision, status: .cancelled, reason: nil) { value in
            guard value.status != .accepted else { throw Failure.staleRevision }
        }
    }

    func accept(_ receipt: NFAIGradeReceipt, for request: NFAIGradeRequest,
                ownerDeviceID: UUID, expectedRevision: Int) throws -> NFAIGradingJob {
        try NFAIGradeValidator.validate(receipt, for: request)
        return try transaction(id: request.id) { existing in
            guard var value = existing else { throw Failure.unavailable }
            try Self.requireBinding(value, request: request, owner: ownerDeviceID)
            if let original = value.receipt {
                guard try Self.encoded(original) == Self.encoded(receipt) else { throw Failure.conflictingRequest }
                return value
            }
            guard value.revision == expectedRevision else { throw Failure.staleRevision }
            guard value.status == .dispatching else {
                throw value.status == .cancelled ? Failure.cancelled : Failure.staleRevision
            }
            value.receipt = receipt
            try Self.advance(&value, to: .accepted, reason: nil)
            return value
        }
    }

    private func change(_ request: NFAIGradeRequest, owner: UUID, expected: Int,
                        status: NFAIGradingJob.Status, reason: String?,
                        update: (inout NFAIGradingJob) throws -> Void) throws -> NFAIGradingJob {
        try transaction(id: request.id) { existing in
            guard var value = existing else { throw Failure.unavailable }
            try Self.requireBinding(value, request: request, owner: owner)
            guard value.revision == expected, value.receipt == nil else { throw Failure.staleRevision }
            try update(&value)
            try Self.advance(&value, to: status, reason: reason)
            return value
        }
    }

    private static func advance(_ value: inout NFAIGradingJob, to status: NFAIGradingJob.Status, reason: String?) throws {
        guard value.revision < Int.max, value.events.count < maximumEvents else { throw Failure.tooLarge }
        value.revision += 1; value.status = status
        value.events.append(.init(revision: value.revision, status: status, occurredAt: Date(), reason: reason))
    }

    private static func requireBinding(_ value: NFAIGradingJob, request: NFAIGradeRequest, owner: UUID) throws {
        try validate(value)
        guard value.ownerDeviceID == owner, value.id == request.id,
              value.request.contentDigest == request.contentDigest else { throw Failure.conflictingRequest }
    }

    nonisolated static func validate(_ value: NFAIGradingJob) throws {
        try NFAIGradeValidator.validateRequest(value.request)
        guard value.schemaVersion == 1, value.revision >= 0, value.revision < maximumEvents,
              value.dispatchCount >= 0, value.dispatchCount <= 32,
              value.events.count == value.revision + 1,
              value.events.enumerated().allSatisfy({ $0.offset == $0.element.revision
                  && $0.element.occurredAt.timeIntervalSince1970.isFinite
                  && ($0.element.reason?.count ?? 0) <= 256 }),
              value.events.last?.status == value.status,
              (value.status == .accepted) == (value.receipt != nil) else { throw Failure.incompatible }
        if let receipt = value.receipt { try NFAIGradeValidator.validate(receipt, for: value.request) }
    }

    private func transaction(id: UUID, operation: (NFAIGradingJob?) throws -> NFAIGradingJob) throws -> NFAIGradingJob {
        if directoryURL == nil {
            let next = try operation(memory[id]); try Self.validate(next)
            _ = try Self.encoded(next)
            #if DEBUG
            writeObserver?(.beforeCommit)
            #endif
            try Task.checkCancellation()
            memory[id] = next
            #if DEBUG
            writeObserver?(.committed)
            #endif
            return next
        }
        return try withFileLock(id: id) { url in
            let existing = try Self.read(url)
            let next = try operation(existing); try Self.validate(next)
            let bytes = try Self.encoded(next)
            #if DEBUG
            writeObserver?(.beforeCommit)
            #endif
            try Task.checkCancellation()
            try Self.write(bytes, to: url)
            // Cancellation after atomic publication cannot retract this receipt.
            #if DEBUG
            writeObserver?(.committed)
            #endif
            return next
        }
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(value)
        guard bytes.count <= maximumBytes else { throw Failure.tooLarge }
        return bytes
    }

    private func withFileLock<T>(id: UUID, operation: (URL) throws -> T) throws -> T {
        guard let directoryURL else { throw Failure.unavailable }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let file = directoryURL.appendingPathComponent("grade-\(id.uuidString.lowercased()).json")
        let lock = Darwin.open(file.appendingPathExtension("lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw Failure.unavailable }
        defer { Darwin.close(lock) }
        var info = stat()
        guard fstat(lock, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw Failure.unavailable }
        defer { _ = flock(lock, LOCK_UN) }
        return try operation(file)
    }

    @inline(never) private static func read(_ url: URL) throws -> NFAIGradingJob? {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 { if errno == ENOENT { return nil }; throw Failure.unavailable }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= maximumBytes else { throw Failure.tooLarge }
        let bytes = try file.read(upToCount: maximumBytes + 1) ?? Data()
        guard bytes.count <= maximumBytes, bytes.count == info.st_size else { throw Failure.tooLarge }
        return try JSONDecoder().decode(NFAIGradingJob.self, from: bytes)
    }

    private static func write(_ bytes: Data, to url: URL) throws {
        let staged = url.deletingLastPathComponent().appendingPathComponent(".grade-\(UUID().uuidString).tmp")
        let fd = Darwin.open(staged.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Failure.unavailable }
        defer { Darwin.close(fd); try? FileManager.default.removeItem(at: staged) }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                guard let base = buffer.baseAddress else { throw Failure.unavailable }
                let count = Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
                guard count > 0 else { throw Failure.unavailable }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw Failure.unavailable }
        try Task.checkCancellation()
        guard Darwin.rename(staged.path, url.path) == 0 else { throw Failure.unavailable }
        try verifyDirectory(url.deletingLastPathComponent())
    }

    private static func verifyDirectory(_ url: URL) throws {
        let fd = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.unavailable }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw Failure.unavailable }
    }
}

/// A linked review changes the displayed effective evaluation, never the
/// original attempt or receipt. A clarification response is not a zero grade.
enum NFAIGradeReviewProjection {
    static func latestAcceptedReview(of original: NFAIGradeReceipt,
                                     jobs: [NFAIGradingJob]) -> NFAIGradeReceipt? {
        guard (try? NFAIGradeValidator.validate(original, for: original.request)) != nil else { return nil }
        return jobs.reversed().compactMap { job -> NFAIGradeReceipt? in
            guard (try? NFAIGradingJobStore.validate(job)) != nil, let receipt = job.receipt,
                  receipt.decision == .graded, receipt.reviewOf == original.id,
                  receipt.request.attemptID == original.request.attemptID,
                  receipt.request.runID == original.request.runID,
                  receipt.request.slotID == original.request.slotID,
                  receipt.request.exercise == original.request.exercise,
                  receipt.request.response == original.request.response,
                  receipt.request.sourceChunks == original.request.sourceChunks else { return nil }
            return receipt
        }.first
    }
}

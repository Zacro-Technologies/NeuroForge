import Foundation

enum NFAdaptivePlanChangeKind: String, Codable, CaseIterable, Sendable {
    case planMaterialized
    case planReplaced
    case readinessChanged
    case weeklyMissionPinned
    case preferencesApplied
    case undo
}

enum NFAdaptivePlanUndoPayload: Codable, Equatable, Sendable {
    case dailyPlan(
        planID: String,
        expectedCurrentPayload: Data,
        previousPayload: Data
    )
    case readiness(previous: Readiness, expectedCurrent: Readiness)
}

struct NFAdaptivePlanChangeRecord: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1

    let id: UUID
    let schemaVersion: Int
    let profileID: UUID
    let occurredAt: Date
    let kind: NFAdaptivePlanChangeKind
    let title: String
    let previousState: String?
    let newState: String
    let reason: String
    let undoPayload: NFAdaptivePlanUndoPayload?
    let reversesChangeID: UUID?

    init(
        id: UUID = UUID(),
        profileID: UUID,
        occurredAt: Date = .now,
        kind: NFAdaptivePlanChangeKind,
        title: String,
        previousState: String? = nil,
        newState: String,
        reason: String,
        undoPayload: NFAdaptivePlanUndoPayload? = nil,
        reversesChangeID: UUID? = nil
    ) {
        self.id = id
        schemaVersion = Self.schemaVersion
        self.profileID = profileID
        self.occurredAt = occurredAt
        self.kind = kind
        self.title = title
        self.previousState = previousState
        self.newState = newState
        self.reason = reason
        self.undoPayload = undoPayload
        self.reversesChangeID = reversesChangeID
    }

    var canUndo: Bool { undoPayload != nil }
}

enum NFAdaptivePlanHistoryError: Error, Equatable, LocalizedError {
    case unreadable
    case unsupportedVersion(Int)
    case duplicateIdentity
    case couldNotPersist

    var errorDescription: String? {
        switch self {
        case .unreadable:
            NFAppLocalization.localized(
                "The adaptive-plan history could not be read.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Adaptive-plan audit-log read error."
            )
        case let .unsupportedVersion(version):
            NFAppLocalization.localized(
                "This adaptive-plan history uses unsupported version \(version).",
                locale: NFAppLocalization.preferredLocale,
                comment: "Adaptive-plan audit-log version error; the placeholder is the file version."
            )
        case .duplicateIdentity:
            NFAppLocalization.localized(
                "The adaptive-plan history contains duplicate records.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Adaptive-plan audit-log integrity error."
            )
        case .couldNotPersist:
            NFAppLocalization.localized(
                "The adaptive-plan change was saved, but its explanation history could not be updated.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Adaptive-plan audit-log write error."
            )
        }
    }
}

/// A bounded, local audit log for adaptive-plan decisions. It intentionally
/// lives outside the shipped SwiftData schema so adding the diagnostic trail
/// does not mutate the version-one CloudKit contract. Writes are atomic and
/// each decoded envelope is validated before it is exposed to the UI.
struct NFAdaptivePlanHistoryRepository: Sendable {
    static let maximumRecordCount = 128

    private struct Envelope: Codable {
        static let currentVersion = 1

        let version: Int
        let records: [NFAdaptivePlanChangeRecord]
    }

    let fileURL: URL

    static func processDefault(fileManager: FileManager = .default) -> Self {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return Self(fileURL: fileManager.temporaryDirectory
                .appending(path: "NeuroForge-Tests", directoryHint: .isDirectory)
                .appending(path: "AdaptivePlanHistory-\(UUID().uuidString).json", directoryHint: .notDirectory))
        }
        return applicationSupport(fileManager: fileManager)
    }

    static func applicationSupport(fileManager: FileManager = .default) -> Self {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return Self(fileURL: base
            .appending(path: "NeuroForge", directoryHint: .isDirectory)
            .appending(path: "AdaptivePlanHistory-v1.json", directoryHint: .notDirectory))
    }

    func load(fileManager: FileManager = .default) throws -> [NFAdaptivePlanChangeRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let envelope: Envelope
        do {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw NFAdaptivePlanHistoryError.unreadable
        }
        guard envelope.version == Envelope.currentVersion else {
            throw NFAdaptivePlanHistoryError.unsupportedVersion(envelope.version)
        }
        let identities = Set(envelope.records.map(\.id))
        guard identities.count == envelope.records.count,
              envelope.records.allSatisfy({ $0.schemaVersion == NFAdaptivePlanChangeRecord.schemaVersion }) else {
            throw NFAdaptivePlanHistoryError.duplicateIdentity
        }
        return Array(envelope.records
            .sorted {
                if $0.occurredAt == $1.occurredAt { return $0.id.uuidString > $1.id.uuidString }
                return $0.occurredAt > $1.occurredAt
            }
            .prefix(Self.maximumRecordCount))
    }

    func replacingHistory(
        with records: [NFAdaptivePlanChangeRecord],
        fileManager: FileManager = .default
    ) throws {
        guard Set(records.map(\.id)).count == records.count,
              records.allSatisfy({ $0.schemaVersion == NFAdaptivePlanChangeRecord.schemaVersion }) else {
            throw NFAdaptivePlanHistoryError.duplicateIdentity
        }
        let bounded = Array(records
            .sorted {
                if $0.occurredAt == $1.occurredAt { return $0.id.uuidString > $1.id.uuidString }
                return $0.occurredAt > $1.occurredAt
            }
            .prefix(Self.maximumRecordCount))
        let envelope = Envelope(version: Envelope.currentVersion, records: bounded)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let options: Data.WritingOptions = {
                #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                [.atomic, .completeFileProtection]
                #else
                [.atomic]
                #endif
            }()
            try encoder.encode(envelope).write(to: fileURL, options: options)
        } catch {
            throw NFAdaptivePlanHistoryError.couldNotPersist
        }
    }

    @discardableResult
    func appending(
        _ record: NFAdaptivePlanChangeRecord,
        to current: [NFAdaptivePlanChangeRecord],
        fileManager: FileManager = .default
    ) throws -> [NFAdaptivePlanChangeRecord] {
        let updated = [record] + current.filter { $0.id != record.id }
        try replacingHistory(with: updated, fileManager: fileManager)
        return try load(fileManager: fileManager)
    }
}

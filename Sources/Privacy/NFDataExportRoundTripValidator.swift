import Foundation

enum NFDataArchiveValidationError: Error, Equatable, Sendable {
    case unsupportedArchiveVersion(Int)
    case duplicateIdentity(category: String)
}

/// A content-free identity snapshot used to prove that the documented JSON
/// archive is independently decodable before preview or restore. Mutation is
/// owned by `NFDataArchiveRestoreService`, which requires an explicit conflict
/// policy and performs its own semantic and transactional checks.
struct NFDataArchiveRoundTripSnapshot: Equatable, Sendable {
    let archiveVersion: Int
    let profileID: UUID?
    let attemptIDs: Set<UUID>
    let attemptReflectionIDs: Set<UUID>
    let documentIDs: Set<UUID>
    let sourceChunkIDs: Set<String>
    let aiGenerationIDs: Set<UUID>
    let sessionCheckpointIDs: Set<UUID>
    let dailyPlanIDs: Set<String>
    let inputCalibrationIDs: Set<UUID>
    let progressAnnotationIDs: Set<UUID>
    let excludedPrivateAnnotationCount: Int
    let weeklyTransferState: NFWeeklyTransferState?
    let reassessmentState: NFReassessmentState?
    let adaptivePlanChangeIDs: Set<UUID>
    let quarantinedReportIDs: Set<UUID>
}

enum NFDataExportRoundTripValidator {
    @MainActor
    static func decodeArchive(at url: URL) throws -> NFDataArchiveRoundTripSnapshot {
        let data = try NFDataArchiveMigration.normalizedData(from: Data(contentsOf: url))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(ArchiveEnvelope.self, from: data)
        guard (NFDataExportService.oldestRestorableArchiveVersion...NFDataExportService.archiveVersion)
            .contains(archive.archiveVersion) else {
            throw NFDataArchiveValidationError.unsupportedArchiveVersion(archive.archiveVersion)
        }

        return NFDataArchiveRoundTripSnapshot(
            archiveVersion: archive.archiveVersion,
            profileID: archive.profile?.id,
            attemptIDs: try unique(archive.attempts.map(\.id), category: "attempts"),
            attemptReflectionIDs: try unique(archive.attemptReflections.map(\.id), category: "attemptReflections"),
            documentIDs: try unique(archive.documents.map(\.id), category: "documents"),
            sourceChunkIDs: try unique(archive.sourceChunks.map(\.id), category: "sourceChunks"),
            aiGenerationIDs: try unique(archive.aiGenerations.map(\.id), category: "aiGenerations"),
            sessionCheckpointIDs: try unique(archive.sessionCheckpoints.map(\.id), category: "sessionCheckpoints"),
            dailyPlanIDs: try unique(archive.dailyPlans.map(\.id), category: "dailyPlans"),
            inputCalibrationIDs: try unique(archive.inputCalibrations.map(\.id), category: "inputCalibrations"),
            progressAnnotationIDs: try unique(archive.progressAnnotations.map(\.id), category: "progressAnnotations"),
            excludedPrivateAnnotationCount: archive.excludedPrivateAnnotationCount,
            weeklyTransferState: archive.weeklyTransferState,
            reassessmentState: archive.reassessmentState,
            adaptivePlanChangeIDs: try unique(
                (archive.adaptivePlanHistory ?? []).map(\.id),
                category: "adaptivePlanHistory"
            ),
            quarantinedReportIDs: try unique(archive.quarantinedReports.map(\.id), category: "quarantinedReports")
        )
    }

    private static func unique<Value: Hashable>(
        _ values: [Value],
        category: String
    ) throws -> Set<Value> {
        let result = Set(values)
        guard result.count == values.count else {
            throw NFDataArchiveValidationError.duplicateIdentity(category: category)
        }
        return result
    }

    private struct ArchiveEnvelope: Decodable {
        let archiveVersion: Int
        let profile: UUIDEntity?
        let attempts: [UUIDEntity]
        let attemptReflections: [UUIDEntity]
        let documents: [UUIDEntity]
        let sourceChunks: [StringEntity]
        let aiGenerations: [UUIDEntity]
        let sessionCheckpoints: [UUIDEntity]
        let dailyPlans: [StringEntity]
        let inputCalibrations: [UUIDEntity]
        let progressAnnotations: [UUIDEntity]
        let excludedPrivateAnnotationCount: Int
        let weeklyTransferState: NFWeeklyTransferState?
        let reassessmentState: NFReassessmentState?
        let adaptivePlanHistory: [NFAdaptivePlanChangeRecord]?
        let quarantinedReports: [UUIDEntity]
    }

    private struct UUIDEntity: Decodable { let id: UUID }
    private struct StringEntity: Decodable { let id: String }
}

/// Sequential compatibility defaults for the archive fields introduced after
/// v14. Both the identity validator and the restoring decoder consume this
/// normalized representation, so preview and restore cannot disagree about a
/// historical file. The original archiveVersion is retained for disclosure.
@MainActor
enum NFDataArchiveMigration {
    static func normalizedData(from data: Data) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sourceVersion = object["archiveVersion"] as? Int,
              (NFDataExportService.oldestRestorableArchiveVersion..<NFDataExportService.archiveVersion)
                .contains(sourceVersion) else {
            return data
        }

        var migrationVersion = sourceVersion
        if migrationVersion == 14 {
            // v15 introduced per-attempt reflection records.
            if object["attemptReflections"] == nil {
                object["attemptReflections"] = []
            }
            migrationVersion = 15
        }
        if migrationVersion == 15 {
            // v16 introduced the separate adaptive-plan explanation history.
            if object["adaptivePlanHistory"] == nil {
                object["adaptivePlanHistory"] = []
            }
            migrationVersion = 16
        }
        if migrationVersion == 16 {
            // v17 added an optional recommendation explanation to checkpoints.
            if var checkpoints = object["sessionCheckpoints"] as? [[String: Any]] {
                for index in checkpoints.indices where checkpoints[index]["recommendationRationale"] == nil {
                    checkpoints[index]["recommendationRationale"] = NSNull()
                }
                object["sessionCheckpoints"] = checkpoints
            }
        }

        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

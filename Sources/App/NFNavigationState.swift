import SwiftUI

/// Browsing paths are deliberately same-process state. Cold launch starts Today;
/// saved learning belongs to the local run repository, never to navigation paths.
enum NFTodayRoute: Hashable, Codable { case completedReview }
enum NFPracticeRoute: Hashable, Codable {
    case lab(TrainingLab)
    case activity(String)
    case methodology(TrainingLab?)
}
enum NFProgressRoute: Hashable, Codable {
    case skill(TrainingLab)
    case history(TrainingLab?)
    case chartHistory([UUID])
    case attempt(UUID)
}
enum NFSourceRoute: Hashable, Codable {
    case resources
    case document(UUID, chunkID: String?)
}
enum NFSettingsRoute: Hashable, Codable { case methodology }

@MainActor @Observable
final class NFNavigationState {
    let schemaVersion = 1
    var today: [NFTodayRoute] = []
    var practice: [NFPracticeRoute] = []
    var progress: [NFProgressRoute] = []
    var sources: [NFSourceRoute] = []
    var settings: [NFSettingsRoute] = []

    func returnToRoot(_ destination: AppDestination) {
        switch destination {
        case .today: today.removeAll()
        case .train: practice.removeAll()
        case .progress: progress.removeAll()
        case .library: sources.removeAll()
        case .settings: settings.removeAll()
        }
    }

    func prune(documentIDs: Set<UUID>, attemptIDs: Set<UUID>) {
        if sources.contains(where: { route in
            if case .document(let id, _) = route { return !documentIDs.contains(id) }
            return false
        }) { sources.removeAll() }
        if let invalid = progress.firstIndex(where: { route in
            if case .attempt(let id) = route { return !attemptIDs.contains(id) }
            if case .chartHistory(let ids) = route { return ids.contains { !attemptIDs.contains($0) } }
            return false
        }) { progress.removeSubrange(invalid...) }
    }
}

import Foundation

/// Opaque, local identifiers for an exact source-review destination. The URL
/// carries IDs only; filenames, excerpts, prompts, and responses never enter
/// notification, widget, or Spotlight routing payloads.
struct NFSourceReviewDeepLinkDestination: Equatable, Sendable {
    let documentID: UUID
    let chunkID: String?
    let reviewID: UUID?

    init?(
        documentID: UUID,
        chunkID: String?,
        reviewID: UUID?
    ) {
        let normalizedChunkID: String?
        if let chunkID {
            guard let normalized = NFExternalRoute.normalizedOpaqueID(chunkID) else { return nil }
            normalizedChunkID = normalized
        } else {
            normalizedChunkID = nil
        }
        guard reviewID == nil || normalizedChunkID != nil else { return nil }
        self.documentID = documentID
        self.chunkID = normalizedChunkID
        self.reviewID = reviewID
    }
}

struct NFSourceDeepLinkDestination: Equatable, Sendable {
    let documentID: UUID?
    let chunkID: String?
}

enum NFExternalRoute: Equatable, Sendable {
    case today
    case completedTodayReview
    case dueTodayReview
    case sourceReviews(NFSourceReviewDeepLinkDestination?)
    case source(NFSourceDeepLinkDestination)
    case practice
    case progress

    static func parse(_ url: URL) -> NFExternalRoute? {
        guard url.scheme?.lowercased() == "neuroforge",
              let host = url.host?.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let queryItems = components.queryItems ?? []

        switch host {
        case "today":
            switch queryValue(named: "review", in: queryItems) {
            case .absent:
                return .today
            case .value("completed"):
                return .completedTodayReview
            case .value("due"):
                return .dueTodayReview
            case .value, .invalid:
                return nil
            }
        case "reviews":
            let pathParts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            guard pathParts.count <= 1 else { return nil }
            let chunkValue = queryValue(named: "chunk", in: queryItems)
            let reviewValue = queryValue(named: "review", in: queryItems)
            guard chunkValue != .invalid, reviewValue != .invalid else { return nil }
            if pathParts.isEmpty {
                guard chunkValue == .absent, reviewValue == .absent else { return nil }
                return .sourceReviews(nil)
            }
            guard let documentID = UUID(uuidString: String(pathParts[0])) else { return nil }
            let chunkID: String? = if case let .value(value) = chunkValue { value } else { nil }
            let reviewID: UUID? = if case let .value(value) = reviewValue {
                UUID(uuidString: value)
            } else {
                nil
            }
            if case .value = reviewValue, reviewID == nil { return nil }
            guard let destination = NFSourceReviewDeepLinkDestination(
                documentID: documentID,
                chunkID: chunkID,
                reviewID: reviewID
            ) else { return nil }
            return .sourceReviews(destination)
        case "source":
            let pathParts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            guard pathParts.count <= 1 else { return nil }
            let documentID: UUID?
            if let pathPart = pathParts.first {
                guard let parsed = UUID(uuidString: String(pathPart)) else { return nil }
                documentID = parsed
            } else {
                documentID = nil
            }
            switch queryValue(named: "chunk", in: queryItems) {
            case .absent:
                return .source(NFSourceDeepLinkDestination(
                    documentID: documentID,
                    chunkID: nil
                ))
            case let .value(value):
                guard let chunkID = normalizedOpaqueID(value) else { return nil }
                return .source(NFSourceDeepLinkDestination(
                    documentID: documentID,
                    chunkID: chunkID
                ))
            case .invalid:
                return nil
            }
        case "practice":
            return .practice
        case "progress":
            return .progress
        default:
            return nil
        }
    }

    fileprivate static func normalizedOpaqueID(_ value: String) -> String? {
        guard !value.isEmpty,
              value.count <= 256,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._:"))
        guard value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
    }

    private enum QueryValue: Equatable {
        case absent
        case value(String)
        case invalid
    }

    private static func queryValue(
        named name: String,
        in items: [URLQueryItem]
    ) -> QueryValue {
        let matches = items.filter { $0.name == name }
        guard matches.count <= 1 else { return .invalid }
        guard let match = matches.first else { return .absent }
        guard let value = match.value, !value.isEmpty else { return .invalid }
        return .value(value)
    }
}

@MainActor
enum NFExternalRouteRouter {
    static func apply(_ route: NFExternalRoute, to store: AppStore) {
        let destination: AppDestination = switch route {
        case .today, .completedTodayReview, .dueTodayReview:
            .today
        case .sourceReviews, .source:
            .library
        case .practice:
            .train
        case .progress:
            .progress
        }
        guard !store.deferExternalRouteIfDirty(route, destination: destination) else { return }

        switch route {
        case .today:
            store.selectedDestination = .today
            store.requestTodayPlan()
        case .completedTodayReview:
            store.selectedDestination = .today
            store.requestTodayPlan()
            store.shouldOpenCompletedTodayReview = true
        case .dueTodayReview:
            _ = store.requestReviewsDue()
        case let .sourceReviews(destination):
            store.selectedDestination = .library
            store.requestedLibraryDocumentID = destination?.documentID
            store.requestedSourceChunkID = destination?.chunkID
            store.requestedSourceReviewID = destination?.reviewID
            store.shouldOpenSourceReviews = true
        case let .source(destination):
            store.selectedDestination = .library
            store.shouldOpenSourceReviews = false
            store.requestedLibraryDocumentID = destination.documentID
            store.requestedSourceChunkID = destination.chunkID
            store.requestedSourceReviewID = nil
        case .practice:
            store.selectedDestination = .train
        case .progress:
            store.selectedDestination = .progress
        }
    }
}

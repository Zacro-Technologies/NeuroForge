import Foundation

#if canImport(CoreSpotlight) && canImport(UniformTypeIdentifiers)
@preconcurrency import CoreSpotlight
import UniformTypeIdentifiers
#endif

struct NFSpotlightPrivacyConsent: Codable, Equatable, Sendable {
    /// A non-nil timestamp records a user action. There is intentionally no
    /// inferred or migration-time opt-in.
    var explicitlyEnabledAt: Date?
    var includeDocumentTitles: Bool
    var includeSourceText: Bool

    init(
        explicitlyEnabledAt: Date? = nil,
        includeDocumentTitles: Bool = false,
        includeSourceText: Bool = false
    ) {
        self.explicitlyEnabledAt = explicitlyEnabledAt
        self.includeDocumentTitles = includeDocumentTitles
        self.includeSourceText = includeSourceText
    }

    var isExplicitlyEnabled: Bool {
        explicitlyEnabledAt != nil
    }
}

struct NFSpotlightSourceChunk: Codable, Equatable, Identifiable, Sendable {
    let stableChunkID: String
    let documentID: UUID
    let documentTitle: String
    let heading: String?
    let normalizedText: String
    let languageCode: String?
    let modifiedAt: Date

    var id: String { stableChunkID }
}

struct NFSpotlightSearchRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let domainIdentifier: String
    let relatedDocumentIdentifier: String
    let title: String
    let contentDescription: String?
    let searchableText: String?
    let keywords: [String]
    let languageCode: String?
    let modifiedAt: Date
    let contentURL: URL
}

enum NFSpotlightIndexMutation: Codable, Equatable, Sendable {
    case upsert([NFSpotlightSearchRecord])
    case deleteIdentifiers([String])
    case deleteNeuroForgeSourceDomain
}

struct NFSpotlightIndexPlan: Codable, Equatable, Sendable {
    let mutations: [NFSpotlightIndexMutation]
    let privacyOptInApplied: Bool
}

enum NFSpotlightIndexPlanner {
    static let sourceDomainIdentifier = "com.zacrotech.NeuroForge.spotlight.source-chunk.v1"
    private static let identifierPrefix = "nf-source-chunk:"

    static func planReplacement(
        chunks: [NFSpotlightSourceChunk],
        previouslyIndexedChunkIDs: Set<String>,
        consent: NFSpotlightPrivacyConsent,
        language: NFNotificationLanguage
    ) -> NFSpotlightIndexPlan {
        let currentIdentifiers = Set(chunks.map { searchableIdentifier(for: $0.stableChunkID) })
        let previousIdentifiers = Set(previouslyIndexedChunkIDs.map(searchableIdentifier(for:)))

        guard consent.isExplicitlyEnabled else {
            let identifiers = Array(previousIdentifiers.union(currentIdentifiers)).sorted()
            let mutations: [NFSpotlightIndexMutation] = identifiers.isEmpty
                ? []
                : [.deleteIdentifiers(identifiers)]
            return NFSpotlightIndexPlan(mutations: mutations, privacyOptInApplied: false)
        }

        let removedIdentifiers = Array(previousIdentifiers.subtracting(currentIdentifiers)).sorted()
        let records = chunks
            .sorted { $0.stableChunkID < $1.stableChunkID }
            .map { record(from: $0, consent: consent, language: language) }

        var mutations: [NFSpotlightIndexMutation] = []
        if !removedIdentifiers.isEmpty {
            mutations.append(.deleteIdentifiers(removedIdentifiers))
        }
        if !records.isEmpty {
            mutations.append(.upsert(records))
        }
        return NFSpotlightIndexPlan(mutations: mutations, privacyOptInApplied: true)
    }

    static func planGlobalDisable() -> NFSpotlightIndexPlan {
        NFSpotlightIndexPlan(
            mutations: [.deleteNeuroForgeSourceDomain],
            privacyOptInApplied: false
        )
    }

    static func planDocumentDeletion(chunkIDs: Set<String>) -> NFSpotlightIndexPlan {
        let identifiers = chunkIDs.map(searchableIdentifier(for:)).sorted()
        return NFSpotlightIndexPlan(
            mutations: identifiers.isEmpty ? [] : [.deleteIdentifiers(identifiers)],
            privacyOptInApplied: false
        )
    }

    static func searchableIdentifier(for stableChunkID: String) -> String {
        identifierPrefix + stableChunkID
    }

    static func contentURL(documentID: UUID, stableChunkID: String) -> URL {
        var components = URLComponents()
        components.scheme = "neuroforge"
        components.host = "source"
        components.path = "/\(documentID.uuidString.lowercased())"
        components.queryItems = [URLQueryItem(name: "chunk", value: stableChunkID)]
        return components.url!
    }

    private static func record(
        from chunk: NFSpotlightSourceChunk,
        consent: NFSpotlightPrivacyConsent,
        language: NFNotificationLanguage
    ) -> NFSpotlightSearchRecord {
        let locale = Locale(identifier: language == .japanese ? "ja" : "en")
        let genericTitle = NFAppLocalization.localized("NeuroForge study material",
            locale: locale,
            comment: "Privacy-safe generic Spotlight title used when the user does not share document titles."
        )
        let genericDescription = NFAppLocalization.localized("Open this private study item in NeuroForge.",
            locale: locale,
            comment: "Privacy-safe generic Spotlight description used when source text is excluded."
        )

        let title = consent.includeDocumentTitles
            ? nonEmpty(chunk.documentTitle, fallback: genericTitle, maximumLength: 180)
            : genericTitle
        let searchableText = consent.includeSourceText
            ? truncated(chunk.normalizedText, maximumLength: 16_000)
            : nil
        let contentDescription: String?
        if consent.includeSourceText {
            let candidate = chunk.heading.flatMap { heading in
                let clean = heading.trimmingCharacters(in: .whitespacesAndNewlines)
                return clean.isEmpty ? nil : clean
            } ?? chunk.normalizedText
            contentDescription = nonEmpty(
                candidate,
                fallback: genericDescription,
                maximumLength: 280
            )
        } else {
            contentDescription = genericDescription
        }

        return NFSpotlightSearchRecord(
            id: searchableIdentifier(for: chunk.stableChunkID),
            domainIdentifier: sourceDomainIdentifier,
            relatedDocumentIdentifier: chunk.documentID.uuidString,
            title: title,
            contentDescription: contentDescription,
            searchableText: searchableText,
            keywords: consent.includeSourceText
                ? ["NeuroForge", "study", "practice", "review"]
                : ["NeuroForge"],
            languageCode: chunk.languageCode,
            modifiedAt: chunk.modifiedAt,
            contentURL: contentURL(
                documentID: chunk.documentID,
                stableChunkID: chunk.stableChunkID
            )
        )
    }

    private static func nonEmpty(
        _ value: String,
        fallback: String,
        maximumLength: Int
    ) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? fallback : truncated(clean, maximumLength: maximumLength)
    }

    private static func truncated(_ value: String, maximumLength: Int) -> String {
        String(value.prefix(maximumLength))
    }
}

protocol NFSpotlightIndexClient: Sendable {
    func apply(_ plan: NFSpotlightIndexPlan) async throws
}

#if canImport(CoreSpotlight) && canImport(UniformTypeIdentifiers)
actor NFCoreSpotlightIndexAdapter: NFSpotlightIndexClient {
    private let index: CSSearchableIndex

    init(index: CSSearchableIndex = .default()) {
        self.index = index
    }

    func apply(_ plan: NFSpotlightIndexPlan) async throws {
        for mutation in plan.mutations {
            switch mutation {
            case let .upsert(records):
                let searchableItems = records.map(Self.searchableItem(from:))
                try await index.indexSearchableItems(searchableItems)
            case let .deleteIdentifiers(identifiers):
                try await index.deleteSearchableItems(withIdentifiers: identifiers)
            case .deleteNeuroForgeSourceDomain:
                try await index.deleteSearchableItems(
                    withDomainIdentifiers: [NFSpotlightIndexPlanner.sourceDomainIdentifier]
                )
            }
        }
    }

    private static func searchableItem(from record: NFSpotlightSearchRecord) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = record.title
        attributes.contentDescription = record.contentDescription
        attributes.textContent = record.searchableText
        attributes.keywords = record.keywords
        attributes.relatedUniqueIdentifier = record.relatedDocumentIdentifier
        attributes.contentModificationDate = record.modifiedAt
        attributes.contentURL = record.contentURL
        if let languageCode = record.languageCode {
            attributes.languages = [languageCode]
        }

        return CSSearchableItem(
            uniqueIdentifier: record.id,
            domainIdentifier: record.domainIdentifier,
            attributeSet: attributes
        )
    }
}
#endif

import Foundation
import PDFKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct NFSourceLocator: Codable, Hashable, Sendable {
    let page: Int?
    let lineStart: Int?
    let lineEnd: Int?
    let section: String?

    var displayText: String {
        if let page {
            return NFAppLocalization.localized("page \(page)", locale: NFAppLocalization.preferredLocale, comment: "Citation locator followed by a page number.")
        }
        if let lineStart, let lineEnd {
            return NFAppLocalization.localized("lines \(lineStart)–\(lineEnd)", locale: NFAppLocalization.preferredLocale, comment: "Citation locator followed by the first and last line numbers.")
        }
        if let section, !section.isEmpty { return section }
        return NFAppLocalization.localized("source excerpt", locale: NFAppLocalization.preferredLocale, comment: "Fallback citation locator when no page, line, or section is available.")
    }
}

struct NFSourceChunk: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let documentID: UUID
    let documentVersion: Int
    let sourceName: String
    let locator: NFSourceLocator
    let text: String
    let contentHash: String
    let ordinal: Int
    /// Half-open character offsets into the extractor's normalized source text.
    /// PDF and OCR offsets address the deterministic concatenation of pages.
    let characterStart: Int?
    let characterEnd: Int?
    let nearbyHeading: String?
    let language: String?
    let contentTypeTags: [String]

    init(
        id: String,
        documentID: UUID,
        documentVersion: Int,
        sourceName: String,
        locator: NFSourceLocator,
        text: String,
        contentHash: String,
        ordinal: Int,
        characterStart: Int? = nil,
        characterEnd: Int? = nil,
        nearbyHeading: String? = nil,
        language: String? = nil,
        contentTypeTags: [String] = []
    ) {
        self.id = id
        self.documentID = documentID
        self.documentVersion = documentVersion
        self.sourceName = sourceName
        self.locator = locator
        self.text = text
        self.contentHash = contentHash
        self.ordinal = ordinal
        self.characterStart = characterStart
        self.characterEnd = characterEnd
        self.nearbyHeading = nearbyHeading
        self.language = language
        self.contentTypeTags = contentTypeTags
    }

    private enum CodingKeys: String, CodingKey {
        case id, documentID, documentVersion, sourceName, locator, text, contentHash, ordinal
        case characterStart, characterEnd, nearbyHeading, language, contentTypeTags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        documentID = try container.decode(UUID.self, forKey: .documentID)
        documentVersion = try container.decode(Int.self, forKey: .documentVersion)
        sourceName = try container.decode(String.self, forKey: .sourceName)
        locator = try container.decode(NFSourceLocator.self, forKey: .locator)
        text = try container.decode(String.self, forKey: .text)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        ordinal = try container.decode(Int.self, forKey: .ordinal)
        characterStart = try container.decodeIfPresent(Int.self, forKey: .characterStart)
        characterEnd = try container.decodeIfPresent(Int.self, forKey: .characterEnd)
        nearbyHeading = try container.decodeIfPresent(String.self, forKey: .nearbyHeading)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        contentTypeTags = try container.decodeIfPresent([String].self, forKey: .contentTypeTags) ?? []
    }

    var citationLabel: String { "\(sourceName), \(locator.displayText)" }
}

struct NFSourceExtraction: Sendable {
    let chunks: [NFSourceChunk]
    let characterCount: Int
    let warning: String?
}

struct NFRecognizedPage: Sendable {
    let pageNumber: Int
    let text: String
}

enum NFSourceExtractionError: Error, LocalizedError {
    case unreadable
    case noExtractableText
    case unsupportedType

    var errorDescription: String? {
        switch self {
        case .unreadable: NFAppLocalization.localized("The selected file could not be read.", locale: NFAppLocalization.preferredLocale, comment: "Local study-material import error.")
        case .noExtractableText: NFAppLocalization.localized("No extractable text was found. Try an OCR-enabled or text-exported copy.", locale: NFAppLocalization.preferredLocale, comment: "Local study-material import error. OCR means optical character recognition.")
        case .unsupportedType: NFAppLocalization.localized("This file type is not supported for text extraction.", locale: NFAppLocalization.preferredLocale, comment: "Local study-material import error.")
        }
    }
}

enum NFSourceExtractor {
    static let extractorVersion = 5
    private static let targetLength = 1_200
    private static let overlapLength = 160

    static func extract(
        documentID: UUID,
        sourceName: String,
        url: URL,
        csvSelection: NFCSVColumnSelection? = nil
    ) throws -> NFSourceExtraction {
        if url.pathExtension.lowercased() == "pdf" {
            return try extractPDF(documentID: documentID, sourceName: sourceName, url: url)
        }
        guard NFSemanticSourceParser.supports(filename: sourceName) else {
            throw NFSourceExtractionError.unsupportedType
        }
        return try extractText(
            documentID: documentID,
            sourceName: sourceName,
            url: url,
            csvSelection: csvSelection
        )
    }

    static func extractRecognizedPages(
        documentID: UUID,
        sourceName: String,
        pages: [NFRecognizedPage],
        contentTypeTags: [String] = ["pdf", "ocr", "prose"]
    ) throws -> NFSourceExtraction {
        var chunks: [NFSourceChunk] = []
        var characterCount = 0
        var characterBase = 0
        var ordinal = 0

        for page in pages.sorted(by: { $0.pageNumber < $1.pageNumber }) {
            let normalized = normalize(page.text)
            guard !normalized.isEmpty else { continue }
            characterCount += normalized.count
            for piece in split(normalized) {
                chunks.append(makeChunk(
                    documentID: documentID,
                    sourceName: sourceName,
                    locator: NFSourceLocator(page: page.pageNumber, lineStart: nil, lineEnd: nil, section: nil),
                    text: piece.text,
                    ordinal: ordinal,
                    characterStart: characterBase + piece.start,
                    characterEnd: characterBase + piece.end,
                    contentTypeTags: contentTypeTags
                ))
                ordinal += 1
            }
            characterBase += normalized.count
        }

        guard !chunks.isEmpty else { throw NFSourceExtractionError.noExtractableText }
        return NFSourceExtraction(
            chunks: chunks,
            characterCount: characterCount,
            warning: NFAppLocalization.localized(
                "Text recognized locally with Vision OCR; compare critical symbols and equations with the original.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Warning attached to text derived from on-device optical character recognition. Vision is an Apple framework name."
            )
        )
    }

    private static func extractPDF(documentID: UUID, sourceName: String, url: URL) throws -> NFSourceExtraction {
        guard let document = PDFDocument(url: url) else { throw NFSourceExtractionError.unreadable }
        var chunks: [NFSourceChunk] = []
        var characterCount = 0
        var characterBase = 0
        var ordinal = 0

        for pageIndex in 0..<document.pageCount {
            guard let raw = document.page(at: pageIndex)?.string else { continue }
            let normalized = normalize(raw)
            guard !normalized.isEmpty else { continue }
            characterCount += normalized.count
            for piece in split(normalized) {
                chunks.append(makeChunk(
                    documentID: documentID,
                    sourceName: sourceName,
                    locator: NFSourceLocator(page: pageIndex + 1, lineStart: nil, lineEnd: nil, section: nil),
                    text: piece.text,
                    ordinal: ordinal,
                    characterStart: characterBase + piece.start,
                    characterEnd: characterBase + piece.end,
                    contentTypeTags: ["pdf", "prose"]
                ))
                ordinal += 1
            }
            characterBase += normalized.count
        }

        guard !chunks.isEmpty else { throw NFSourceExtractionError.noExtractableText }
        return NFSourceExtraction(chunks: chunks, characterCount: characterCount, warning: nil)
    }

    static func csvPreview(url: URL) throws -> NFCSVSchemaPreview {
        let decoded = try decodeText(at: url)
        let normalizedSource = NFSemanticSourceParser.normalizeSource(decoded)
        if url.pathExtension.lowercased() == "tsv" {
            return NFSemanticSourceParser.parseTSV(normalizedSource).preview
        }
        return NFSemanticSourceParser.parseCSV(normalizedSource).preview
    }

    private static func extractText(
        documentID: UUID,
        sourceName: String,
        url: URL,
        csvSelection: NFCSVColumnSelection?
    ) throws -> NFSourceExtraction {
        let pathExtension = URL(fileURLWithPath: sourceName).pathExtension.lowercased()
        let decoded: String
        switch pathExtension {
        case "html", "htm":
            decoded = htmlVisibleText(try decodeText(at: url))
        case "rtf":
            decoded = try decodeRTF(at: url)
        case "ipynb":
            decoded = try decodeNotebook(at: url)
        default:
            decoded = try decodeText(at: url)
        }
        let normalizedSource = NFSemanticSourceParser.normalizeSource(decoded)
        let drafts: [NFSourceChunkDraft]
        if pathExtension == "csv" {
            drafts = NFSemanticSourceParser.parseCSV(
                normalizedSource,
                selection: csvSelection
            ).chunks
        } else if pathExtension == "tsv" {
            drafts = NFSemanticSourceParser.parseTSV(
                normalizedSource,
                selection: csvSelection
            ).chunks
        } else if pathExtension == "ipynb" {
            drafts = NFSemanticSourceParser.parse(
                normalizedSource,
                filename: "notebook.md"
            ).map { draft in
                NFSourceChunkDraft(
                    text: draft.text,
                    lineStart: draft.lineStart,
                    lineEnd: draft.lineEnd,
                    characterStart: draft.characterStart,
                    characterEnd: draft.characterEnd,
                    section: draft.section,
                    nearbyHeading: draft.nearbyHeading,
                    language: draft.language,
                    contentTypeTags: Array(Set(draft.contentTypeTags + ["notebook"])).sorted()
                )
            }
        } else {
            drafts = NFSemanticSourceParser.parse(
                normalizedSource,
                filename: sourceName
            )
        }
        let chunks = drafts.enumerated().map { ordinal, draft in
            makeChunk(
                documentID: documentID,
                sourceName: sourceName,
                locator: NFSourceLocator(
                    page: nil,
                    lineStart: draft.lineStart,
                    lineEnd: draft.lineEnd,
                    section: draft.section
                ),
                text: draft.text,
                ordinal: ordinal,
                characterStart: draft.characterStart,
                characterEnd: draft.characterEnd,
                nearbyHeading: draft.nearbyHeading,
                language: draft.language,
                contentTypeTags: draft.contentTypeTags
            )
        }

        guard !chunks.isEmpty else { throw NFSourceExtractionError.noExtractableText }
        return NFSourceExtraction(chunks: chunks, characterCount: normalizedSource.count, warning: nil)
    }

    private static func decodeText(at url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let decoded = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
        guard let decoded else { throw NFSourceExtractionError.unreadable }
        return decoded
    }

    private static func decodeRTF(at url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        do {
            let attributed = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            return attributed.string.replacingOccurrences(of: "\u{fffc}", with: "\n")
        } catch {
            throw NFSourceExtractionError.unreadable
        }
    }

    /// Produces a passive reading view of HTML without WebKit, network loads,
    /// scripts, styles, templates, or other active document behavior.
    private static func htmlVisibleText(_ html: String) -> String {
        let suppressedElements: Set<String> = ["script", "style", "noscript", "template", "svg", "canvas"]
        let lineBreakElements: Set<String> = [
            "address", "article", "aside", "blockquote", "br", "caption", "dd", "div", "dl", "dt",
            "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
            "header", "hr", "li", "main", "nav", "ol", "p", "pre", "section", "table", "tr", "ul"
        ]
        var output = ""
        var index = html.startIndex
        var suppressedElement: String?

        func appendBoundary(_ boundary: Character) {
            guard output.last != boundary else { return }
            output.append(boundary)
        }

        while index < html.endIndex {
            if html[index] == "<" {
                if html[index...].hasPrefix("<!--") {
                    guard let commentEnd = html.range(of: "-->", range: index..<html.endIndex) else { break }
                    index = commentEnd.upperBound
                    continue
                }
                guard let tagEnd = htmlTagEnd(in: html, after: index) else {
                    if suppressedElement == nil { output.append("<") }
                    index = html.index(after: index)
                    continue
                }
                let contentStart = html.index(after: index)
                let rawTag = String(html[contentStart..<tagEnd])
                if let tag = htmlTagDescriptor(rawTag) {
                    if let activeSuppressedElement = suppressedElement {
                        if tag.isClosing, tag.name == activeSuppressedElement {
                            suppressedElement = nil
                        }
                    } else if !tag.isClosing, suppressedElements.contains(tag.name) {
                        suppressedElement = tag.name
                    } else if tag.name == "td" || tag.name == "th" {
                        if tag.isClosing { appendBoundary("\t") }
                    } else if lineBreakElements.contains(tag.name) {
                        appendBoundary("\n")
                    }
                }
                index = html.index(after: tagEnd)
                continue
            }

            if suppressedElement == nil {
                if html[index] == "&", let entity = decodedHTMLEntity(in: html, at: index) {
                    output.append(entity.value)
                    index = entity.endIndex
                    continue
                }
                output.append(html[index])
            }
            index = html.index(after: index)
        }

        return output
            .replacingOccurrences(of: #"[ \t\u{00a0}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func htmlTagEnd(in html: String, after opening: String.Index) -> String.Index? {
        var index = html.index(after: opening)
        var quote: Character?
        while index < html.endIndex {
            let character = html[index]
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return index
            }
            index = html.index(after: index)
        }
        return nil
    }

    private static func htmlTagDescriptor(_ rawTag: String) -> (name: String, isClosing: Bool)? {
        var value = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.first != "!", value.first != "?" else { return nil }
        let isClosing = value.first == "/"
        if isClosing { value.removeFirst() }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String(value.prefix { character in
            character.isLetter || character.isNumber || character == ":" || character == "-"
        }).lowercased()
        return name.isEmpty ? nil : (name, isClosing)
    }

    private static func decodedHTMLEntity(
        in html: String,
        at ampersand: String.Index
    ) -> (value: String, endIndex: String.Index)? {
        let maximumLength = 16
        var index = html.index(after: ampersand)
        var count = 0
        while index < html.endIndex, count < maximumLength, html[index] != ";" {
            guard html[index].isLetter || html[index].isNumber || html[index] == "#" else { return nil }
            index = html.index(after: index)
            count += 1
        }
        guard index < html.endIndex, html[index] == ";" else { return nil }
        let bodyStart = html.index(after: ampersand)
        let body = String(html[bodyStart..<index]).lowercased()
        let value: String?
        if body.hasPrefix("#x"), let scalarValue = UInt32(body.dropFirst(2), radix: 16),
           let scalar = UnicodeScalar(scalarValue), scalarValue != 0 {
            value = String(scalar)
        } else if body.hasPrefix("#"), let scalarValue = UInt32(body.dropFirst()),
                  let scalar = UnicodeScalar(scalarValue), scalarValue != 0 {
            value = String(scalar)
        } else {
            value = [
                "amp": "&", "apos": "'", "gt": ">", "lt": "<", "quot": "\"", "nbsp": " ",
                "ndash": "–", "mdash": "—", "hellip": "…", "middot": "·", "times": "×",
                "plusmn": "±", "minus": "−", "le": "≤", "ge": "≥", "ne": "≠"
            ][body]
        }
        guard let value else { return nil }
        return (value, html.index(after: index))
    }

    /// Reads only cell type and source. Notebook metadata, outputs, execution
    /// counts, rich-display payloads, and attachments are never copied into the index.
    private static func decodeNotebook(at url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawCells = root["cells"] as? [Any] else {
            throw NFSourceExtractionError.unreadable
        }
        var preparedCells: [String] = []
        for rawCell in rawCells {
            guard let cell = rawCell as? [String: Any],
                  let cellType = cell["cell_type"] as? String else {
                throw NFSourceExtractionError.unreadable
            }
            let source: String
            if let value = cell["source"] as? String {
                source = value
            } else if let values = cell["source"] as? [Any],
                      values.allSatisfy({ $0 is String }) {
                source = values.compactMap { $0 as? String }.joined()
            } else {
                throw NFSourceExtractionError.unreadable
            }
            guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            if cellType.lowercased() == "markdown" {
                preparedCells.append(source)
            } else {
                let fenceLength = max(3, longestRun(of: "~", in: source) + 1)
                let fence = String(repeating: "~", count: fenceLength)
                let ending = source.hasSuffix("\n") ? "" : "\n"
                preparedCells.append("\(fence)\n\(source)\(ending)\(fence)")
            }
        }
        guard !preparedCells.isEmpty else { throw NFSourceExtractionError.noExtractableText }
        return preparedCells.joined(separator: "\n\n")
    }

    private static func longestRun(of target: Character, in source: String) -> Int {
        var longest = 0
        var current = 0
        for character in source {
            if character == target {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }

    private static func split(_ text: String) -> [(text: String, start: Int, end: Int)] {
        guard text.count > targetLength else { return [(text, 0, text.count)] }
        var result: [(text: String, start: Int, end: Int)] = []
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let proposedEnd = text.index(cursor, offsetBy: targetLength, limitedBy: text.endIndex) ?? text.endIndex
            let end = proposedEnd < text.endIndex
                ? lastSentenceBoundary(in: text, from: cursor, through: proposedEnd)
                    ?? firstSentenceBoundary(in: text, after: proposedEnd)
                    ?? text.endIndex
                : text.endIndex
            let contentStart = text[cursor..<end].firstIndex(where: { !$0.isWhitespace }) ?? end
            let contentEnd = text[cursor..<end].lastIndex(where: { !$0.isWhitespace })
                .map { text.index(after: $0) } ?? contentStart
            if contentStart < contentEnd {
                result.append((
                    String(text[contentStart..<contentEnd]),
                    text.distance(from: text.startIndex, to: contentStart),
                    text.distance(from: text.startIndex, to: contentEnd)
                ))
            }
            guard end < text.endIndex else { break }
            let desiredOverlapStart = text.index(
                end,
                offsetBy: -min(overlapLength, text.distance(from: cursor, to: end))
            )
            let nextSentenceStart = firstSentenceStart(
                in: text,
                atOrAfter: desiredOverlapStart,
                before: end
            )
            // Overlap only at a verified sentence boundary. If the tail has no
            // complete boundary, begin at `end` instead of manufacturing a
            // fragment that could later be treated as an authoritative claim.
            cursor = nextSentenceStart.flatMap { $0 > cursor ? $0 : nil } ?? end
        }
        return result
    }

    private static func lastSentenceBoundary(
        in text: String,
        from start: String.Index,
        through proposedEnd: String.Index
    ) -> String.Index? {
        var boundary: String.Index?
        var index = start
        while index < proposedEnd {
            if let candidate = sentenceStart(after: index, in: text), candidate <= proposedEnd {
                boundary = candidate
            }
            index = text.index(after: index)
        }
        return boundary
    }

    private static func firstSentenceStart(
        in text: String,
        atOrAfter lowerBound: String.Index,
        before upperBound: String.Index
    ) -> String.Index? {
        var index = lowerBound
        while index < upperBound {
            if let candidate = sentenceStart(after: index, in: text), candidate < upperBound {
                return candidate
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func firstSentenceBoundary(
        in text: String,
        after lowerBound: String.Index
    ) -> String.Index? {
        var index = lowerBound
        while index < text.endIndex {
            if let candidate = sentenceStart(after: index, in: text) {
                return candidate
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func sentenceStart(after index: String.Index, in text: String) -> String.Index? {
        let character = text[index]
        if character == "\n" {
            let next = text.index(after: index)
            guard next < text.endIndex, text[next] == "\n" else { return nil }
            return firstNonWhitespaceIndex(after: next, in: text)
        }
        guard ".!?".contains(character), isSentenceTerminator(at: index, in: text) else {
            return nil
        }
        return firstNonWhitespaceIndex(after: index, in: text)
    }

    private static func firstNonWhitespaceIndex(
        after index: String.Index,
        in text: String
    ) -> String.Index {
        var candidate = text.index(after: index)
        while candidate < text.endIndex, text[candidate].isWhitespace {
            candidate = text.index(after: candidate)
        }
        return candidate
    }

    private static func isSentenceTerminator(at index: String.Index, in text: String) -> Bool {
        let next = text.index(after: index)
        guard next == text.endIndex || text[next].isWhitespace else { return false }
        guard text[index] == "." else { return true }
        let previous = index > text.startIndex ? text[text.index(before: index)] : nil
        if previous?.isNumber == true, next < text.endIndex, text[next].isNumber {
            return false
        }
        let contextStart = text.index(index, offsetBy: -min(12, text.distance(from: text.startIndex, to: index)))
        let context = String(text[contextStart...index]).lowercased()
        let nonTerminalSuffixes = [
            "dr.", "mr.", "mrs.", "ms.", "prof.", "fig.", "eq.", "no.", "st.", "vs.",
            "e.g.", "i.e.", "et al."
        ]
        return !nonTerminalSuffixes.contains(where: context.hasSuffix)
            && !isInitialismEnding(at: index, in: text)
    }

    private static func isInitialismEnding(at index: String.Index, in text: String) -> Bool {
        guard text[index] == "." else { return false }
        var period = index
        var componentCount = 0
        while period > text.startIndex {
            let letter = text.index(before: period)
            guard text[letter].isLetter else { break }
            componentCount += 1
            guard letter > text.startIndex else { break }
            let preceding = text.index(before: letter)
            guard text[preceding] == "." else { break }
            period = preceding
        }
        return componentCount >= 2
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{0000}", with: "")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeChunk(
        documentID: UUID,
        sourceName: String,
        locator: NFSourceLocator,
        text: String,
        ordinal: Int,
        characterStart: Int? = nil,
        characterEnd: Int? = nil,
        nearbyHeading: String? = nil,
        language: String? = nil,
        contentTypeTags: [String] = []
    ) -> NFSourceChunk {
        let hash = String(AdaptiveEngine.fnv1a64(text), radix: 16)
        let locatorKey = [
            String(locator.page ?? -1),
            String(locator.lineStart ?? -1),
            String(locator.lineEnd ?? -1),
            String(characterStart ?? -1),
            String(characterEnd ?? -1)
        ].joined(separator: ":")
        let stable = String(AdaptiveEngine.fnv1a64("\(documentID.uuidString)|\(extractorVersion)|\(locatorKey)|\(hash)"), radix: 16)
        return NFSourceChunk(
            id: "chunk.\(stable)",
            documentID: documentID,
            documentVersion: extractorVersion,
            sourceName: sourceName,
            locator: locator,
            text: text,
            contentHash: hash,
            ordinal: ordinal,
            characterStart: characterStart,
            characterEnd: characterEnd,
            nearbyHeading: nearbyHeading,
            language: language,
            contentTypeTags: contentTypeTags
        )
    }
}

enum NFSourceRetriever {
    static func retrieve(query: String, from chunks: [NFSourceChunk], limit: Int = 6) -> [NFSourceChunk] {
        guard !chunks.isEmpty else { return [] }
        let queryTerms = terms(in: query)
        guard !queryTerms.isEmpty else { return Array(chunks.prefix(limit)) }

        return chunks
            .map { chunk in
                let semanticText = [
                    chunk.text,
                    chunk.locator.section,
                    chunk.nearbyHeading,
                    chunk.language,
                    chunk.contentTypeTags.joined(separator: " ")
                ].compactMap { $0 }.joined(separator: " ")
                let chunkTerms = terms(in: semanticText)
                let overlap = queryTerms.reduce(0.0) { partial, term in
                    partial + (chunkTerms.contains(term) ? 1 : 0)
                }
                let exactBoost = chunk.text.localizedCaseInsensitiveContains(query) ? 4.0 : 0
                let density = overlap / Double(max(1, chunkTerms.count))
                return (chunk, overlap + exactBoost + density)
            }
            .sorted {
                if $0.1 == $1.1 { return $0.0.ordinal < $1.0.ordinal }
                return $0.1 > $1.1
            }
            .prefix(max(1, limit))
            .map(\.0)
    }

    private static func terms(in text: String) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) })
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "that", "with", "from", "this", "are", "was", "were", "into", "your", "using"
    ]
}

struct NFSourceChunkDraft: Hashable, Sendable {
    let text: String
    let lineStart: Int
    let lineEnd: Int
    let characterStart: Int
    let characterEnd: Int
    let section: String?
    let nearbyHeading: String?
    let language: String?
    let contentTypeTags: [String]
}

enum NFCSVColumnType: String, Codable, Hashable, Sendable {
    case integer
    case number
    case boolean
    case date
    case text
    case mixed
}

struct NFCSVColumnDescriptor: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let index: Int
    let name: String
    let inferredType: NFCSVColumnType
    let nonEmptyCount: Int
    let distinctCount: Int
    let minimumTextLength: Int?
    let maximumTextLength: Int?
    let numericMinimum: Double?
    let numericMaximum: Double?
    let numericMean: Double?
}

struct NFCSVSchemaPreview: Codable, Hashable, Sendable {
    let rowCount: Int
    let columns: [NFCSVColumnDescriptor]
}

struct NFCSVColumnSelection: Codable, Hashable, Sendable {
    let columnIDs: [String]

    init(columnIDs: some Sequence<String>) {
        var seen: Set<String> = []
        self.columnIDs = columnIDs.filter { seen.insert($0).inserted }
    }

    static func all(in preview: NFCSVSchemaPreview) -> NFCSVColumnSelection {
        NFCSVColumnSelection(columnIDs: preview.columns.map(\.id))
    }
}

/// A deterministic, text-only parser. Format handlers only inspect characters;
/// imported source code is never compiled, interpreted, loaded, or executed.
enum NFSemanticSourceParser {
    private static let targetLength = 2_200
    private static let overlapLength = 240
    static let supportedFilenameExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "mdown", "mkdn", "tex", "latex", "html", "htm", "rtf",
        "csv", "tsv", "json", "jsonl", "yaml", "yml", "xml", "toml", "ipynb",
        "swift", "py", "pyw", "js", "mjs", "cjs", "jsx", "ts", "tsx", "java",
        "c", "h", "m", "mm", "cc", "cpp", "cxx", "hpp", "cs", "go", "rs",
        "rb", "php", "kt", "kts", "scala", "sh", "bash", "zsh", "fish", "sql",
        "r", "lua", "dart", "ex", "exs", "erl", "hrl", "fs", "fsx", "vb", "pl", "pm"
    ]

    static func supports(filename: String) -> Bool {
        supportedFilenameExtensions.contains(URL(fileURLWithPath: filename).pathExtension.lowercased())
    }

    static func normalizeSource(_ source: String) -> String {
        var normalized = source
            .replacingOccurrences(of: "\u{0000}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if normalized.first == "\u{feff}" { normalized.removeFirst() }
        return normalized
    }

    static func parse(_ source: String, filename: String) -> [NFSourceChunkDraft] {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let pathExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let lines = sourceLines(source)
        switch pathExtension {
        case "md", "markdown", "mdown", "mkdn":
            return parseMarkdown(source, lines: lines)
        case "tex", "latex":
            return parseLaTeX(source, lines: lines)
        case "csv":
            return parseCSV(source).chunks
        case "tsv":
            return parseTSV(source).chunks
        case "html", "htm":
            return taggedTextDrafts(
                source,
                lines: lines,
                language: nil,
                tags: ["html", "prose"]
            )
        case "rtf":
            return taggedTextDrafts(
                source,
                lines: lines,
                language: nil,
                tags: ["rtf", "prose"]
            )
        case "json", "jsonl", "yaml", "yml", "xml", "toml":
            let language = pathExtension == "yml" ? "yaml" : pathExtension
            return taggedTextDrafts(
                source,
                lines: lines,
                language: language,
                tags: ["structured-data", language]
            )
        case "ipynb":
            // Notebook containers must first pass through the cell-source-only
            // decoder in `NFSourceExtractor`; raw JSON is never indexed here.
            return []
        default:
            if let language = codeLanguage(for: pathExtension) {
                return parseCode(source, lines: lines, language: language)
            }
            return drafts(
                for: [Block(
                    lineRange: lines.indices,
                    section: nil,
                    nearbyHeading: nil,
                    language: nil,
                    tags: ["plain-text", "prose"],
                    atomic: false
                )],
                source: source,
                lines: lines
            )
        }
    }

    private static func taggedTextDrafts(
        _ source: String,
        lines: [SourceLine],
        language: String?,
        tags: [String]
    ) -> [NFSourceChunkDraft] {
        drafts(
            for: [Block(
                lineRange: lines.indices,
                section: nil,
                nearbyHeading: nil,
                language: language,
                tags: tags,
                atomic: false
            )],
            source: source,
            lines: lines
        )
    }

    private struct SourceLine: Sendable {
        let number: Int
        let start: Int
        let end: Int
        let fullEnd: Int
        let text: String
    }

    private struct Block: Sendable {
        let lineRange: Range<Int>
        let section: String?
        let nearbyHeading: String?
        let language: String?
        let tags: [String]
        let atomic: Bool
    }

    private struct CSVRecord: Sendable {
        let fields: [String]
        let raw: String
        let start: Int
        let end: Int
        let lineStart: Int
        let lineEnd: Int
    }

    struct CSVParseResult: Sendable {
        let preview: NFCSVSchemaPreview
        let chunks: [NFSourceChunkDraft]
    }

    private static func sourceLines(_ source: String) -> [SourceLine] {
        let components = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return [] }
        var offset = 0
        return components.enumerated().map { index, component in
            let text = String(component)
            let end = offset + text.count
            let fullEnd = end < source.count ? end + 1 : end
            defer { offset = fullEnd }
            return SourceLine(
                number: index + 1,
                start: offset,
                end: end,
                fullEnd: fullEnd,
                text: text
            )
        }
    }

    private static func parseMarkdown(_ source: String, lines: [SourceLine]) -> [NFSourceChunkDraft] {
        var blocks: [Block] = []
        var headingStack: [Int: String] = [:]
        var currentStart = lines.startIndex
        var currentSection: String?
        var currentHeading: String?
        var index = lines.startIndex

        func appendProse(until end: Int) {
            guard currentStart < end else { return }
            blocks.append(Block(
                lineRange: currentStart..<end,
                section: currentSection,
                nearbyHeading: currentHeading,
                language: nil,
                tags: currentSection == nil ? ["markdown", "prose"] : ["markdown", "prose", "section"],
                atomic: false
            ))
        }

        while index < lines.endIndex {
            if let fence = markdownFence(in: lines[index].text) {
                appendProse(until: index)
                var closingIndex = index
                var candidate = index + 1
                while candidate < lines.endIndex {
                    if isClosingFence(lines[candidate].text, marker: fence.marker, count: fence.count) {
                        closingIndex = candidate
                        break
                    }
                    closingIndex = candidate
                    candidate += 1
                }
                let language = fence.language
                var tags = ["markdown", "source-code", "code", "fenced-code"]
                if let language { tags.append(language) }
                blocks.append(Block(
                    lineRange: index..<(closingIndex + 1),
                    section: currentSection,
                    nearbyHeading: currentHeading,
                    language: language,
                    tags: tags,
                    atomic: true
                ))
                index = closingIndex + 1
                currentStart = index
                continue
            }

            if let heading = markdownATXHeading(in: lines[index].text) {
                appendProse(until: index)
                updateHeadingStack(&headingStack, level: heading.level, title: heading.title)
                currentSection = headingPath(headingStack)
                currentHeading = heading.title
                currentStart = index
                index += 1
                continue
            }

            if index + 1 < lines.endIndex,
               let level = markdownSetextLevel(in: lines[index + 1].text),
               !lines[index].text.trimmingCharacters(in: .whitespaces).isEmpty {
                appendProse(until: index)
                let title = lines[index].text.trimmingCharacters(in: .whitespaces)
                updateHeadingStack(&headingStack, level: level, title: title)
                currentSection = headingPath(headingStack)
                currentHeading = title
                currentStart = index
                index += 2
                continue
            }
            index += 1
        }
        appendProse(until: lines.endIndex)
        return drafts(for: blocks, source: source, lines: lines)
    }

    private static func parseLaTeX(_ source: String, lines: [SourceLine]) -> [NFSourceChunkDraft] {
        var blocks: [Block] = []
        var headingStack: [Int: String] = [:]
        var currentStart = lines.startIndex
        var currentSection: String?
        var currentHeading: String?
        var index = lines.startIndex

        func appendProse(until end: Int) {
            guard currentStart < end else { return }
            blocks.append(Block(
                lineRange: currentStart..<end,
                section: currentSection,
                nearbyHeading: currentHeading,
                language: "latex",
                tags: currentSection == nil ? ["latex", "prose"] : ["latex", "prose", "section"],
                atomic: false
            ))
        }

        while index < lines.endIndex {
            if let section = latexSection(in: lines[index].text) {
                appendProse(until: index)
                updateHeadingStack(&headingStack, level: section.level, title: section.title)
                currentSection = headingPath(headingStack)
                currentHeading = section.title
                currentStart = index
                index += 1
                continue
            }

            if let delimiter = latexEquationDelimiter(in: lines[index].text) {
                appendProse(until: index)
                var closingIndex = index
                if !delimiter.closedOnOpeningLine {
                    var candidate = index + 1
                    while candidate < lines.endIndex {
                        closingIndex = candidate
                        if lines[candidate].text.contains(delimiter.closing) { break }
                        candidate += 1
                    }
                }
                blocks.append(Block(
                    lineRange: index..<(closingIndex + 1),
                    section: currentSection,
                    nearbyHeading: currentHeading,
                    language: "latex",
                    tags: ["latex", "math", "equation"],
                    atomic: true
                ))
                index = closingIndex + 1
                currentStart = index
                continue
            }
            index += 1
        }
        appendProse(until: lines.endIndex)
        return drafts(for: blocks, source: source, lines: lines)
    }

    private static func parseCode(
        _ source: String,
        lines: [SourceLine],
        language: String
    ) -> [NFSourceChunkDraft] {
        var blocks: [Block] = []
        var currentStart = lines.startIndex
        var currentSymbol: String?

        for index in lines.indices {
            guard let symbol = codeSymbol(in: lines[index].text, language: language) else { continue }
            if currentStart < index {
                var tags = ["source-code", "code", language]
                if currentSymbol != nil { tags.append("symbol") }
                blocks.append(Block(
                    lineRange: currentStart..<index,
                    section: currentSymbol,
                    nearbyHeading: currentSymbol,
                    language: language,
                    tags: tags,
                    atomic: false
                ))
            }
            currentStart = index
            currentSymbol = symbol
        }

        if currentStart < lines.endIndex {
            var tags = ["source-code", "code", language]
            if currentSymbol != nil { tags.append("symbol") }
            blocks.append(Block(
                lineRange: currentStart..<lines.endIndex,
                section: currentSymbol,
                nearbyHeading: currentSymbol,
                language: language,
                tags: tags,
                atomic: false
            ))
        }
        return drafts(for: blocks, source: source, lines: lines)
    }

    static func parseCSV(
        _ source: String,
        selection: NFCSVColumnSelection? = nil
    ) -> CSVParseResult {
        parseDelimitedText(source, delimiter: ",", format: "csv", selection: selection)
    }

    static func parseTSV(
        _ source: String,
        selection: NFCSVColumnSelection? = nil
    ) -> CSVParseResult {
        parseDelimitedText(source, delimiter: "\t", format: "tsv", selection: selection)
    }

    private static func parseDelimitedText(
        _ source: String,
        delimiter: Character,
        format: String,
        selection: NFCSVColumnSelection?
    ) -> CSVParseResult {
        let records = csvRecords(source, delimiter: delimiter).filter {
            $0.fields.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        guard let header = records.first else {
            return CSVParseResult(preview: NFCSVSchemaPreview(rowCount: 0, columns: []), chunks: [])
        }
        let dataRows = Array(records.dropFirst())
        let columnCount = max(
            header.fields.count,
            dataRows.map(\.fields.count).max() ?? 0
        )
        let columnNames = (0..<columnCount).map { columnIndex in
            guard columnIndex < header.fields.count else { return "column_\(columnIndex + 1)" }
            let candidate = header.fields[columnIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            return candidate.isEmpty ? "column_\(columnIndex + 1)" : candidate
        }
        let descriptors = (0..<columnCount).map { columnIndex in
            let values = dataRows.compactMap { row -> String? in
                guard columnIndex < row.fields.count else { return nil }
                let value = row.fields[columnIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            let kind = inferredCSVKind(values)
            let numericValues = values.compactMap(Double.init).filter(\.isFinite)
            return NFCSVColumnDescriptor(
                id: "\(format)-column.\(columnIndex + 1).\(String(AdaptiveEngine.fnv1a64(columnNames[columnIndex].lowercased()), radix: 16))",
                index: columnIndex,
                name: columnNames[columnIndex],
                inferredType: kind,
                nonEmptyCount: values.count,
                distinctCount: Set(values).count,
                minimumTextLength: values.map(\.count).min(),
                maximumTextLength: values.map(\.count).max(),
                numericMinimum: numericValues.min(),
                numericMaximum: numericValues.max(),
                numericMean: numericValues.isEmpty
                    ? nil
                    : numericValues.reduce(0, +) / Double(numericValues.count)
            )
        }
        let preview = NFCSVSchemaPreview(rowCount: dataRows.count, columns: descriptors)
        let selectedIDSet = selection.map { Set($0.columnIDs) }
        let selectedDescriptors = descriptors.filter { selectedIDSet?.contains($0.id) ?? true }
        let selectedIndices = selectedDescriptors.map(\.index)
        let schemaSection = "\(format)-schema"
        var schemaLines = ["\(schemaSection) rows=\(dataRows.count) columns=\(selectedDescriptors.count)"]
        for descriptor in selectedDescriptors {
            schemaLines.append(
                "column[\(descriptor.index + 1)] name=\"\(metadataEscaped(descriptor.name))\" type=\(descriptor.inferredType.rawValue) nonempty=\(descriptor.nonEmptyCount) distinct=\(descriptor.distinctCount)"
            )
        }
        var result = [NFSourceChunkDraft(
            text: schemaLines.joined(separator: "\n"),
            lineStart: header.lineStart,
            lineEnd: header.lineEnd,
            characterStart: header.start,
            characterEnd: header.end,
            section: schemaSection,
            nearbyHeading: schemaSection,
            language: nil,
            contentTypeTags: [format, "table", "schema-summary"]
        )]

        guard !selectedDescriptors.isEmpty else {
            return CSVParseResult(preview: preview, chunks: result)
        }
        let projectedHeader = csvEncodedRow(
            header.fields,
            selecting: selectedIndices,
            delimiter: delimiter
        )
        var rowBuffer: [(record: CSVRecord, projected: String)] = []
        var firstRowNumber = 1
        func flushRows() {
            guard let first = rowBuffer.first, let last = rowBuffer.last else { return }
            let lastRowNumber = firstRowNumber + rowBuffer.count - 1
            result.append(NFSourceChunkDraft(
                text: ([projectedHeader] + rowBuffer.map(\.projected)).joined(separator: "\n"),
                lineStart: first.record.lineStart,
                lineEnd: last.record.lineEnd,
                characterStart: first.record.start,
                characterEnd: last.record.end,
                section: "\(format)-rows-\(firstRowNumber)-\(lastRowNumber)",
                nearbyHeading: "\(format)-table",
                language: nil,
                contentTypeTags: [format, "table", "rows"]
            ))
            firstRowNumber = lastRowNumber + 1
            rowBuffer.removeAll(keepingCapacity: true)
        }

        for row in dataRows {
            let projected = csvEncodedRow(
                row.fields,
                selecting: selectedIndices,
                delimiter: delimiter
            )
            let bufferedLength = projectedHeader.count + rowBuffer.reduce(0) { $0 + $1.projected.count + 1 }
            if !rowBuffer.isEmpty, bufferedLength + projected.count + 1 > targetLength {
                flushRows()
            }
            rowBuffer.append((row, projected))
        }
        flushRows()
        return CSVParseResult(preview: preview, chunks: result)
    }

    private static func drafts(
        for blocks: [Block],
        source: String,
        lines: [SourceLine]
    ) -> [NFSourceChunkDraft] {
        var result: [NFSourceChunkDraft] = []
        for block in blocks {
            guard let trimmed = meaningfulRange(block.lineRange, lines: lines) else { continue }
            if block.atomic {
                if let draft = makeDraft(block: block, lineRange: trimmed, source: source, lines: lines) {
                    result.append(draft)
                }
                continue
            }

            var cursor = trimmed.lowerBound
            while cursor < trimmed.upperBound {
                var end = cursor
                while end < trimmed.upperBound {
                    let proposedLength = lines[end].end - lines[cursor].start
                    if proposedLength > targetLength, end > cursor { break }
                    end += 1
                }
                end = max(cursor + 1, end)
                if let draft = makeDraft(
                    block: block,
                    lineRange: cursor..<end,
                    source: source,
                    lines: lines
                ) {
                    result.append(draft)
                }
                guard end < trimmed.upperBound else { break }
                var overlapStart = end
                while overlapStart > cursor + 1,
                      lines[end - 1].end - lines[overlapStart - 1].start < overlapLength {
                    overlapStart -= 1
                }
                cursor = max(cursor + 1, overlapStart)
            }
        }
        return result
    }

    private static func makeDraft(
        block: Block,
        lineRange: Range<Int>,
        source: String,
        lines: [SourceLine]
    ) -> NFSourceChunkDraft? {
        guard let trimmed = meaningfulRange(lineRange, lines: lines),
              let first = lines[safe: trimmed.lowerBound],
              let last = lines[safe: trimmed.upperBound - 1] else { return nil }
        let text = substring(source, start: first.start, end: last.end)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return NFSourceChunkDraft(
            text: text,
            lineStart: first.number,
            lineEnd: last.number,
            characterStart: first.start,
            characterEnd: last.end,
            section: block.section,
            nearbyHeading: block.nearbyHeading,
            language: block.language,
            contentTypeTags: uniqueTags(block.tags)
        )
    }

    private static func meaningfulRange(
        _ range: Range<Int>,
        lines: [SourceLine]
    ) -> Range<Int>? {
        var start = range.lowerBound
        var end = min(range.upperBound, lines.endIndex)
        while start < end, lines[start].text.trimmingCharacters(in: .whitespaces).isEmpty {
            start += 1
        }
        while end > start, lines[end - 1].text.trimmingCharacters(in: .whitespaces).isEmpty {
            end -= 1
        }
        return start < end ? start..<end : nil
    }

    private static func substring(_ source: String, start: Int, end: Int) -> String {
        let lower = source.index(source.startIndex, offsetBy: max(0, start))
        let upper = source.index(lower, offsetBy: max(0, end - start), limitedBy: source.endIndex) ?? source.endIndex
        return String(source[lower..<upper])
    }

    private static func markdownATXHeading(in line: String) -> (level: Int, title: String)? {
        guard let captures = captures(
            #"^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$"#,
            in: line
        ), captures.count == 2 else { return nil }
        let title = captures[1].trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : (captures[0].count, title)
    }

    private static func markdownSetextLevel(in line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }
        if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func markdownFence(
        in line: String
    ) -> (marker: Character, count: Int, language: String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let count = trimmed.prefix { $0 == marker }.count
        guard count >= 3 else { return nil }
        let info = trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces)
        let token = info.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
        return (marker, count, token.flatMap(normalizedLanguage))
    }

    private static func isClosingFence(_ line: String, marker: Character, count: Int) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.prefix { $0 == marker }.count >= count
            && trimmed.drop { $0 == marker }.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func latexSection(in line: String) -> (level: Int, title: String)? {
        guard let captures = captures(
            #"^\s*\\(part|chapter|section|subsection|subsubsection|paragraph|subparagraph)\*?\{([^}]*)\}"#,
            in: line
        ), captures.count == 2 else { return nil }
        let levels = [
            "part": 1, "chapter": 2, "section": 3, "subsection": 4,
            "subsubsection": 5, "paragraph": 6, "subparagraph": 7
        ]
        let title = captures[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let level = levels[captures[0]], !title.isEmpty else { return nil }
        return (level, title)
    }

    private static func latexEquationDelimiter(
        in line: String
    ) -> (closing: String, closedOnOpeningLine: Bool)? {
        if let captures = captures(
            #"\\begin\{(equation\*?|align\*?|alignat\*?|gather\*?|multline\*?|displaymath|eqnarray\*?)\}"#,
            in: line
        ), let environment = captures.first {
            let closing = "\\end{\(environment)}"
            return (closing, line.range(of: closing) != nil)
        }
        if line.contains("\\[") {
            return ("\\]", line.range(of: "\\]", range: line.range(of: "\\[")!.upperBound..<line.endIndex) != nil)
        }
        let delimiterCount = line.components(separatedBy: "$$").count - 1
        if delimiterCount > 0 {
            return ("$$", delimiterCount >= 2)
        }
        return nil
    }

    private static func updateHeadingStack(
        _ stack: inout [Int: String],
        level: Int,
        title: String
    ) {
        for existingLevel in stack.keys.filter({ $0 >= level }) {
            stack.removeValue(forKey: existingLevel)
        }
        stack[level] = title
    }

    private static func headingPath(_ stack: [Int: String]) -> String? {
        let path = stack.keys.sorted().compactMap { stack[$0] }
        return path.isEmpty ? nil : path.joined(separator: " > ")
    }

    private static func codeLanguage(for pathExtension: String) -> String? {
        let languages: [String: String] = [
            "swift": "swift", "py": "python", "pyw": "python",
            "js": "javascript", "mjs": "javascript", "cjs": "javascript", "jsx": "javascript",
            "ts": "typescript", "tsx": "typescript", "java": "java", "c": "c", "h": "c",
            "m": "objective-c", "mm": "objective-c++", "cc": "cpp", "cpp": "cpp",
            "cxx": "cpp", "hpp": "cpp", "cs": "csharp", "go": "go", "rs": "rust",
            "rb": "ruby", "php": "php", "kt": "kotlin", "kts": "kotlin",
            "scala": "scala", "sh": "shell", "bash": "shell", "zsh": "shell",
            "fish": "shell", "sql": "sql", "r": "r", "lua": "lua", "dart": "dart",
            "ex": "elixir", "exs": "elixir", "erl": "erlang", "hrl": "erlang",
            "fs": "fsharp", "fsx": "fsharp", "vb": "visual-basic", "pl": "perl", "pm": "perl"
        ]
        return languages[pathExtension]
    }

    private static func normalizedLanguage(_ raw: String) -> String? {
        let token = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = [
            "py": "python", "js": "javascript", "jsx": "javascript",
            "ts": "typescript", "tsx": "typescript", "rs": "rust",
            "c++": "cpp", "cs": "csharp", "sh": "shell", "bash": "shell",
            "zsh": "shell", "objc": "objective-c"
        ]
        guard !token.isEmpty else { return nil }
        return aliases[token] ?? token
    }

    private static func codeSymbol(in line: String, language: String) -> String? {
        let pattern: String
        switch language {
        case "python":
            pattern = #"^\s*(?:async\s+)?(?:def|class)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        case "swift":
            pattern = #"^\s*(?:(?:public|private|fileprivate|internal|open|static|final|actor|mutating|nonmutating|class)\s+)*(?:func|struct|enum|protocol|extension|class|actor)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        case "javascript", "typescript":
            pattern = #"^\s*(?:(?:export|default|async|declare|abstract)\s+)*(?:(?:function|class|interface|type|enum)\s+|(?:const|let|var)\s+)([A-Za-z_$][A-Za-z0-9_$]*)"#
        case "rust":
            pattern = #"^\s*(?:(?:pub|async|unsafe|const)\s+)*(?:fn|struct|enum|trait|impl|mod)\s+(?:<[^>]+>\s*)?([A-Za-z_][A-Za-z0-9_]*)"#
        case "go":
            pattern = #"^\s*(?:func\s+(?:\([^)]*\)\s*)?|type\s+)([A-Za-z_][A-Za-z0-9_]*)"#
        case "ruby":
            pattern = #"^\s*(?:def|class|module)\s+(?:self\.)?([A-Za-z_][A-Za-z0-9_!?=]*)"#
        case "sql":
            pattern = #"(?i)^\s*create\s+(?:or\s+replace\s+)?(?:table|view|function|procedure|trigger)\s+([A-Za-z_][A-Za-z0-9_.]*)"#
        default:
            pattern = #"^\s*(?:(?:public|private|protected|internal|static|final|abstract|sealed|open|export)\s+)*(?:class|struct|enum|interface|protocol|record|namespace|module|function|func)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        }
        return captures(pattern, in: line)?.first
    }

    private static func csvRecords(
        _ source: String,
        delimiter: Character
    ) -> [CSVRecord] {
        let characters = Array(source)
        var records: [CSVRecord] = []
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var recordStart = 0
        var recordStartLine = 1
        var line = 1
        var index = 0

        func appendRecord(end: Int, lineEnd: Int) {
            fields.append(field)
            records.append(CSVRecord(
                fields: fields,
                raw: String(characters[recordStart..<end]),
                start: recordStart,
                end: end,
                lineStart: recordStartLine,
                lineEnd: lineEnd
            ))
            fields.removeAll(keepingCapacity: true)
            field = ""
        }

        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(character)
                    if character == "\n" { line += 1 }
                }
            } else {
                switch character {
                case "\"" where field.isEmpty:
                    inQuotes = true
                case let value where value == delimiter:
                    fields.append(field)
                    field = ""
                case "\n":
                    appendRecord(end: index, lineEnd: line)
                    line += 1
                    recordStart = index + 1
                    recordStartLine = line
                default:
                    field.append(character)
                }
            }
            index += 1
        }
        if recordStart < characters.count || !fields.isEmpty || !field.isEmpty {
            appendRecord(end: characters.count, lineEnd: line)
        }
        return records
    }

    private static func inferredCSVKind(_ values: [String]) -> NFCSVColumnType {
        let kinds = Set(values.map(csvValueKind))
        guard !kinds.isEmpty else { return .text }
        if kinds == [.integer] { return .integer }
        if kinds.isSubset(of: [.integer, .number]) { return .number }
        if kinds.count == 1 { return kinds.first ?? .text }
        return .mixed
    }

    private static func csvValueKind(_ value: String) -> NFCSVColumnType {
        let lowercased = value.lowercased()
        if lowercased == "true" || lowercased == "false" { return .boolean }
        if Int64(value) != nil { return .integer }
        if let number = Double(value), number.isFinite { return .number }
        if value.range(
            of: #"^\d{4}-\d{2}-\d{2}(?:[T ][0-9:.+-]+Z?)?$"#,
            options: .regularExpression
        ) != nil { return .date }
        return .text
    }

    private static func metadataEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func csvEncodedRow(
        _ fields: [String],
        selecting indices: [Int],
        delimiter: Character
    ) -> String {
        indices.map { index in
            let field = index < fields.count ? fields[index] : ""
            if field.contains(delimiter) || field.contains("\"") || field.contains("\n") {
                return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return field
        }.joined(separator: String(delimiter))
    }

    private static func uniqueTags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return tags.filter { seen.insert($0).inserted }
    }

    private static func captures(_ pattern: String, in value: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
              ) else { return nil }
        return (1..<match.numberOfRanges).compactMap { captureIndex in
            guard let range = Range(match.range(at: captureIndex), in: value) else { return nil }
            return String(value[range])
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

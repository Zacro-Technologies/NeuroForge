import CoreGraphics
import Foundation
import ImageIO
import PDFKit
@preconcurrency import Vision

enum NFOCRError: Error, LocalizedError {
    case unsupportedDocument
    case unreadablePDF
    case unreadableImage
    case pageRenderingFailed(Int)
    case imageRenderingFailed
    case noRecognizedText

    var errorDescription: String? {
        switch self {
        case .unsupportedDocument:
            NFAppLocalization.localized("Local OCR is available for PDFs and supported images.", locale: NFAppLocalization.preferredLocale, comment: "On-device optical-character-recognition error.")
        case .unreadablePDF:
            NFAppLocalization.localized("The PDF could not be opened for local OCR.", locale: NFAppLocalization.preferredLocale, comment: "On-device optical-character-recognition error.")
        case .unreadableImage:
            NFAppLocalization.localized("The image could not be opened for local OCR.", locale: NFAppLocalization.preferredLocale, comment: "On-device optical-character-recognition error.")
        case let .pageRenderingFailed(page):
            NFAppLocalization.localized("Page \(page) could not be rendered for local OCR.", locale: NFAppLocalization.preferredLocale, comment: "On-device optical-character-recognition error; the placeholder is a page number.")
        case .imageRenderingFailed:
            NFAppLocalization.localized("The image could not be rendered safely for local OCR.", locale: NFAppLocalization.preferredLocale, comment: "On-device optical-character-recognition error.")
        case .noRecognizedText:
            NFAppLocalization.localized("Vision did not find readable text. Try a clearer image or an exported text-based copy.", locale: NFAppLocalization.preferredLocale, comment: "On-device optical-character-recognition error. Vision is an Apple framework name.")
        }
    }
}

enum NFOCRService {
    static func recognizePDF(
        documentID: UUID,
        sourceName: String,
        url: URL
    ) async throws -> NFSourceExtraction {
        guard url.pathExtension.lowercased() == "pdf" else {
            throw NFOCRError.unsupportedDocument
        }

        let pages = try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: url) else { throw NFOCRError.unreadablePDF }
            var recognizedPages: [NFRecognizedPage] = []

            for pageIndex in 0..<document.pageCount {
                try Task.checkCancellation()
                guard let page = document.page(at: pageIndex),
                      let image = render(page: page) else {
                    throw NFOCRError.pageRenderingFailed(pageIndex + 1)
                }

                let text = try recognizedText(in: image)
                if !text.isEmpty {
                    recognizedPages.append(NFRecognizedPage(pageNumber: pageIndex + 1, text: text))
                }
            }

            guard !recognizedPages.isEmpty else { throw NFOCRError.noRecognizedText }
            return recognizedPages
        }.value

        return try NFSourceExtractor.extractRecognizedPages(
            documentID: documentID,
            sourceName: sourceName,
            pages: pages
        )
    }

    static func recognizeImage(
        documentID: UUID,
        sourceName: String,
        url: URL
    ) async throws -> NFSourceExtraction {
        guard NFDocumentImportTypeRegistry.isImage(filename: sourceName) else {
            throw NFOCRError.unsupportedDocument
        }

        let pages = try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let image = try renderedImageForOCR(at: url)
            try Task.checkCancellation()
            let text = try recognizedText(in: image)
            guard !text.isEmpty else { throw NFOCRError.noRecognizedText }
            return [NFRecognizedPage(pageNumber: 1, text: text)]
        }.value

        return try NFSourceExtractor.extractRecognizedPages(
            documentID: documentID,
            sourceName: sourceName,
            pages: pages,
            contentTypeTags: ["image", "ocr", "prose"]
        )
    }

    static func renderedImageForOCR(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ), CGImageSourceGetCount(source) > 0 else {
            throw NFOCRError.unreadableImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_400,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            throw NFOCRError.imageRenderingFailed
        }
        return image
    }

    private static func recognizedText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return (request.results ?? [])
            .sorted { lhs, rhs in
                let verticalDifference = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                if verticalDifference > 0.015 { return lhs.boundingBox.midY > rhs.boundingBox.midY }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func render(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let maximumDimension: CGFloat = 2_400
        let scale = min(2, maximumDimension / max(bounds.width, bounds.height))
        let width = max(1, Int((bounds.width * scale).rounded(.up)))
        let height = max(1, Int((bounds.height * scale).rounded(.up)))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        return context.makeImage()
    }
}

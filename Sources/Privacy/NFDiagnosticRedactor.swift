import Foundation

enum NFDiagnosticContext: String, Sendable {
    case documentImport = "document.import"
    case documentExtraction = "document.extraction"
    case localOCR = "document.ocr"
    case aiAuthoring = "ai.authoring"
    case dataExport = "data.export"
}

/// Converts operational failures into a small, reviewed diagnostic vocabulary.
///
/// Platform-provided error strings can contain local paths, source excerpts, model responses,
/// or answer keys. Those descriptions must never cross into UI, SwiftData, or an
/// export. This type intentionally does not interpolate platform error text,
/// associated model strings, source text, or answer text.
enum NFDiagnosticRedactor {
    static func code(for error: Error, context: NFDiagnosticContext) -> String {
        if error is CancellationError { return "\(context.rawValue).cancelled" }

        if let extractionError = error as? NFSourceExtractionError {
            switch extractionError {
            case .unreadable: return "\(context.rawValue).unreadable"
            case .noExtractableText: return "\(context.rawValue).no_text"
            case .unsupportedType: return "\(context.rawValue).unsupported_type"
            }
        }

        if let validationError = error as? NFDocumentImportValidationError {
            switch validationError {
            case .notRegularFile: return "\(context.rawValue).not_regular_file"
            case .unsupportedType: return "\(context.rawValue).unsupported_type"
            case .fileTooLarge: return "\(context.rawValue).file_too_large"
            }
        }

        if let ocrError = error as? NFOCRError {
            switch ocrError {
            case .unsupportedDocument: return "\(context.rawValue).unsupported_document"
            case .unreadablePDF: return "\(context.rawValue).unreadable_pdf"
            case .unreadableImage: return "\(context.rawValue).unreadable_image"
            case .pageRenderingFailed: return "\(context.rawValue).page_rendering_failed"
            case .imageRenderingFailed: return "\(context.rawValue).image_rendering_failed"
            case .noRecognizedText: return "\(context.rawValue).no_text"
            }
        }

        if let aiError = error as? NFAIError {
            switch aiError {
            case .disabled: return "\(context.rawValue).disabled"
            case .sourcePolicyForbidsAI: return "\(context.rawValue).source_policy"
            case .modelUnavailable: return "\(context.rawValue).model_unavailable"
            case .unsupportedLocale: return "\(context.rawValue).unsupported_locale"
            case .timedOut: return "\(context.rawValue).timed_out"
            case .invalidOutput: return "\(context.rawValue).invalid_output"
            case .generationFailed: return "\(context.rawValue).generation_failed"
            }
        }

        return "\(context.rawValue).failed"
    }

    static func userMessage(
        for error: Error,
        context: NFDiagnosticContext,
        locale: Locale = NFAppLocalization.preferredLocale
    ) -> String {
        if error is CancellationError {
            return NFAppLocalization.localized("The operation was cancelled. Nothing was saved.", locale: locale, comment: "Privacy-reviewed generic cancellation message.")
        }

        if let extractionError = error as? NFSourceExtractionError {
            switch extractionError {
            case .unreadable:
                return NFAppLocalization.localized("The selected file could not be read. Try another local copy.", locale: locale, comment: "Privacy-reviewed local file-reading error.")
            case .noExtractableText:
                return NFAppLocalization.localized("No extractable text was found. Try local OCR or a text-exported copy.", locale: locale, comment: "Privacy-reviewed local text-extraction error.")
            case .unsupportedType:
                return NFAppLocalization.localized("This file type is not supported for text extraction.", locale: locale, comment: "Privacy-reviewed local text-extraction error.")
            }
        }

        if let validationError = error as? NFDocumentImportValidationError {
            switch validationError {
            case .notRegularFile:
                return NFAppLocalization.localized("Choose a regular file rather than a folder, package, or link.", locale: locale, comment: "Privacy-reviewed study-material import validation error.")
            case .unsupportedType:
                return NFAppLocalization.localized("This file type is not supported for local import.", locale: locale, comment: "Privacy-reviewed study-material import validation error.")
            case .fileTooLarge:
                return NFAppLocalization.localized("This file is larger than the 50 MB local import limit.", locale: locale, comment: "Privacy-reviewed study-material import validation error. MB means megabytes.")
            }
        }

        if let ocrError = error as? NFOCRError {
            switch ocrError {
            case .unsupportedDocument:
                return NFAppLocalization.localized("Local OCR is available for PDFs and supported images.", locale: locale, comment: "Privacy-reviewed on-device optical-character-recognition error.")
            case .unreadablePDF:
                return NFAppLocalization.localized("The PDF could not be opened for local OCR.", locale: locale, comment: "Privacy-reviewed on-device optical-character-recognition error.")
            case .unreadableImage:
                return NFAppLocalization.localized("The image could not be opened for local OCR.", locale: locale, comment: "Privacy-reviewed on-device optical-character-recognition error.")
            case let .pageRenderingFailed(page):
                return NFAppLocalization.localized("Page \(page) could not be rendered for local OCR.", locale: locale, comment: "Privacy-reviewed on-device OCR error; the placeholder is a page number.")
            case .imageRenderingFailed:
                return NFAppLocalization.localized("The image could not be rendered safely for local OCR.", locale: locale, comment: "Privacy-reviewed on-device optical-character-recognition error.")
            case .noRecognizedText:
                return NFAppLocalization.localized("No readable text was recognized. Try a clearer image or a text-exported copy.", locale: locale, comment: "Privacy-reviewed on-device optical-character-recognition error.")
            }
        }

        if let aiError = error as? NFAIError {
            switch aiError {
            case .disabled:
                return NFAppLocalization.localized("Question Writer is off in Settings. Offline question writing remains available.", locale: locale, comment: "Question Writer routing message when the feature is disabled.")
            case .sourcePolicyForbidsAI:
                return NFAppLocalization.localized("Question Writer is off for a selected source. The set was created offline.", locale: locale, comment: "Question Writer routing message when a selected source is excluded.")
            case .modelUnavailable:
                return NFAppLocalization.localized("Optional context was unavailable. Offline practice was used.", locale: locale, comment: "Compatibility routing message for a historical optional-presentation failure.")
            case .unsupportedLocale:
                return NFAppLocalization.localized("Optional context did not support the selected language. Offline practice was used.", locale: locale, comment: "Compatibility routing message for a historical optional-presentation language failure.")
            case .timedOut:
                return NFAppLocalization.localized("Question writing took too long. The set was created offline.", locale: locale, comment: "Question Writer timeout fallback message.")
            case .invalidOutput:
                return NFAppLocalization.localized("The returned questions did not pass NeuroForge checks. The set was created offline.", locale: locale, comment: "Question Writer validation fallback message.")
            case .generationFailed:
                return NFAppLocalization.localized("Question writing did not finish. The set was created offline.", locale: locale, comment: "Question Writer failure fallback message.")
            }
        }

        switch context {
        case .documentImport:
            return NFAppLocalization.localized("The document could not be imported. No source contents or local paths were recorded in this diagnostic.", locale: locale, comment: "Privacy-reviewed document-import error.")
        case .documentExtraction:
            return NFAppLocalization.localized("Text extraction did not finish. Try local OCR or a text-exported copy.", locale: locale, comment: "Privacy-reviewed local text-extraction error.")
        case .localOCR:
            return NFAppLocalization.localized("Local OCR did not finish. Try a clearer scan or a text-based PDF.", locale: locale, comment: "Privacy-reviewed on-device optical-character-recognition error.")
        case .aiAuthoring:
            return NFAppLocalization.localized("Question writing did not finish. Offline question writing remains available.", locale: locale, comment: "Question Writer diagnostic fallback message.")
        case .dataExport:
            return NFAppLocalization.localized("The export could not be prepared. Existing data remains unchanged.", locale: locale, comment: "Privacy-reviewed local data-export error.")
        }
    }

    static func persistedMessage(for error: Error, context: NFDiagnosticContext) -> String {
        "\(code(for: error, context: context)): \(userMessage(for: error, context: context, locale: Locale(identifier: "en")))"
    }

    static func sanitizedPersistedMessage(
        _ message: String?,
        context: NFDiagnosticContext
    ) -> String? {
        guard let message, !message.isEmpty else { return nil }

        // These are complete application-owned status strings, never error or
        // source interpolation.
        if message == "Running explicit on-device Vision OCR…"
            || message == "Text recognized locally with Vision OCR; compare critical symbols and equations with the original scan."
            || message == "Text recognized locally with Vision OCR; compare critical symbols and equations with the original." {
            return message
        }

        let code = String(message.prefix { $0 != ":" })
        if code.hasPrefix("\(context.rawValue).") {
            return "\(code): \(reviewedMessage(forSafeCode: code, context: context, locale: Locale(identifier: "en")))"
        }

        return "\(context.rawValue).legacy_redacted: A previous unbounded diagnostic was removed. Retry to create a privacy-safe status."
    }

    static func localizedPersistedMessage(
        _ message: String?,
        context: NFDiagnosticContext,
        locale: Locale = NFAppLocalization.preferredLocale
    ) -> String? {
        guard let message, !message.isEmpty else { return nil }
        if message == "Running explicit on-device Vision OCR…" {
            return NFAppLocalization.localized("Running explicit on-device Vision OCR…", locale: locale, comment: "Study-material status while on-device optical character recognition is running. Vision is an Apple framework name.")
        }
        if message == "Text recognized locally with Vision OCR; compare critical symbols and equations with the original scan." {
            return NFAppLocalization.localized("Text recognized locally with Vision OCR; compare critical symbols and equations with the original scan.", locale: locale, comment: "Study-material OCR verification warning. Vision is an Apple framework name.")
        }
        if message == "Text recognized locally with Vision OCR; compare critical symbols and equations with the original." {
            return NFAppLocalization.localized("Text recognized locally with Vision OCR; compare critical symbols and equations with the original.", locale: locale, comment: "Study-material OCR verification warning for a PDF or image. Vision is an Apple framework name.")
        }
        let code = String(message.prefix { $0 != ":" })
        if code.hasPrefix("\(context.rawValue).") {
            return "\(code): \(reviewedMessage(forSafeCode: code, context: context, locale: locale))"
        }
        return NFAppLocalization.localized("A previous unbounded diagnostic was removed. Retry to create a privacy-safe status.", locale: locale, comment: "Privacy-redaction status for a legacy diagnostic.")
    }

    private static func reviewedMessage(
        forSafeCode code: String,
        context: NFDiagnosticContext,
        locale: Locale
    ) -> String {
        if code.hasSuffix(".cancelled") {
            return NFAppLocalization.localized("The operation was cancelled. Nothing was saved.", locale: locale, comment: "Privacy-reviewed generic cancellation message.")
        }
        if code.hasSuffix(".unsupported_type") || code.hasSuffix(".unsupported_document") {
            return NFAppLocalization.localized("This file type is not supported for the requested local operation.", locale: locale, comment: "Privacy-reviewed local file-operation error.")
        }
        if code.hasSuffix(".not_regular_file") {
            return NFAppLocalization.localized("Choose a regular file rather than a folder, package, or link.", locale: locale, comment: "Privacy-reviewed study-material import validation error.")
        }
        if code.hasSuffix(".file_too_large") {
            return NFAppLocalization.localized("This file is larger than the 50 MB local import limit.", locale: locale, comment: "Privacy-reviewed study-material import validation error. MB means megabytes.")
        }
        if code.hasSuffix(".unreadable")
            || code.hasSuffix(".unreadable_pdf")
            || code.hasSuffix(".unreadable_image") {
            return NFAppLocalization.localized("The selected file could not be read. Try another local copy.", locale: locale, comment: "Privacy-reviewed local file-reading error.")
        }
        if code.hasSuffix(".image_rendering_failed") {
            return NFAppLocalization.localized("The image could not be rendered safely for local OCR.", locale: locale, comment: "Privacy-reviewed on-device optical-character-recognition error.")
        }
        if code.hasSuffix(".no_text") {
            return NFAppLocalization.localized("No readable text was found. Try local OCR or a text-exported copy.", locale: locale, comment: "Privacy-reviewed local text-extraction error.")
        }
        if code.hasSuffix(".model_unavailable") {
            return NFAppLocalization.localized("Optional context was unavailable. Offline practice was used.", locale: locale, comment: "Compatibility routing message for a historical optional-presentation failure.")
        }
        if code.hasSuffix(".invalid_output") {
            return NFAppLocalization.localized("The returned questions did not pass NeuroForge checks. Offline question writing remains available.", locale: locale, comment: "Question Writer diagnostic validation message.")
        }
        switch context {
        case .documentImport: return NFAppLocalization.localized("The document import did not finish.", locale: locale, comment: "Privacy-reviewed document-import error.")
        case .documentExtraction: return NFAppLocalization.localized("Text extraction did not finish.", locale: locale, comment: "Privacy-reviewed local text-extraction error.")
        case .localOCR: return NFAppLocalization.localized("Local OCR did not finish.", locale: locale, comment: "Privacy-reviewed on-device optical-character-recognition error.")
        case .aiAuthoring: return NFAppLocalization.localized("Question writing did not finish. Offline question writing remains available.", locale: locale, comment: "Question Writer diagnostic fallback message.")
        case .dataExport: return NFAppLocalization.localized("The export could not be prepared. Existing data remains unchanged.", locale: locale, comment: "Privacy-reviewed local data-export error.")
        }
    }
}

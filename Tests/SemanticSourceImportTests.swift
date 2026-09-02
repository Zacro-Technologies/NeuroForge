import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import NeuroForge

final class SemanticSourceImportTests: XCTestCase {
    func testSourceReaderPreservesMarkdownStructureAsSeparateReadingUnits() {
        let source = #"""
        # NeuroForge
        Release candidate notes stay readable.

        ## Document control
        | Field | Decision |
        |:------|:---------|
        | Version | **1.0** |
        | Owner | Product team |

        - First requirement
          with a deliberate continuation line
        2. Second requirement
        - [x] Formatting verified

        > Keep evidence and claims separate.
        """#

        XCTAssertEqual(
            NFSourceReadingParser.parse(
                source,
                contentTypeTags: ["markdown", "prose", "section"]
            ),
            [
                .heading(level: 1, text: "NeuroForge"),
                .paragraph("Release candidate notes stay readable."),
                .heading(level: 2, text: "Document control"),
                .table(
                    headers: ["Field", "Decision"],
                    rows: [
                        ["Version", "**1.0**"],
                        ["Owner", "Product team"]
                    ]
                ),
                .unorderedListItem(
                    depth: 0,
                    text: "First requirement\nwith a deliberate continuation line"
                ),
                .orderedListItem(depth: 0, marker: "2.", text: "Second requirement"),
                .taskListItem(depth: 0, isChecked: true, text: "Formatting verified"),
                .blockquote("Keep evidence and claims separate.")
            ]
        )
    }

    func testSourceReaderKeepsCodeAndDisplayMathAtomic() {
        let source = #"""
        Before the calculation.

        ```swift
        let value = 6 * 9
        ```

        $$
        y = mx + b
        $$

        After the calculation.
        """#

        XCTAssertEqual(
            NFSourceReadingParser.parse(source, contentTypeTags: ["markdown", "prose"]),
            [
                .paragraph("Before the calculation."),
                .code(language: "swift", source: "let value = 6 * 9"),
                .displayMath(source: "y = mx + b"),
                .paragraph("After the calculation.")
            ]
        )
    }

    func testSourceReaderInlineMarkdownPreservesNewlinesAndDisablesLinks() throws {
        let attributed = try XCTUnwrap(NFSourceReadingParser.inlineMarkdown(
            "First line\nsecond line with [untrusted link](customscheme://source)"
        ))

        XCTAssertEqual(
            String(attributed.characters),
            "First line\nsecond line with untrusted link"
        )
        XCTAssertFalse(attributed.runs.contains { $0.link != nil })
    }

    func testSourceTableAccessibilityModelProvidesUniqueHeaderAndPositionContext() {
        let model = NFSourceTableAccessibilityModel(
            headers: ["Quantity", "Value"],
            rows: [["Mass", "4 kg"], ["Velocity", "3 m/s"]]
        )

        XCTAssertNotEqual(model.cellLabel(rowIndex: 0, columnIndex: 0), model.cellLabel(rowIndex: 0, columnIndex: 1))
        XCTAssertNotEqual(model.cellLabel(rowIndex: 0, columnIndex: 0), model.cellLabel(rowIndex: 1, columnIndex: 0))
        XCTAssertTrue(model.cellLabel(rowIndex: 0, columnIndex: 0).contains("Quantity"))
        XCTAssertTrue(model.cellLabel(rowIndex: 0, columnIndex: 0).contains("Mass"))
        XCTAssertTrue(model.cellLabel(rowIndex: 0, columnIndex: 1).contains("Value"))
        XCTAssertTrue(model.cellLabel(rowIndex: 0, columnIndex: 1).contains("4 kg"))
        XCTAssertTrue(model.summary.contains("2"))
    }

    func testExerciseTableAccessibilityModelExposesHeadersAndUniqueCellContext() {
        let model = NFExerciseTableAccessibilityModel(
            headers: ["Quantity", "Value"],
            rows: [["Mass", "4 kg"], ["Velocity", "3 m/s"]],
            authoredSummary: "Measured quantities"
        )

        XCTAssertEqual(model.columnCount, 2)
        XCTAssertTrue(model.summary.contains("Measured quantities"))
        XCTAssertTrue(model.headerLabel(columnIndex: 0).contains("Quantity"))
        XCTAssertTrue(model.headerLabel(columnIndex: 1).contains("Value"))
        XCTAssertNotEqual(model.headerLabel(columnIndex: 0), model.headerLabel(columnIndex: 1))
        XCTAssertNotEqual(model.cellLabel(rowIndex: 0, columnIndex: 0), model.cellLabel(rowIndex: 1, columnIndex: 0))
        XCTAssertNotEqual(model.cellLabel(rowIndex: 0, columnIndex: 0), model.cellLabel(rowIndex: 0, columnIndex: 1))
        XCTAssertTrue(model.cellLabel(rowIndex: 0, columnIndex: 1).contains("Value"))
        XCTAssertTrue(model.cellLabel(rowIndex: 0, columnIndex: 1).contains("4 kg"))
        XCTAssertTrue(model.cellLabel(rowIndex: 0, columnIndex: 1).contains("1"))

        let repeated = NFExerciseTableAccessibilityModel(
            headers: ["Value", "Value"],
            rows: [["4", "4"], ["4", "4"]],
            authoredSummary: "Repeated values"
        )
        let repeatedLabels = (0..<2).flatMap { rowIndex in
            (0..<2).map { columnIndex in
                repeated.cellLabel(rowIndex: rowIndex, columnIndex: columnIndex)
            }
        }
        XCTAssertEqual(Set(repeatedLabels).count, 4, "Position context must keep repeated cells unique.")
    }

    func testDocumentReadinessSeparatesIndexStateFromQuestionPrivacyAvailability() {
        let preparing = NFDocumentReadinessPresentation.make(
            indexState: "extracting",
            chunkCount: 0,
            aiPolicy: .onDeviceOnly,
            questionWriterEnabled: false
        )
        let reviewOnly = NFDocumentReadinessPresentation.make(
            indexState: "ready",
            chunkCount: 2,
            aiPolicy: .noAI,
            questionWriterEnabled: true
        )
        let offline = NFDocumentReadinessPresentation.make(
            indexState: "ready",
            chunkCount: 2,
            aiPolicy: .onDeviceOnly,
            questionWriterEnabled: false
        )
        let questionWriter = NFDocumentReadinessPresentation.make(
            indexState: "ready",
            chunkCount: 2,
            aiPolicy: .privateCloudAllowed,
            questionWriterEnabled: true
        )

        XCTAssertNotEqual(preparing.indexStatus, reviewOnly.indexStatus)
        XCTAssertEqual(reviewOnly.indexStatus, offline.indexStatus)
        XCTAssertNotEqual(reviewOnly.questionStatus, offline.questionStatus)
        XCTAssertNotEqual(offline.questionStatus, questionWriter.questionStatus)
    }

    func testDuplicateImportInspectionMatchesFullContentNotFilenameAlone() async throws {
        let selected = try makeFixture(name: "renamed-notes.md", contents: "identical source text")
        let existing = try makeFixture(name: "original-notes.md", contents: "identical source text")
        let sameNameDifferentContent = try makeFixture(name: "renamed-notes.md", contents: "different source text")
        defer {
            selected.remove()
            existing.remove()
            sameNameDifferentContent.remove()
        }

        let existingID = UUID()
        let matching = NFDuplicateImportExistingSource(
            id: existingID,
            filename: "original-notes.md",
            sizeBytes: Int64(Data("identical source text".utf8).count),
            localURL: existing.url,
            indexState: "extractionFailed",
            importedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
        let match = try await NFDuplicateImportInspector.inspect(
            selectedURL: selected.url,
            existingSources: [matching]
        )

        XCTAssertEqual(match?.existingSource.id, existingID)
        XCTAssertEqual(match?.fingerprint.count, 64)
        XCTAssertEqual(match?.selectedFilename, "renamed-notes.md")

        let different = try await NFDuplicateImportInspector.inspect(
            selectedURL: sameNameDifferentContent.url,
            existingSources: [matching]
        )
        XCTAssertNil(different, "A matching filename must not be treated as duplicate content.")
    }

    func testDuplicateRecoveryPlansUseExistingReplaceKeepBothAndSkipExactly() throws {
        let documentID = UUID(uuidString: "4CA73730-E470-4C74-8424-6D8D190A6F2E")!
        let selectedURL = URL(fileURLWithPath: "/tmp/incoming/renamed-scan.pdf")
        let remainingURLs = [
            URL(fileURLWithPath: "/tmp/incoming/second.md"),
            URL(fileURLWithPath: "/tmp/incoming/third.txt")
        ]
        let existing = duplicateExistingSource(
            id: documentID,
            filename: "original-scan.pdf"
        )
        let available = Set([documentID])

        XCTAssertEqual(
            try NFDuplicateImportRecoveryPlanner.plan(
                choice: .useExisting,
                selectedURL: selectedURL,
                existingSource: existing,
                remainingURLs: remainingURLs,
                availableDocumentIDs: available
            ),
            .useExisting(documentID: documentID, remainingURLs: remainingURLs)
        )
        XCTAssertEqual(
            try NFDuplicateImportRecoveryPlanner.plan(
                choice: .replaceExisting,
                selectedURL: selectedURL,
                existingSource: existing,
                remainingURLs: remainingURLs,
                availableDocumentIDs: available
            ),
            .importSelected(
                selectedURL: selectedURL,
                disposition: .replace(existingDocumentID: documentID),
                remainingURLs: remainingURLs
            )
        )
        XCTAssertEqual(
            try NFDuplicateImportRecoveryPlanner.plan(
                choice: .keepBoth,
                selectedURL: selectedURL,
                existingSource: existing,
                remainingURLs: remainingURLs,
                availableDocumentIDs: []
            ),
            .importSelected(
                selectedURL: selectedURL,
                disposition: .keepBoth,
                remainingURLs: remainingURLs
            ),
            "Keeping both remains explicit even if the prior record disappeared."
        )
        XCTAssertEqual(
            try NFDuplicateImportRecoveryPlanner.plan(
                choice: .skip,
                selectedURL: selectedURL,
                existingSource: existing,
                remainingURLs: remainingURLs,
                availableDocumentIDs: []
            ),
            .skip(remainingURLs: remainingURLs),
            "Cancel skips only the reviewed duplicate and preserves the rest of the batch."
        )
    }

    func testDuplicateRecoveryPlansScannedPDFOCRAndTextRetrySeparately() throws {
        let documentID = UUID(uuidString: "9DFCE693-F00D-4DEB-8297-3561F189D084")!
        let selectedURL = URL(fileURLWithPath: "/tmp/incoming/source.pdf")
        let remainingURLs = [URL(fileURLWithPath: "/tmp/incoming/remaining.txt")]

        let scannedPDF = duplicateExistingSource(
            id: documentID,
            filename: "scanned-source.PDF"
        )
        XCTAssertEqual(
            try NFDuplicateImportRecoveryPlanner.plan(
                choice: .retryExisting,
                selectedURL: selectedURL,
                existingSource: scannedPDF,
                remainingURLs: remainingURLs,
                availableDocumentIDs: [documentID]
            ),
            .reprocessExisting(
                documentID: documentID,
                method: .localPDFOCR,
                remainingURLs: remainingURLs
            )
        )

        let textSource = duplicateExistingSource(
            id: documentID,
            filename: "source.md"
        )
        XCTAssertEqual(
            try NFDuplicateImportRecoveryPlanner.plan(
                choice: .retryExisting,
                selectedURL: selectedURL,
                existingSource: textSource,
                remainingURLs: remainingURLs,
                availableDocumentIDs: [documentID]
            ),
            .reprocessExisting(
                documentID: documentID,
                method: .extractText,
                remainingURLs: remainingURLs
            )
        )
    }

    func testDuplicateRecoveryRejectsEveryStaleChoiceThatDependsOnExistingSource() {
        let existing = duplicateExistingSource(
            id: UUID(uuidString: "DF65221E-3E97-45D0-9E22-08DB25473D89")!,
            filename: "missing.pdf"
        )
        for choice in [
            NFDuplicateImportRecoveryChoice.useExisting,
            .replaceExisting,
            .retryExisting
        ] {
            XCTAssertThrowsError(try NFDuplicateImportRecoveryPlanner.plan(
                choice: choice,
                selectedURL: URL(fileURLWithPath: "/tmp/incoming/missing.pdf"),
                existingSource: existing,
                remainingURLs: [],
                availableDocumentIDs: []
            )) { error in
                XCTAssertEqual(
                    error as? NFDuplicateImportRecoveryPlanningError,
                    .existingSourceUnavailable
                )
            }
        }
    }

    func testDuplicateReplacementRollsBackNewImportWhenExistingDeletionFails() {
        enum FixtureFailure: Error, Equatable { case deletionFailed }
        let documentID = UUID(uuidString: "9E7F98DC-5DF5-47ED-83B5-42B6B2C2881D")!
        var events: [String] = []

        XCTAssertThrowsError(try NFDuplicateImportReplacementTransaction.commit(
            importedSource: "new-source",
            existingDocumentID: documentID,
            findExisting: { id in
                events.append("find:\(id.uuidString)")
                return "existing-source"
            },
            deleteExisting: { source in
                events.append("delete:\(source)")
                throw FixtureFailure.deletionFailed
            },
            rollbackImported: { source in
                events.append("rollback:\(source)")
            }
        )) { error in
            XCTAssertEqual(error as? FixtureFailure, .deletionFailed)
        }
        XCTAssertEqual(
            events,
            [
                "find:\(documentID.uuidString)",
                "delete:existing-source",
                "rollback:new-source"
            ]
        )
    }

    func testDuplicateReplacementRollsBackNewImportWhenExistingSourceVanishes() {
        let documentID = UUID(uuidString: "81D3FAEA-5680-475E-9191-E32FB46A1536")!
        var rolledBack: [String] = []

        XCTAssertThrowsError(try NFDuplicateImportReplacementTransaction.commit(
            importedSource: "new-source",
            existingDocumentID: documentID,
            findExisting: { _ -> String? in nil },
            deleteExisting: { (_: String) in XCTFail("Nothing should be deleted.") },
            rollbackImported: { rolledBack.append($0) }
        )) { error in
            XCTAssertEqual(
                error as? NFDuplicateImportRecoveryPlanningError,
                .existingSourceUnavailable
            )
        }
        XCTAssertEqual(rolledBack, ["new-source"])
    }

    func testDuplicateReplacementCommitsWithoutRollingBackOnSuccess() throws {
        let documentID = UUID(uuidString: "BC9AE329-73F5-47E3-980C-14EAE82DE5A9")!
        var deleted: [String] = []
        var rolledBack: [String] = []

        try NFDuplicateImportReplacementTransaction.commit(
            importedSource: "new-source",
            existingDocumentID: documentID,
            findExisting: { _ in "existing-source" },
            deleteExisting: { deleted.append($0) },
            rollbackImported: { rolledBack.append($0) }
        )

        XCTAssertEqual(deleted, ["existing-source"])
        XCTAssertTrue(rolledBack.isEmpty)
    }

    func testFilePickerRegistryCoversEveryExtractorExtension() throws {
        XCTAssertEqual(
            NFDocumentImportTypeRegistry.supportedFilenameExtensions,
            NFSemanticSourceParser.supportedFilenameExtensions
                .union(["pdf"])
                .union(NFDocumentImportTypeRegistry.imageFilenameExtensions)
        )

        let pickerTypeIdentifiers = Set(NFDocumentImportTypeRegistry.contentTypes.map(\.identifier))
        for pathExtension in NFDocumentImportTypeRegistry.supportedFilenameExtensions {
            let type = try XCTUnwrap(
                UTType(filenameExtension: pathExtension),
                "Missing UTType for supported .\(pathExtension) import"
            )
            XCTAssertTrue(
                pickerTypeIdentifiers.contains(type.identifier),
                "The file picker is missing supported .\(pathExtension) imports"
            )
            if pathExtension != "pdf",
               !NFDocumentImportTypeRegistry.imageFilenameExtensions.contains(pathExtension) {
                XCTAssertTrue(NFSemanticSourceParser.supports(filename: "fixture.\(pathExtension)"))
            }
        }
        XCTAssertTrue([
            "html", "rtf", "json", "jsonl", "yaml", "yml", "xml", "toml", "tsv", "ipynb",
            "png", "jpg", "jpeg", "heic", "tiff", "gif", "webp"
        ].allSatisfy(NFDocumentImportTypeRegistry.supportedFilenameExtensions.contains))
        XCTAssertFalse(NFDocumentImportTypeRegistry.supportedFilenameExtensions.contains("bin"))
    }

    func testRecognizedPageChunksOverlapOnlyAtCompleteSentenceBoundaries() throws {
        let sentences = (1...30).map { index in
            if index == 14 {
                return "The control group was evaluated by Dr. Smith before treatment and again after the final dose."
            }
            if index == 17 {
                return "The U.S. population in the sampled region increased during the study."
            }
            return "Sentence \(index) records a complete observation with enough context to support a standalone recall question."
        }
        let source = sentences.joined(separator: " ")
        let extraction = try NFSourceExtractor.extractRecognizedPages(
            documentID: UUID(uuidString: "6C56CB38-9988-4F87-B3DE-BA8CE9C6F128")!,
            sourceName: "long-scan.pdf",
            pages: [NFRecognizedPage(pageNumber: 1, text: source)]
        )

        XCTAssertGreaterThan(extraction.chunks.count, 1)
        for chunk in extraction.chunks {
            XCTAssertTrue(
                sentences.contains(where: chunk.text.hasPrefix),
                "Chunk began inside a sentence: \(chunk.text.prefix(80))"
            )
            XCTAssertTrue(chunk.text.hasSuffix("."))
            XCTAssertFalse(chunk.text.hasPrefix("Smith"))
            XCTAssertFalse(chunk.text.hasPrefix("population in the sampled region"))
            let start = try XCTUnwrap(chunk.characterStart)
            let end = try XCTUnwrap(chunk.characterEnd)
            let lower = source.index(source.startIndex, offsetBy: start)
            let upper = source.index(source.startIndex, offsetBy: end)
            XCTAssertEqual(String(source[lower..<upper]), chunk.text)
        }
    }

    func testMarkdownRetainsHeadingHierarchyFenceLanguageOffsetsAndStableIDs() throws {
        let source = """
        # Mechanics
        Momentum is conserved in a closed system.

        ## Collisions
        Compare the state before and after impact.

        ```python
        def impulse(force, duration):
            return force * duration
        ```
        """
        let fixture = try makeFixture(name: "mechanics.md", contents: source)
        defer { fixture.remove() }
        let documentID = UUID(uuidString: "5E08E049-7A49-4D96-BF8D-87128D39C441")!

        let first = try NFSourceExtractor.extract(
            documentID: documentID,
            sourceName: "mechanics.md",
            url: fixture.url
        )
        let second = try NFSourceExtractor.extract(
            documentID: documentID,
            sourceName: "mechanics.md",
            url: fixture.url
        )

        XCTAssertEqual(first.chunks.map(\.id), second.chunks.map(\.id))
        XCTAssertEqual(Set(first.chunks.compactMap(\.locator.section)), ["Mechanics", "Mechanics > Collisions"])
        let fenced = try XCTUnwrap(first.chunks.first { $0.contentTypeTags.contains("fenced-code") })
        XCTAssertEqual(fenced.language, "python")
        XCTAssertEqual(fenced.nearbyHeading, "Collisions")
        XCTAssertEqual(fenced.locator.section, "Mechanics > Collisions")
        XCTAssertTrue(fenced.text.contains("    return force * duration"))
        try assertExactOffsets(first.chunks, in: source)

        let persisted = SourceChunkRecord(chunk: fenced)
        XCTAssertEqual(persisted.characterStart, fenced.characterStart)
        XCTAssertEqual(persisted.characterEnd, fenced.characterEnd)
        XCTAssertEqual(persisted.nearbyHeading, "Collisions")
        XCTAssertEqual(persisted.language, "python")
        XCTAssertEqual(persisted.contentTypeTags, fenced.contentTypeTags)
        XCTAssertEqual(persisted.snapshot, fenced)
    }

    func testLaTeXPreservesCommandsAndKeepsEquationAsAtomicSectionBoundary() throws {
        let source = #"""
        \section{Energy}
        Work changes kinetic energy.
        \subsection{Derivation}
        \begin{align}
        W &= \int_a^b F(x)\,dx \\
          &= \Delta K
        \end{align}
        Therefore the endpoints determine the change.
        """#
        let fixture = try makeFixture(name: "energy.tex", contents: source)
        defer { fixture.remove() }

        let extraction = try NFSourceExtractor.extract(
            documentID: UUID(),
            sourceName: "energy.tex",
            url: fixture.url
        )
        let equation = try XCTUnwrap(extraction.chunks.first { $0.contentTypeTags.contains("equation") })

        XCTAssertEqual(equation.locator.section, "Energy > Derivation")
        XCTAssertEqual(equation.nearbyHeading, "Derivation")
        XCTAssertEqual(equation.language, "latex")
        XCTAssertTrue(equation.text.hasPrefix(#"\begin{align}"#))
        XCTAssertTrue(equation.text.hasSuffix(#"\end{align}"#))
        XCTAssertTrue(equation.text.contains(#"\int_a^b"#))
        XCTAssertEqual(equation.locator.lineStart, 4)
        XCTAssertEqual(equation.locator.lineEnd, 7)
        try assertExactOffsets(extraction.chunks, in: source)
    }

    func testSourceCodeGetsLanguageAndSymbolBoundariesButIsNeverExecuted() throws {
        let fixtureFolder = FileManager.default.temporaryDirectory
            .appending(path: "NFCodeTextOnly-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fixtureFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureFolder) }
        let marker = fixtureFolder.appending(path: "must-not-exist")
        let source = """
        import Foundation

        func maliciousLookingImport() {
            try? Data("executed".utf8).write(to: URL(fileURLWithPath: "\(marker.path)"))
        }

        struct Solver {
            func answer() -> Int { 42 }
        }
        """
        let url = fixtureFolder.appending(path: "solver.swift")
        try Data(source.utf8).write(to: url)

        let extraction = try NFSourceExtractor.extract(
            documentID: UUID(),
            sourceName: "solver.swift",
            url: url
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertTrue(extraction.chunks.allSatisfy { $0.language == "swift" })
        XCTAssertTrue(extraction.chunks.allSatisfy { $0.contentTypeTags.contains("source-code") })
        XCTAssertTrue(extraction.chunks.contains { $0.locator.section == "maliciousLookingImport" })
        XCTAssertTrue(extraction.chunks.contains { $0.locator.section == "Solver" })
        try assertExactOffsets(extraction.chunks, in: source)
    }

    func testCSVPreviewInfersQuotedFieldsAndSelectionProjectsStableTableChunks() throws {
        let source = #"""
        name,score,active,note,date
        "Ada, A.",10,true,"line one
        line two",2026-08-05
        "Bo ""B""",12.5,false,short,2026-08-06
        """#
        let normalized = NFSemanticSourceParser.normalizeSource(source)
        let full = NFSemanticSourceParser.parseCSV(normalized)
        XCTAssertEqual(full.preview.rowCount, 2)
        XCTAssertEqual(full.preview.columns.map(\.name), ["name", "score", "active", "note", "date"])
        XCTAssertEqual(full.preview.columns.map(\.inferredType), [.text, .number, .boolean, .text, .date])

        let score = try XCTUnwrap(full.preview.columns.first { $0.name == "score" })
        XCTAssertEqual(score.numericMinimum, 10)
        XCTAssertEqual(score.numericMaximum, 12.5)
        XCTAssertEqual(score.numericMean ?? 0, 11.25, accuracy: 0.000_001)
        let note = try XCTUnwrap(full.preview.columns.first { $0.name == "note" })
        XCTAssertEqual(note.nonEmptyCount, 2)
        XCTAssertEqual(note.distinctCount, 2)
        XCTAssertEqual(note.maximumTextLength, "line one\nline two".count)

        let selection = NFCSVColumnSelection(columnIDs: [score.id, note.id])
        let selected = NFSemanticSourceParser.parseCSV(normalized, selection: selection)
        XCTAssertEqual(selected.preview, full.preview)
        XCTAssertTrue(selected.chunks.first?.text.contains("columns=2") == true)
        let rows = try XCTUnwrap(selected.chunks.first { $0.contentTypeTags.contains("rows") })
        XCTAssertTrue(rows.text.hasPrefix("score,note\n"))
        XCTAssertTrue(rows.text.contains(#"10,"line one"#))
        XCTAssertTrue(rows.text.contains("line two\""))
        XCTAssertFalse(rows.text.contains("Ada, A."))
        XCTAssertGreaterThan(rows.lineEnd, rows.lineStart)

        let fixture = try makeFixture(name: "measurements.csv", contents: source)
        defer { fixture.remove() }
        let documentID = UUID(uuidString: "32D55DB0-0FC4-4713-99AC-E70C69EDB154")!
        let first = try NFSourceExtractor.extract(
            documentID: documentID,
            sourceName: "measurements.csv",
            url: fixture.url,
            csvSelection: selection
        )
        let second = try NFSourceExtractor.extract(
            documentID: documentID,
            sourceName: "measurements.csv",
            url: fixture.url,
            csvSelection: selection
        )
        XCTAssertEqual(first.chunks.map(\.id), second.chunks.map(\.id))
        XCTAssertTrue(first.chunks.allSatisfy {
            ($0.characterStart ?? -1) >= 0 && ($0.characterEnd ?? .max) <= first.characterCount
        })
    }

    func testTSVPreviewAndSelectionPreserveTabsAndStableCitations() throws {
        let source = "name\tscore\tnote\nAda\t10\tfirst\nBo\t12.5\tsecond"
        let parsed = NFSemanticSourceParser.parseTSV(source)
        XCTAssertEqual(parsed.preview.rowCount, 2)
        XCTAssertEqual(parsed.preview.columns.map(\.name), ["name", "score", "note"])
        XCTAssertEqual(parsed.preview.columns.map(\.inferredType), [.text, .number, .text])

        let score = try XCTUnwrap(parsed.preview.columns.first { $0.name == "score" })
        let selected = NFSemanticSourceParser.parseTSV(
            source,
            selection: NFCSVColumnSelection(columnIDs: [score.id])
        )
        let rows = try XCTUnwrap(selected.chunks.first { $0.contentTypeTags.contains("rows") })
        XCTAssertEqual(rows.text, "score\n10\n12.5")
        XCTAssertTrue(rows.contentTypeTags.contains("tsv"))

        let fixture = try makeFixture(name: "measurements.tsv", contents: source)
        defer { fixture.remove() }
        let documentID = UUID(uuidString: "719155C5-E37A-4373-88D4-14698102197A")!
        let first = try NFSourceExtractor.extract(
            documentID: documentID,
            sourceName: "measurements.tsv",
            url: fixture.url,
            csvSelection: NFCSVColumnSelection(columnIDs: [score.id])
        )
        let second = try NFSourceExtractor.extract(
            documentID: documentID,
            sourceName: "measurements.tsv",
            url: fixture.url,
            csvSelection: NFCSVColumnSelection(columnIDs: [score.id])
        )
        XCTAssertEqual(first.chunks.map(\.id), second.chunks.map(\.id))
        XCTAssertTrue(first.chunks.allSatisfy { $0.contentTypeTags.contains("tsv") })
    }

    func testHTMLAndRTFAreConvertedToPassiveProseWithoutActiveContent() throws {
        let html = #"""
        <!doctype html>
        <html><head><style>.hidden { content: "STYLE_SECRET"; }</style></head>
        <body><h1>Orbital mechanics</h1><p>Energy &amp; momentum stay visible.</p>
        <script>document.body.textContent = "SCRIPT_SECRET"</script></body></html>
        """#
        let htmlFixture = try makeFixture(name: "lesson.html", contents: html)
        defer { htmlFixture.remove() }
        let documentID = UUID(uuidString: "017E8931-F965-4EB1-B276-C59DB1E5A57A")!
        let firstHTML = try NFSourceExtractor.extract(
            documentID: documentID,
            sourceName: "lesson.html",
            url: htmlFixture.url
        )
        let secondHTML = try NFSourceExtractor.extract(
            documentID: documentID,
            sourceName: "lesson.html",
            url: htmlFixture.url
        )
        let htmlText = firstHTML.chunks.map(\.text).joined(separator: "\n")
        XCTAssertTrue(htmlText.contains("Orbital mechanics"))
        XCTAssertTrue(htmlText.contains("Energy & momentum stay visible."))
        XCTAssertFalse(htmlText.contains("STYLE_SECRET"))
        XCTAssertFalse(htmlText.contains("SCRIPT_SECRET"))
        XCTAssertEqual(firstHTML.chunks.map(\.id), secondHTML.chunks.map(\.id))
        XCTAssertTrue(firstHTML.chunks.allSatisfy { $0.contentTypeTags.contains("html") })

        let rtf = #"{\rtf1\ansi\deff0 Newton's \b second law\b0 relates force, mass, and acceleration.\par Momentum remains conserved in a closed system.}"#
        let rtfFixture = try makeFixture(name: "lesson.rtf", contents: rtf)
        defer { rtfFixture.remove() }
        let rtfExtraction = try NFSourceExtractor.extract(
            documentID: UUID(),
            sourceName: "lesson.rtf",
            url: rtfFixture.url
        )
        let rtfText = rtfExtraction.chunks.map(\.text).joined(separator: "\n")
        XCTAssertTrue(rtfText.contains("Newton's second law"))
        XCTAssertTrue(rtfText.contains("Momentum remains conserved"))
        XCTAssertFalse(rtfText.contains("\\rtf1"))
        XCTAssertTrue(rtfExtraction.chunks.allSatisfy { $0.contentTypeTags.contains("rtf") })
    }

    func testStructuredTextFormatsAreReadOnlyTaggedAndCitationStable() throws {
        let fixtures: [(extension: String, text: String, language: String)] = [
            ("json", #"{"mass": 2, "acceleration": 3}"#, "json"),
            ("jsonl", "{\"trial\":1}\n{\"trial\":2}", "jsonl"),
            ("yaml", "mass: 2\nacceleration: 3", "yaml"),
            ("yml", "mass: 2\nacceleration: 3", "yaml"),
            ("xml", "<experiment><mass>2</mass></experiment>", "xml"),
            ("toml", "[experiment]\nmass = 2", "toml")
        ]
        let documentID = UUID(uuidString: "68D1213D-BD17-4DA6-865C-D27C016A2E53")!
        for fixtureSpec in fixtures {
            let fixture = try makeFixture(
                name: "data.\(fixtureSpec.extension)",
                contents: fixtureSpec.text
            )
            defer { fixture.remove() }
            let first = try NFSourceExtractor.extract(
                documentID: documentID,
                sourceName: "data.\(fixtureSpec.extension)",
                url: fixture.url
            )
            let second = try NFSourceExtractor.extract(
                documentID: documentID,
                sourceName: "data.\(fixtureSpec.extension)",
                url: fixture.url
            )
            XCTAssertEqual(first.chunks.map(\.id), second.chunks.map(\.id))
            XCTAssertTrue(first.chunks.allSatisfy { $0.language == fixtureSpec.language })
            XCTAssertTrue(first.chunks.allSatisfy { $0.contentTypeTags.contains("structured-data") })
            try assertExactOffsets(first.chunks, in: fixtureSpec.text)
        }
    }

    func testNotebookIndexesOnlyCellSourceAndDropsOutputsAttachmentsAndMetadata() throws {
        let notebook = #"""
        {
          "metadata": {"private_note": "METADATA_SECRET"},
          "nbformat": 4,
          "nbformat_minor": 5,
          "cells": [
            {
              "cell_type": "markdown",
              "metadata": {},
              "source": ["# Vectors\n", "A vector has magnitude and direction."],
              "attachments": {"diagram": {"text/plain": ["ATTACHMENT_SECRET"]}}
            },
            {
              "cell_type": "code",
              "metadata": {},
              "execution_count": 7,
              "source": ["def magnitude(x, y):\n", "    return (x * x + y * y) ** 0.5"],
              "outputs": [{"output_type": "stream", "text": ["OUTPUT_SECRET"]}]
            }
          ]
        }
        """#
        let fixture = try makeFixture(name: "vectors.ipynb", contents: notebook)
        defer { fixture.remove() }
        let documentID = UUID(uuidString: "B4898F80-F1B2-438D-AC2B-F2889F7A2AB4")!
        let first = try NFSourceExtractor.extract(
            documentID: documentID,
            sourceName: "vectors.ipynb",
            url: fixture.url
        )
        let second = try NFSourceExtractor.extract(
            documentID: documentID,
            sourceName: "vectors.ipynb",
            url: fixture.url
        )
        let indexed = first.chunks.map(\.text).joined(separator: "\n")
        XCTAssertTrue(indexed.contains("A vector has magnitude and direction."))
        XCTAssertTrue(indexed.contains("def magnitude"))
        XCTAssertFalse(indexed.contains("OUTPUT_SECRET"))
        XCTAssertFalse(indexed.contains("ATTACHMENT_SECRET"))
        XCTAssertFalse(indexed.contains("METADATA_SECRET"))
        XCTAssertEqual(first.chunks.map(\.id), second.chunks.map(\.id))
        XCTAssertTrue(first.chunks.allSatisfy { $0.contentTypeTags.contains("notebook") })
        XCTAssertTrue(first.chunks.contains { $0.contentTypeTags.contains("prose") })
        XCTAssertTrue(first.chunks.contains { $0.contentTypeTags.contains("code") })
        XCTAssertTrue(first.chunks.allSatisfy {
            ($0.characterStart ?? -1) >= 0 && ($0.characterEnd ?? .max) <= first.characterCount
        })
    }

    func testRecognizedImageTextUsesStablePageCitationsAndImageTags() throws {
        let documentID = UUID(uuidString: "88599719-C312-4396-A6F5-39509CE6D829")!
        let pages = [NFRecognizedPage(
            pageNumber: 1,
            text: "The mitochondrion converts chemical energy into ATP."
        )]
        let first = try NFSourceExtractor.extractRecognizedPages(
            documentID: documentID,
            sourceName: "cell.png",
            pages: pages,
            contentTypeTags: ["image", "ocr", "prose"]
        )
        let second = try NFSourceExtractor.extractRecognizedPages(
            documentID: documentID,
            sourceName: "cell.png",
            pages: pages,
            contentTypeTags: ["image", "ocr", "prose"]
        )
        XCTAssertEqual(first.chunks.map(\.id), second.chunks.map(\.id))
        XCTAssertEqual(first.chunks.first?.locator.page, 1)
        XCTAssertEqual(first.chunks.first?.contentTypeTags, ["image", "ocr", "prose"])
        XCTAssertEqual(
            NFDiagnosticRedactor.sanitizedPersistedMessage(
                first.warning,
                context: .documentExtraction
            ),
            first.warning
        )
        XCTAssertEqual(
            NFDiagnosticRedactor.localizedPersistedMessage(
                first.warning,
                context: .documentExtraction,
                locale: Locale(identifier: "en")
            ),
            first.warning
        )
    }

    func testImageImportCreatesAThumbnailBoundedForOnDeviceOCR() throws {
        let fixture = try makeBlankPNGFixture()
        defer { fixture.remove() }
        let image = try NFOCRService.renderedImageForOCR(at: fixture.url)

        XCTAssertEqual(image.width, 128)
        XCTAssertEqual(image.height, 128)
        XCTAssertLessThanOrEqual(max(image.width, image.height), 2_400)
    }

    func testUnsupportedBinaryExtensionFailsClosed() throws {
        let fixture = try makeFixture(name: "payload.bin", contents: "print('not a supported import')")
        defer { fixture.remove() }
        XCTAssertThrowsError(try NFSourceExtractor.extract(
            documentID: UUID(),
            sourceName: "payload.bin",
            url: fixture.url
        )) { error in
            guard case NFSourceExtractionError.unsupportedType = error else {
                return XCTFail("Expected unsupportedType, received \(error)")
            }
        }
    }

    private func assertExactOffsets(_ chunks: [NFSourceChunk], in source: String) throws {
        for chunk in chunks {
            let start = try XCTUnwrap(chunk.characterStart)
            let end = try XCTUnwrap(chunk.characterEnd)
            let lower = source.index(source.startIndex, offsetBy: start)
            let upper = source.index(source.startIndex, offsetBy: end)
            XCTAssertEqual(String(source[lower..<upper]), chunk.text)
        }
    }

    private func duplicateExistingSource(
        id: UUID,
        filename: String
    ) -> NFDuplicateImportExistingSource {
        NFDuplicateImportExistingSource(
            id: id,
            filename: filename,
            sizeBytes: 4_096,
            localURL: URL(fileURLWithPath: "/tmp/library/\(filename)"),
            indexState: "extractionFailed",
            importedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }

    private func makeFixture(name: String, contents: String) throws -> (
        url: URL,
        remove: () -> Void
    ) {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "NFSemanticImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return (url, { try? FileManager.default.removeItem(at: folder) })
    }

    private func makeBlankPNGFixture() throws -> (url: URL, remove: () -> Void) {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "NFImageImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "blank.png")
        guard let context = CGContext(
            data: nil,
            width: 128,
            height: 128,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NFSourceExtractionError.unreadable
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw NFSourceExtractionError.unreadable
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NFSourceExtractionError.unreadable
        }
        return (url, { try? FileManager.default.removeItem(at: folder) })
    }
}

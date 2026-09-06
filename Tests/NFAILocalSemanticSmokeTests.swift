import Foundation
import XCTest
@testable import NeuroForge

/// Opt-in capability smoke measurement, not a certification of evaluator quality.
/// Uses only synthetic learning content and the on-device route; it never reads cloud credentials.
@MainActor
final class NFAILocalSemanticSmokeTests: XCTestCase {
    func testLocalEnglishJapaneseAndSourceGradingAgainstHandWrittenOracles() async throws {
        guard ProcessInfo.processInfo.environment["NEUROFORGE_RUN_LOCAL_AI_SMOKE"] == "1" else {
            throw XCTSkip("Set NEUROFORGE_RUN_LOCAL_AI_SMOKE=1 to run synthetic on-device semantic measurements.")
        }
        let availability = await NFFoundationModelsLearningProvider().availability()
        guard availability.isAvailable else { throw XCTSkip(availability.status) }
        let reportURL = URL(fileURLWithPath: "/tmp/neuroforge-local-semantic-smoke-\(UUID().uuidString).json")
        var measurements: [Measurement] = []
        for testCase in Self.cases {
            let started = Date()
            do {
                let request = try Self.request(testCase)
                let receipt = try await NFAIGradingService.shared.grade(request, mode: .onDeviceOnly)
                let score = try NFAIGradeValidator.score(receipt, for: request)
                measurements.append(.init(caseID: testCase.id, locale: testCase.locale,
                    lowerCredit: testCase.credit.lowerBound, upperCredit: testCase.credit.upperBound,
                    actualCredit: score.credit, elapsedSeconds: Date().timeIntervalSince(started),
                    provider: receipt.providerIdentifier, model: receipt.modelIdentifier,
                    criterionCredits: receipt.criteria.map(\.credit),
                    explanation: receipt.explanation, error: nil))
                XCTAssertEqual(receipt.routeIdentifier, "local", testCase.id)
                XCTAssertTrue(testCase.credit.contains(score.credit),
                    "\(testCase.id): expected \(testCase.credit), received \(score.credit). \(receipt.explanation)")
                XCTAssertTrue(NFAIGradeValidator.validatesScore(score, exercise: request.exercise,
                    response: request.response, attemptID: request.attemptID), testCase.id)
            } catch {
                measurements.append(.init(caseID: testCase.id, locale: testCase.locale,
                    lowerCredit: testCase.credit.lowerBound, upperCredit: testCase.credit.upperBound,
                    actualCredit: nil, elapsedSeconds: Date().timeIntervalSince(started), provider: nil,
                    model: nil, criterionCredits: nil, explanation: nil, error: String(describing: error)))
                XCTFail("\(testCase.id) could not produce an accepted grade: \(error)")
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(measurements).write(to: reportURL, options: .atomic)
        }
        let attachment = XCTAttachment(contentsOfFile: reportURL)
        attachment.lifetime = .keepAlways
        add(attachment)
        print("NEUROFORGE_LOCAL_AI_SMOKE_REPORT=\(reportURL.path)")
    }

    private static func request(_ testCase: OracleCase) throws -> NFAIGradeRequest {
        let sourceChunks = testCase.source.map { [$0] } ?? []
        let authoring = NFAuthoringRequest(capability: sourceChunks.isEmpty ? .contextualize : .sourceGroundedPractice,
            lab: .scientificReasoning, field: .lifeSciences, customTopic: "Synthetic semantic smoke",
            learningObjective: "Explain a direction and its cause.", style: .shortAnswer, difficulty: 0.4,
            count: 1, localeIdentifier: testCase.locale, seed: 123,
            sourceChunks: sourceChunks, documentPolicies: sourceChunks.isEmpty ? [] : [.onDeviceOnly], aiMode: .onDeviceOnly)
        let base = NFAuthoredExerciseAuthority.make(id: "synthetic-smoke.\(testCase.id)",
            lab: .scientificReasoning, style: .shortAnswer, prompt: testCase.question, context: "",
            choices: [], correctAnswer: testCase.reference, acceptedAnswers: [], explanation: testCase.reference,
            hint: testCase.locale.hasPrefix("ja") ? "移動の向きとその根拠を分けて考えてください。" : "Consider the direction and its reason separately.",
            decisiveStep: testCase.locale.hasPrefix("ja") ? "移動の向きとその理由を説明してください。" : "Explain the direction and its reason.",
            difficulty: 0.4, citationChunkIDs: sourceChunks.map(\.id), evidenceClass: .documentPractice,
            contentTier: .bundledAuthored, request: authoring)
        let exercise = try NFAIExerciseFactory.shortResponse(from: base,
            reference: testCase.reference, criteria: testCase.criteria)
        return .init(attemptID: UUID(), runID: UUID(), exercise: exercise,
                     response: .shortText(testCase.answer), sourceChunks: sourceChunks)
    }

    private struct OracleCase {
        let id: String
        let locale: String
        let question: String
        let reference: String
        let criteria: [String]
        let answer: String
        let credit: ClosedRange<Double>
        let source: NFSourceChunk?
    }

    private struct Measurement: Encodable {
        let caseID: String
        let locale: String
        let lowerCredit: Double
        let upperCredit: Double
        let actualCredit: Double?
        let elapsedSeconds: Double
        let provider: String?
        let model: String?
        let criterionCredits: [Double]?
        let explanation: String?
        let error: String?
    }

    private static var cases: [OracleCase] {
        let englishQuestion = "A membrane permits only water to cross between two solutions. Which way does water move when one side has more dissolved solute, and why?"
        let englishReference = "Water moves toward the more concentrated solution. Dissolved solute lowers water potential, so water moves from higher to lower water potential."
        let englishCriteria = [
            "Identify net water movement toward the side with more dissolved solute.",
            "Explain that solute lowers water potential and water moves from higher to lower water potential."
        ]
        let japaneseQuestion = "水だけを通す膜を挟んで、溶質濃度の異なる二つの溶液があります。水はどちらへ移動し、それはなぜですか。"
        let japaneseReference = "水は溶質濃度の高い側へ移動します。溶質は水ポテンシャルを低くするため、水は水ポテンシャルの高い側から低い側へ移動するからです。"
        let japaneseCriteria = [
            "水が溶質濃度の高い側へ正味で移動することを述べている。",
            "溶質が水ポテンシャルを下げ、水が水ポテンシャルの高い側から低い側へ移動すると説明している。"
        ]
        var result = [
            OracleCase(id: "en-paraphrase", locale: "en", question: englishQuestion, reference: englishReference,
                criteria: englishCriteria,
                answer: "The saltier side has lower water potential, so water flows into that side from the side with higher water potential.",
                credit: 0.95...1, source: nil),
            OracleCase(id: "en-partial", locale: "en", question: englishQuestion, reference: englishReference,
                criteria: englishCriteria, answer: "Water moves toward the more concentrated solution.",
                credit: 0.35...0.65, source: nil),
            OracleCase(id: "en-contradiction", locale: "en", question: englishQuestion, reference: englishReference,
                criteria: englishCriteria,
                answer: "Water moves into the less concentrated solution because adding solute raises water potential.",
                credit: 0...0.1, source: nil),
            OracleCase(id: "ja-paraphrase", locale: "ja", question: japaneseQuestion, reference: japaneseReference,
                criteria: japaneseCriteria,
                answer: "溶質の多い側は水ポテンシャルが低いので、水は水ポテンシャルの高い薄い溶液側から、溶質の多い側へ流れます。",
                credit: 0.95...1, source: nil),
            OracleCase(id: "ja-partial", locale: "ja", question: japaneseQuestion, reference: japaneseReference,
                criteria: japaneseCriteria, answer: "水は溶質濃度の高い側へ移動します。",
                credit: 0.35...0.65, source: nil),
            OracleCase(id: "ja-contradiction", locale: "ja", question: japaneseQuestion, reference: japaneseReference,
                criteria: japaneseCriteria,
                answer: "水は溶質濃度の低い側に移動します。溶質が多いほど水ポテンシャルが高いからです。",
                credit: 0...0.1, source: nil)
        ]
        let source = NFSourceChunk(id: "synthetic-greenhouse-source", documentID: UUID(), documentVersion: 1,
            sourceName: "Synthetic greenhouse note", locator: .init(page: nil, lineStart: 1, lineEnd: 2, section: nil),
            text: "The greenhouse vent opens when internal temperature reaches 28 °C. Opening the vent increases air exchange and lets warm air leave the greenhouse.",
            contentHash: "synthetic-smoke-source-v1", ordinal: 0)
        result.append(.init(id: "en-source-paraphrase", locale: "en",
            question: "According to the greenhouse note, when does the vent open, and how does this limit overheating?",
            reference: "The vent opens at 28 °C. Increased air exchange lets warm air leave, limiting heat inside.",
            criteria: ["State that the vent opens when internal temperature reaches 28 °C.",
                       "Explain that increased air exchange lets warm air leave and limits overheating."],
            answer: "At 28 °C the vent opens, allowing warm air to escape through greater air exchange so heat does not keep building up inside.",
            credit: 0.95...1, source: source))
        return result
    }
}

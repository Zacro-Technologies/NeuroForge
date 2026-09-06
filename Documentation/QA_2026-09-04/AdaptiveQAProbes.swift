import XCTest
@testable import NeuroForge

@MainActor
final class NeuroForgeAdaptiveQAProbes: XCTestCase {
    func testQADifficultyChangesMetadataWithoutChangingQuestion() throws {
        let easy = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: 20260904, index: 0, lab: .mentalMath, purpose: .practice,
            localeIdentifier: "en", targetDifficulty: 0.2
        ))
        let hard = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: 20260904, index: 0, lab: .mentalMath, purpose: .practice,
            localeIdentifier: "en", targetDifficulty: 0.9
        ))
        XCTAssertEqual(easy.prompt, hard.prompt)
        XCTAssertEqual(easy.interaction, hard.interaction)
        XCTAssertEqual(easy.representations, hard.representations)
        XCTAssertEqual(easy.id, hard.id)
        XCTAssertEqual(easy.difficulty.overall, 0.2)
        XCTAssertEqual(hard.difficulty.overall, 0.9)
        print("QA_CONFIRMED difficulty: identical prompt, answer schema, representations and ID at targetDifficulty 0.2 and 0.9; only overall metadata differs. Prompt: \(easy.prompt)")
    }
}

import Foundation

struct NFCodeTraceStep: Equatable, Sendable {
    let lineNumber: Int
    let variables: [String: NFPseudocodeValue]
    let visitedInputIndices: [Int]
}

/// A pinned typed tree encoded separately so recursive decoding is preceded by
/// a byte/depth bound. Display source is verified against the same renderer;
/// strings from source documents and response fields are never interpreted.
struct NFCodeTraceContract: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let programData: Data
    let initialVariables: [String: NFPseudocodeValue]
    let inputCount: Int
    let displaySkin: NFPseudocodeDisplaySkin
    let source: String

    static func make(program: [NFPseudocodeStatement], initialVariables: [String: NFPseudocodeValue],
                     inputCount: Int = 0, skin: NFPseudocodeDisplaySkin) throws -> Self {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let contract = Self(programData: try encoder.encode(program), initialVariables: initialVariables,
            inputCount: inputCount, displaySkin: skin, source: NFPseudocodeRenderer.render(program, skin: skin))
        _ = try contract.steps()
        return contract
    }

    func steps() throws -> [NFCodeTraceStep] {
        guard schemaVersion == 1, programData.count <= 16_384, Self.hasBoundedJSONDepth(programData),
              !initialVariables.isEmpty, initialVariables.count <= 16,
              initialVariables.keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 64 }),
              (0...256).contains(inputCount), source.utf8.count <= 8_192 else { throw Failure.unavailable }
        let program = try JSONDecoder().decode([NFPseudocodeStatement].self, from: programData)
        guard !program.isEmpty, source == NFPseudocodeRenderer.render(program, skin: displaySkin) else { throw Failure.unavailable }
        let steps = try NFRestrictedPseudocodeInterpreter.trace(program,
            initialVariables: initialVariables, inputCount: inputCount, skin: displaySkin)
        guard !steps.isEmpty, steps.allSatisfy({ Set($0.variables.keys) == Set(initialVariables.keys) }) else { throw Failure.unavailable }
        return steps
    }

    static func hasBoundedJSONDepth(_ data: Data) -> Bool {
        var depth = 0, quoted = false, escaped = false
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 91 || byte == 123 { depth += 1; if depth > 32 { return false } }
            else if byte == 93 || byte == 125 { depth -= 1; if depth < 0 { return false } }
        }
        return depth == 0 && !quoted
    }
    enum Failure: Error { case unavailable }
}

extension NFPseudocodeValue {
    var traceText: String {
        switch self { case .integer(let value): String(value); case .boolean(let value): value ? "true" : "false" }
    }
}

/// The first prediction remains immutable, even when an inspected answer is
/// subsequently revised. Cursor changes never change the committed response.
struct NFTraceInspectionDraft: Codable, Equatable, Sendable {
    struct Event: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable { case reveal, previous, reset, selectLine }
        let kind: Kind
        let cursor: Int
        let selectedLine: Int?
    }
    struct StatePrediction: Codable, Equatable, Sendable {
        let step: Int
        let values: [String: String]
    }
    static let maximumPredictionCharacters = 500
    static let oversizedPredictionMessage = "A next-state prediction is too long to save. Use 500 characters or fewer per value, or export the current work."
    var schemaVersion = 1
    var nextStatePrediction: [String: String]? = nil
    var statePredictions: [StatePrediction]? = nil
    let exerciseDigest: String
    let prediction: NFExerciseResponse
    var cursor: Int
    var revealedStepCount: Int
    var selectedLine: Int?
    var events: [Event]

    static func begin(exercise: NFExercise, prediction: NFExerciseResponse) throws -> Self {
        guard let projection = NFCodeTraceProjection.make(exercise: exercise),
              NFExerciseResponseValidator.validate(prediction, for: exercise.interaction,
                localeIdentifier: exercise.localeIdentifier).isValid else { throw NFCodeTraceContract.Failure.unavailable }
        return Self(exerciseDigest: try NFLocalItemCheckpoint.digest(exercise), prediction: prediction,
            cursor: 1, revealedStepCount: 1, selectedLine: projection.steps[0].lineNumber,
            events: [.init(kind: .reveal, cursor: 1, selectedLine: projection.steps[0].lineNumber)])
    }
    func isValid(for exercise: NFExercise) -> Bool {
        guard schemaVersion == 1, let projection = NFCodeTraceProjection.make(exercise: exercise),
              exerciseDigest == (try? NFLocalItemCheckpoint.digest(exercise)),
              NFExerciseResponseValidator.validate(prediction, for: exercise.interaction,
                localeIdentifier: exercise.localeIdentifier).isValid,
              (1...projection.steps.count).contains(revealedStepCount), (0...revealedStepCount).contains(cursor),
              events.count <= 512, events.first?.kind == .reveal, events.first?.cursor == 1 else { return false }
        let names = Set(projection.contract.initialVariables.keys)
        guard nextStatePrediction.map({ Self.boundedStateText($0, names: names) }) ?? true,
              (statePredictions?.count ?? 0) <= 128,
              (statePredictions ?? []).allSatisfy({ (1...projection.steps.count).contains($0.step) && Self.validStatePrediction($0.values, in: projection) }) else { return false }
        let range = 1...projection.lines.count
        return (selectedLine.map(range.contains) ?? true)
            && events.allSatisfy { (0...revealedStepCount).contains($0.cursor) && ($0.selectedLine.map(range.contains) ?? true) }
    }
    mutating func next(in projection: NFCodeTraceProjection) {
        guard cursor < projection.steps.count, canAdvance(in: projection) else { return }
        if let prediction = nextStatePrediction, !prediction.values.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            var retained = statePredictions ?? []
            guard retained.count < 128 else { return }
            retained.append(.init(step: cursor + 1, values: prediction)); statePredictions = retained
            nextStatePrediction = nil
        }
        cursor += 1; revealedStepCount = max(revealedStepCount, cursor)
        selectedLine = projection.steps[cursor - 1].lineNumber
        record(.reveal)
    }
    func canAdvance(in projection: NFCodeTraceProjection) -> Bool {
        guard let pending = nextStatePrediction else { return true }
        guard Self.boundedStateText(pending, names: Set(projection.contract.initialVariables.keys)) else { return false }
        guard !pending.values.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return true }
        return (statePredictions?.count ?? 0) < 128 && Self.validStatePrediction(pending, in: projection)
    }
    mutating func predict(variable: String, value: String, in projection: NFCodeTraceProjection) {
        guard projection.contract.initialVariables[variable] != nil else { return }
        var pending = nextStatePrediction ?? [:]; pending[variable] = value; nextStatePrediction = pending
    }
    private static func boundedStateText(_ values: [String: String], names: Set<String>) -> Bool {
        values.count <= 16 && Set(values.keys).isSubset(of: names)
            && values.values.allSatisfy { $0.utf8.count <= 2_000 && $0.count <= maximumPredictionCharacters }
    }
    private static func validStatePrediction(_ values: [String: String], in projection: NFCodeTraceProjection) -> Bool {
        let names = Set(projection.contract.initialVariables.keys)
        guard Set(values.keys) == names, boundedStateText(values, names: names) else { return false }
        return values.allSatisfy { name, raw in
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            switch projection.contract.initialVariables[name] {
            case .integer: return Int(text) != nil
            case .boolean: return ["true", "false"].contains(text.lowercased())
            case nil: return false
            }
        }
    }
    func recoveryText(exercise: NFExercise) -> String {
        guard !exercise.assessmentProtected else { return "" }
        var sections = [NFResponsePresentation.text(prediction, exercise: exercise)]
        for saved in statePredictions ?? [] {
            sections.append(saved.values.keys.sorted().map { "\($0): \(saved.values[$0] ?? "")" }.joined(separator: ", "))
        }
        if let pending = nextStatePrediction {
            sections.append(pending.keys.sorted().map { "\($0): \(pending[$0] ?? "")" }.joined(separator: ", "))
        }
        return sections.joined(separator: "\n\n")
    }

    mutating func previous() { guard cursor > 0 else { return }; cursor -= 1; record(.previous) }
    mutating func reset() { cursor = 0; selectedLine = nil; record(.reset) }
    mutating func select(line: Int, in projection: NFCodeTraceProjection) {
        guard (1...projection.lines.count).contains(line) else { return }; selectedLine = line; record(.selectLine)
    }
    private mutating func record(_ kind: Event.Kind) {
        // Bound repeated presentation actions; the monotonic maximum and first
        // prediction remain authoritative even after the detail log fills.
        if events.count < 512 { events.append(.init(kind: kind, cursor: cursor, selectedLine: selectedLine)) }
    }
}

struct NFCodeTraceProjection: Sendable {
    let contract: NFCodeTraceContract
    let steps: [NFCodeTraceStep]
    var lines: [String] { contract.source.components(separatedBy: "\n") }
    static func make(exercise: NFExercise) -> Self? {
        guard !exercise.assessmentProtected, case let .logicState(schema) = exercise.interaction,
              let contract = exercise.independentRepresentations.compactMap({ representation -> NFCodeTraceContract? in
                  guard case let .logicState(metadata) = representation else { return nil }; return metadata.traceContract
              }).first,
              let steps = try? contract.steps(),
              schema.initialState == contract.initialVariables.mapValues(\.traceText),
              exercise.independentRepresentations.contains(where: { representation in
                  guard case let .code(_, source, _) = representation else { return false }; return source == contract.source
              }) else { return nil }
        return Self(contract: contract, steps: steps)
    }
    func variables(at cursor: Int) -> [String: NFPseudocodeValue] {
        guard cursor > 0, steps.indices.contains(cursor - 1) else { return contract.initialVariables }
        return steps[cursor - 1].variables
    }
    func changedVariables(at cursor: Int) -> [String] {
        let current = variables(at: cursor), previous = variables(at: max(0, cursor - 1))
        return current.keys.sorted().filter { current[$0] != previous[$0] }
    }
}

extension NFExercise {
    var hasSupportedTraceContract: Bool {
        let contracts = representations.compactMap { representation -> NFCodeTraceContract? in
            guard case let .logicState(metadata) = representation else { return nil }; return metadata.traceContract
        }
        guard !contracts.isEmpty else { return true }
        guard contracts.count == 1, let projection = NFCodeTraceProjection.make(exercise: self),
              case let .logicState(schema) = interaction else { return false }
        return projection.steps.last?.variables.mapValues(\.traceText) == schema.expectedFinalState
    }
}

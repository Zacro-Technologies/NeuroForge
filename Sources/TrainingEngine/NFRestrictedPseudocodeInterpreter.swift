import Foundation

/// A deliberately small, typed interpreter used to validate bundled debugging
/// exercises. It executes only values and operations represented by this AST;
/// user text and imported source code are never parsed or evaluated.
enum NFPseudocodeValue: Codable, Equatable, Sendable {
    case integer(Int)
    case boolean(Bool)
}

indirect enum NFPseudocodeExpression: Codable, Equatable, Sendable {
    case value(NFPseudocodeValue)
    case variable(String)
    case inputCount
    case add(NFPseudocodeExpression, NFPseudocodeExpression)
    case subtract(NFPseudocodeExpression, NFPseudocodeExpression)
    case lessThan(NFPseudocodeExpression, NFPseudocodeExpression)
    case lessThanOrEqual(NFPseudocodeExpression, NFPseudocodeExpression)
    case equal(NFPseudocodeExpression, NFPseudocodeExpression)
    case not(NFPseudocodeExpression)
}

indirect enum NFPseudocodeStatement: Codable, Equatable, Sendable {
    case assign(name: String, expression: NFPseudocodeExpression)
    case ifThen(condition: NFPseudocodeExpression, body: [NFPseudocodeStatement])
    case whileLoop(condition: NFPseudocodeExpression, iterationLimit: Int, body: [NFPseudocodeStatement])
    case visitInput(index: NFPseudocodeExpression)
}

/// Pure presentation skins over the restricted AST. A skin is never parsed
/// back into executable code; the interpreter and scorer continue to consume
/// only the typed tree above.
enum NFPseudocodeDisplaySkin: String, Codable, CaseIterable, Sendable {
    case languageNeutral = "language-neutral"
    case pythonLike = "python-like"
    case javaScriptLike = "javascript-like"
    case swiftLike = "swift-like"
}

enum NFPseudocodeRenderer {
    static func render(
        _ statements: [NFPseudocodeStatement],
        skin: NFPseudocodeDisplaySkin
    ) -> String {
        render(statements, skin: skin, indentation: 0).joined(separator: "\n")
    }

    private static func render(
        _ statements: [NFPseudocodeStatement],
        skin: NFPseudocodeDisplaySkin,
        indentation: Int
    ) -> [String] {
        statements.flatMap { statement in
            render(statement, skin: skin, indentation: indentation)
        }
    }

    private static func render(
        _ statement: NFPseudocodeStatement,
        skin: NFPseudocodeDisplaySkin,
        indentation: Int
    ) -> [String] {
        let prefix = String(repeating: skin == .pythonLike ? "    " : "  ", count: indentation)
        switch statement {
        case let .assign(name, expression):
            let rendered = render(expression, skin: skin)
            switch skin {
            case .languageNeutral: return ["\(prefix)SET \(name) TO \(rendered)"]
            case .pythonLike, .swiftLike: return ["\(prefix)\(name) = \(rendered)"]
            case .javaScriptLike: return ["\(prefix)\(name) = \(rendered);"]
            }

        case let .ifThen(condition, body):
            let rendered = render(condition, skin: skin)
            switch skin {
            case .languageNeutral:
                return ["\(prefix)IF \(rendered) THEN"]
                    + render(body, skin: skin, indentation: indentation + 1)
                    + ["\(prefix)END IF"]
            case .pythonLike:
                return ["\(prefix)if \(rendered):"]
                    + render(body, skin: skin, indentation: indentation + 1)
            case .javaScriptLike, .swiftLike:
                return ["\(prefix)if (\(rendered)) {"]
                    + render(body, skin: skin, indentation: indentation + 1)
                    + ["\(prefix)}"]
            }

        case let .whileLoop(condition, _, body):
            let rendered = render(condition, skin: skin)
            switch skin {
            case .languageNeutral:
                return ["\(prefix)WHILE \(rendered) DO"]
                    + render(body, skin: skin, indentation: indentation + 1)
                    + ["\(prefix)END WHILE"]
            case .pythonLike:
                return ["\(prefix)while \(rendered):"]
                    + render(body, skin: skin, indentation: indentation + 1)
            case .javaScriptLike, .swiftLike:
                return ["\(prefix)while (\(rendered)) {"]
                    + render(body, skin: skin, indentation: indentation + 1)
                    + ["\(prefix)}"]
            }

        case let .visitInput(index):
            let rendered = render(index, skin: skin)
            switch skin {
            case .languageNeutral: return ["\(prefix)VISIT INPUT[\(rendered)]"]
            case .pythonLike, .swiftLike: return ["\(prefix)visit(input[\(rendered)])"]
            case .javaScriptLike: return ["\(prefix)visit(input[\(rendered)]);"]
            }
        }
    }

    private static func render(
        _ expression: NFPseudocodeExpression,
        skin: NFPseudocodeDisplaySkin
    ) -> String {
        switch expression {
        case let .value(.integer(value)):
            return String(value)
        case let .value(.boolean(value)):
            switch skin {
            case .languageNeutral: return value ? "TRUE" : "FALSE"
            case .pythonLike: return value ? "True" : "False"
            case .javaScriptLike, .swiftLike: return value ? "true" : "false"
            }
        case let .variable(name):
            return name
        case .inputCount:
            switch skin {
            case .languageNeutral: return "INPUT_COUNT"
            case .pythonLike: return "len(input)"
            case .javaScriptLike: return "input.length"
            case .swiftLike: return "input.count"
            }
        case let .add(lhs, rhs):
            return binary(lhs, "+", rhs, skin: skin)
        case let .subtract(lhs, rhs):
            return binary(lhs, "-", rhs, skin: skin)
        case let .lessThan(lhs, rhs):
            return binary(lhs, "<", rhs, skin: skin)
        case let .lessThanOrEqual(lhs, rhs):
            return binary(lhs, "<=", rhs, skin: skin)
        case let .equal(lhs, rhs):
            let operation = skin == .languageNeutral ? "=" : (skin == .javaScriptLike ? "===" : "==")
            return binary(lhs, operation, rhs, skin: skin)
        case let .not(value):
            let rendered = render(value, skin: skin)
            switch skin {
            case .languageNeutral: return "NOT (\(rendered))"
            case .pythonLike: return "not (\(rendered))"
            case .javaScriptLike, .swiftLike: return "!(\(rendered))"
            }
        }
    }

    private static func binary(
        _ lhs: NFPseudocodeExpression,
        _ operation: String,
        _ rhs: NFPseudocodeExpression,
        skin: NFPseudocodeDisplaySkin
    ) -> String {
        "\(render(lhs, skin: skin)) \(operation) \(render(rhs, skin: skin))"
    }
}

enum NFPseudocodeRuntimeError: Error, Equatable, Sendable {
    case unknownVariable(String)
    case expectedInteger
    case expectedBoolean
    case inputIndexOutOfBounds(Int)
    case invalidIterationLimit
    case iterationLimitExceeded
    case operationBudgetExceeded
    case integerOverflow
}

struct NFPseudocodeExecutionResult: Equatable, Sendable {
    let variables: [String: NFPseudocodeValue]
    let visitedInputIndices: [Int]

    func integer(named name: String) -> Int? {
        guard case let .integer(value) = variables[name] else { return nil }
        return value
    }

    func boolean(named name: String) -> Bool? {
        guard case let .boolean(value) = variables[name] else { return nil }
        return value
    }
}

enum NFRestrictedPseudocodeInterpreter {
    static func execute(
        _ statements: [NFPseudocodeStatement],
        initialVariables: [String: NFPseudocodeValue] = [:],
        inputCount: Int = 0,
        operationBudget: Int = 10_000
    ) throws -> NFPseudocodeExecutionResult {
        var machine = Machine(
            variables: initialVariables,
            inputCount: max(0, inputCount),
            visitedInputIndices: [],
            remainingOperationBudget: max(1, operationBudget)
        )
        try run(statements, machine: &machine)
        return NFPseudocodeExecutionResult(
            variables: machine.variables,
            visitedInputIndices: machine.visitedInputIndices
        )
    }

    /// Uses the same evaluator and mutation semantics as execute; only the
    /// bounded recorder is additional. No user-authored source is evaluated.
    static func trace(_ statements: [NFPseudocodeStatement],
                      initialVariables: [String: NFPseudocodeValue], inputCount: Int,
                      skin: NFPseudocodeDisplaySkin) throws -> [NFCodeTraceStep] {
        var machine = Machine(variables: initialVariables, inputCount: inputCount,
            visitedInputIndices: [], remainingOperationBudget: 512)
        var steps: [NFCodeTraceStep] = []
        try traceRun(statements, machine: &machine, line: 1, skin: skin, steps: &steps)
        let actual = try execute(statements, initialVariables: initialVariables, inputCount: inputCount, operationBudget: 512)
        guard actual.variables == machine.variables, actual.visitedInputIndices == machine.visitedInputIndices else {
            throw NFPseudocodeRuntimeError.operationBudgetExceeded
        }
        return steps
    }

    private static func traceRun(_ statements: [NFPseudocodeStatement], machine: inout Machine,
                                 line firstLine: Int, skin: NFPseudocodeDisplaySkin,
                                 steps: inout [NFCodeTraceStep]) throws {
        var line = firstLine
        for statement in statements {
            try consumeOperation(machine: &machine)
            switch statement {
            case let .assign(name, expression):
                machine.variables[name] = try evaluate(expression, machine: machine)
                try appendTrace(line: line, machine: machine, steps: &steps)
            case let .ifThen(condition, body):
                let proceeds = try boolean(evaluate(condition, machine: machine))
                try appendTrace(line: line, machine: machine, steps: &steps)
                if proceeds { try traceRun(body, machine: &machine, line: line + 1, skin: skin, steps: &steps) }
            case let .whileLoop(condition, limit, body):
                guard limit > 0 else { throw NFPseudocodeRuntimeError.invalidIterationLimit }
                var iterations = 0
                while true {
                    let proceeds = try boolean(evaluate(condition, machine: machine))
                    try appendTrace(line: line, machine: machine, steps: &steps)
                    if !proceeds { break }
                    guard iterations < limit else { throw NFPseudocodeRuntimeError.iterationLimitExceeded }
                    iterations += 1
                    try traceRun(body, machine: &machine, line: line + 1, skin: skin, steps: &steps)
                    try consumeOperation(machine: &machine)
                }
            case let .visitInput(expression):
                let index = try integer(evaluate(expression, machine: machine))
                guard (0..<machine.inputCount).contains(index) else { throw NFPseudocodeRuntimeError.inputIndexOutOfBounds(index) }
                machine.visitedInputIndices.append(index)
                try appendTrace(line: line, machine: machine, steps: &steps)
            }
            line += NFPseudocodeRenderer.render([statement], skin: skin).components(separatedBy: "\n").count
        }
    }
    private static func appendTrace(line: Int, machine: Machine, steps: inout [NFCodeTraceStep]) throws {
        guard steps.count < 128, machine.variables.count <= 16 else { throw NFPseudocodeRuntimeError.operationBudgetExceeded }
        steps.append(NFCodeTraceStep(lineNumber: line, variables: machine.variables, visitedInputIndices: machine.visitedInputIndices))
    }

    private struct Machine {
        var variables: [String: NFPseudocodeValue]
        let inputCount: Int
        var visitedInputIndices: [Int]
        var remainingOperationBudget: Int
    }

    private static func run(
        _ statements: [NFPseudocodeStatement],
        machine: inout Machine
    ) throws {
        for statement in statements {
            try consumeOperation(machine: &machine)
            switch statement {
            case let .assign(name, expression):
                machine.variables[name] = try evaluate(expression, machine: machine)

            case let .ifThen(condition, body):
                if try boolean(evaluate(condition, machine: machine)) {
                    try run(body, machine: &machine)
                }

            case let .whileLoop(condition, iterationLimit, body):
                guard iterationLimit > 0 else { throw NFPseudocodeRuntimeError.invalidIterationLimit }
                var iterations = 0
                while try boolean(evaluate(condition, machine: machine)) {
                    guard iterations < iterationLimit else {
                        throw NFPseudocodeRuntimeError.iterationLimitExceeded
                    }
                    iterations += 1
                    try run(body, machine: &machine)
                    try consumeOperation(machine: &machine)
                }

            case let .visitInput(indexExpression):
                let index = try integer(evaluate(indexExpression, machine: machine))
                guard (0..<machine.inputCount).contains(index) else {
                    throw NFPseudocodeRuntimeError.inputIndexOutOfBounds(index)
                }
                machine.visitedInputIndices.append(index)
            }
        }
    }

    private static func evaluate(
        _ expression: NFPseudocodeExpression,
        machine: Machine
    ) throws -> NFPseudocodeValue {
        switch expression {
        case let .value(value):
            return value
        case let .variable(name):
            guard let value = machine.variables[name] else {
                throw NFPseudocodeRuntimeError.unknownVariable(name)
            }
            return value
        case .inputCount:
            return .integer(machine.inputCount)
        case let .add(lhs, rhs):
            let (value, overflow) = try integer(evaluate(lhs, machine: machine)).addingReportingOverflow(integer(evaluate(rhs, machine: machine)))
            guard !overflow else { throw NFPseudocodeRuntimeError.integerOverflow }
            return .integer(value)
        case let .subtract(lhs, rhs):
            let (value, overflow) = try integer(evaluate(lhs, machine: machine)).subtractingReportingOverflow(integer(evaluate(rhs, machine: machine)))
            guard !overflow else { throw NFPseudocodeRuntimeError.integerOverflow }
            return .integer(value)
        case let .lessThan(lhs, rhs):
            return .boolean(try integer(evaluate(lhs, machine: machine)) < integer(evaluate(rhs, machine: machine)))
        case let .lessThanOrEqual(lhs, rhs):
            return .boolean(try integer(evaluate(lhs, machine: machine)) <= integer(evaluate(rhs, machine: machine)))
        case let .equal(lhs, rhs):
            return .boolean(try evaluate(lhs, machine: machine) == evaluate(rhs, machine: machine))
        case let .not(value):
            return .boolean(try !boolean(evaluate(value, machine: machine)))
        }
    }

    private static func integer(_ value: NFPseudocodeValue) throws -> Int {
        guard case let .integer(integer) = value else {
            throw NFPseudocodeRuntimeError.expectedInteger
        }
        return integer
    }

    private static func boolean(_ value: NFPseudocodeValue) throws -> Bool {
        guard case let .boolean(boolean) = value else {
            throw NFPseudocodeRuntimeError.expectedBoolean
        }
        return boolean
    }

    private static func consumeOperation(machine: inout Machine) throws {
        guard machine.remainingOperationBudget > 0 else {
            throw NFPseudocodeRuntimeError.operationBudgetExceeded
        }
        machine.remainingOperationBudget -= 1
    }
}

import Foundation
import Security
#if canImport(FoundationModels)
import FoundationModels
#endif

enum NFAILearningTask: String, Codable, Sendable {
    case grading
    case tutoring
    case generation
}

enum NFAILearningRoute: String, Codable, Sendable {
    case local
    case cloud
}

struct NFAICompletionRequest: Sendable {
    let id: UUID
    let task: NFAILearningTask
    let instructions: String
    let input: String
    let jsonSchema: String?
    let maxOutputTokens: Int
    let localeIdentifier: String?

    init(
        id: UUID = UUID(), task: NFAILearningTask, instructions: String, input: String,
        jsonSchema: String? = nil, maxOutputTokens: Int = 1_024, localeIdentifier: String? = nil
    ) {
        self.id = id
        self.task = task
        self.instructions = instructions
        self.input = input
        self.jsonSchema = jsonSchema
        self.maxOutputTokens = maxOutputTokens
        self.localeIdentifier = localeIdentifier
    }
}

/// Persist accepted results for replay. Running the same request again is a new inference.
struct NFAICompletionResult: Codable, Equatable, Sendable {
    let requestID: UUID
    let text: String
    let providerIdentifier: String
    let modelIdentifier: String
    let route: NFAILearningRoute
    let generatedAt: Date
}

struct NFAILearningAvailability: Equatable, Sendable {
    let isAvailable: Bool
    let route: NFAILearningRoute?
    let status: String
    let localAvailable: Bool
    let cloudConfigured: Bool
}

struct NFAICloudConfiguration: Codable, Equatable, Sendable {
    /// A full HTTPS Chat Completions endpoint, including its path.
    let endpoint: URL
    let model: String
    let providerName: String

    init(endpoint: URL, model: String, providerName: String = "Cloud AI") {
        self.endpoint = endpoint
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.providerName = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum NFAILearningError: Error, LocalizedError, Equatable, Sendable {
    case disabled
    case notConfigured
    case invalidConfiguration
    case credentialRequired
    case credentialStorage(OSStatus)
    case localUnavailable(String)
    case inputTooLarge
    case invalidSchema
    case unsupportedSchema
    case outputTooLarge
    case invalidResponse
    case incompleteResponse
    case refused
    case authentication
    case rateLimited
    case serverUnavailable(Int)
    case timedOut
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .disabled: "AI is turned off."
        case .notConfigured: "Set up a cloud provider or enable an available on-device model."
        case .invalidConfiguration: "Enter a full HTTPS Chat Completions endpoint and a model name."
        case .credentialRequired: "Enter an API key for this endpoint."
        case .credentialStorage: "The saved AI provider could not be accessed. Try saving it again."
        case .localUnavailable(let reason): reason
        case .inputTooLarge: "This request is too large for the selected AI route. Use a shorter passage."
        case .invalidSchema, .unsupportedSchema: "This AI response format is not supported."
        case .outputTooLarge: "The AI response exceeded the supported size. Try again with a smaller request."
        case .invalidResponse: "The AI response did not match the expected format. Try again."
        case .incompleteResponse: "The AI response was incomplete. Try again."
        case .refused: "The model could not complete this request. Try rephrasing it."
        case .authentication: "The provider did not accept the API key or model access. Check its settings."
        case .rateLimited: "The provider is at its current usage limit. Try again later."
        case .serverUnavailable: "The provider could not complete the request. Try again later."
        case .timedOut: "The AI request took too long. Your response is still available to retry."
        case .connectionFailed: "The AI provider could not be reached. Check your connection or use on-device AI."
        }
    }
}

/// Configuration and its credential are one atomic Keychain record. No token enters defaults.
struct NFAIStoredCloudCredentials: Codable, Sendable {
    let configuration: NFAICloudConfiguration
    let apiKey: String
}

protocol NFAICloudCredentialStore: Sendable {
    func read() async throws -> NFAIStoredCloudCredentials?
    func write(_ credentials: NFAIStoredCloudCredentials) async throws
    func delete() async throws
}

struct NFAIHTTPResponse: Sendable {
    let statusCode: Int
    let data: Data
}

protocol NFAIHTTPTransport: Sendable {
    func send(_ request: URLRequest, maximumResponseBytes: Int) async throws -> NFAIHTTPResponse
}

struct NFAILocalAvailability: Equatable, Sendable {
    let isAvailable: Bool
    let status: String
}

protocol NFAILocalModelProvider: Sendable {
    func availability() async -> NFAILocalAvailability
    func complete(_ request: NFAICompletionRequest) async throws -> NFAICompletionResult
}

struct NFKeychainAICloudCredentialStore: NFAICloudCredentialStore {
    private let service = "com.zacrotech.NeuroForge.learning-ai"
    private let account = "cloud-provider-v1"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func read() async throws -> NFAIStoredCloudCredentials? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw NFAILearningError.credentialStorage(status)
        }
        do { return try JSONDecoder().decode(NFAIStoredCloudCredentials.self, from: data) }
        catch { throw NFAILearningError.credentialStorage(errSecDecode) }
    }

    func write(_ credentials: NFAIStoredCloudCredentials) async throws {
        let data = try JSONEncoder().encode(credentials)
        let changes = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NFAILearningError.credentialStorage(status) }
    }

    func delete() async throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NFAILearningError.credentialStorage(status)
        }
    }
}

/// A request owns its session, so timeout, cancellation and a size rejection close the body stream.
struct NFURLSessionAIHTTPTransport: NFAIHTTPTransport {
    func send(_ request: URLRequest, maximumResponseBytes: Int) async throws -> NFAIHTTPResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: NFNoAIRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw NFAILearningError.invalidResponse }
        guard response.expectedContentLength <= Int64(maximumResponseBytes) else {
            throw NFAILearningError.outputTooLarge
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumResponseBytes else { throw NFAILearningError.outputTooLarge }
            data.append(byte)
        }
        return NFAIHTTPResponse(statusCode: response.statusCode, data: data)
    }
}

private final class NFNoAIRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // An endpoint change belongs in configuration; never forward a saved key through a redirect.
        completionHandler(nil)
    }
}

actor NFAILearningService {
    static let shared = NFAILearningService()
    static let maximumInputBytes = 96_000
    static let maximumOutputBytes = 64_000
    static let maximumHTTPResponseBytes = 512_000

    private let credentialStore: any NFAICloudCredentialStore
    private let transport: any NFAIHTTPTransport
    private let localProvider: any NFAILocalModelProvider
    private let timeout: Duration

    init(
        credentialStore: any NFAICloudCredentialStore = NFKeychainAICloudCredentialStore(),
        transport: any NFAIHTTPTransport = NFURLSessionAIHTTPTransport(),
        localProvider: any NFAILocalModelProvider = NFFoundationModelsLearningProvider(),
        timeout: Duration = .seconds(30)
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
        self.localProvider = localProvider
        self.timeout = timeout
    }

    func configuration() async throws -> NFAICloudConfiguration? {
        try await credentialStore.read()?.configuration
    }

    func hasSavedCredential() async throws -> Bool {
        guard let saved = try await credentialStore.read() else { return false }
        return !saved.apiKey.isEmpty
    }

    func saveConfiguration(_ configuration: NFAICloudConfiguration, apiKey: String?) async throws {
        try Self.validate(configuration)
        let suppliedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key: String
        if let suppliedKey, !suppliedKey.isEmpty {
            key = suppliedKey
        } else if let saved = try await credentialStore.read(), saved.configuration.endpoint == configuration.endpoint {
            key = saved.apiKey
        } else {
            throw NFAILearningError.credentialRequired
        }
        guard !key.isEmpty, key.utf8.count <= 8_192,
              !key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw NFAILearningError.credentialRequired
        }
        try await credentialStore.write(.init(configuration: configuration, apiKey: key))
    }

    func deleteConfiguration() async throws {
        try await credentialStore.delete()
    }

    /// User-initiated only: this sends one small API request to the saved provider.
    func testConfiguration() async throws -> NFAICompletionResult {
        guard let credentials = try await credentialStore.read(), !credentials.apiKey.isEmpty else {
            throw NFAILearningError.notConfigured
        }
        let request = NFAICompletionRequest(
            task: .tutoring, instructions: "Reply with only the word Ready.",
            input: "Check the connection.", maxOutputTokens: 64
        )
        return try await perform(request, credentials: credentials, permitsOfflineFallback: false)
    }

    func availability(mode: AIMode) async -> NFAILearningAvailability {
        let local = await localProvider.availability()
        let saved: NFAIStoredCloudCredentials?
        do { saved = try await credentialStore.read() }
        catch {
            return .init(isAvailable: mode == .onDeviceOnly && local.isAvailable,
                         route: mode == .onDeviceOnly && local.isAvailable ? .local : nil,
                         status: mode == .disabled ? "AI is turned off." : mode == .onDeviceOnly ? local.status : "The saved AI provider could not be accessed. Try saving it again.",
                         localAvailable: local.isAvailable, cloudConfigured: false)
        }
        let configured = saved.map { (try? Self.validate($0.configuration)) != nil && !$0.apiKey.isEmpty } ?? false
        if mode == .disabled {
            return .init(isAvailable: false, route: nil, status: "AI is turned off.",
                         localAvailable: local.isAvailable, cloudConfigured: configured)
        }
        if mode == .automatic, configured {
            return .init(isAvailable: true, route: .cloud,
                         status: "Cloud AI is configured. A connection is required; use Check connection to verify it.",
                         localAvailable: local.isAvailable, cloudConfigured: true)
        }
        return .init(isAvailable: local.isAvailable, route: local.isAvailable ? .local : nil,
                     status: local.status, localAvailable: local.isAvailable, cloudConfigured: configured)
    }

    func complete(_ request: NFAICompletionRequest, mode: AIMode) async throws -> NFAICompletionResult {
        try Task.checkCancellation()
        guard mode != .disabled else { throw NFAILearningError.disabled }
        try Self.validate(request)
        let credentials = mode == .automatic ? try await credentialStore.read() : nil
        return try await perform(request, credentials: credentials, permitsOfflineFallback: mode == .automatic)
    }

    private func perform(
        _ request: NFAICompletionRequest, credentials: NFAIStoredCloudCredentials?, permitsOfflineFallback: Bool
    ) async throws -> NFAICompletionResult {
        try Task.checkCancellation()
        try Self.validate(request)
        let transport = self.transport
        let local = self.localProvider
        let timeout = self.timeout
        do {
            let result = try await withThrowingTaskGroup(of: NFAICompletionResult.self) { group in
                group.addTask {
                    if let credentials {
                        do {
                            return try await Self.cloudCompletion(request, credentials: credentials, transport: transport)
                        } catch let error as URLError where permitsOfflineFallback && Self.canUseOfflineFallback(error) {
                            try Task.checkCancellation()
                            guard await local.availability().isAvailable else { throw error }
                            return try await local.complete(request)
                        }
                    }
                    return try await local.complete(request)
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw NFAILearningError.timedOut
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw CancellationError() }
                return first
            }
            try Task.checkCancellation()
            guard result.requestID == request.id else { throw NFAILearningError.invalidResponse }
            try Self.validateOutput(result.text, schema: request.jsonSchema)
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as NFAILearningError {
            throw error
        } catch let error as URLError {
            if Task.isCancelled || error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? NFAILearningError.timedOut : NFAILearningError.connectionFailed
        } catch {
            throw NFAILearningError.invalidResponse
        }
    }

    private static func canUseOfflineFallback(_ error: URLError) -> Bool {
        // These failures occur before a usable connection. Timeout and a dropped connection
        // have an unknown remote outcome and must remain explicit retries for the learner.
        [.notConnectedToInternet, .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost,
         .internationalRoamingOff, .dataNotAllowed].contains(error.code)
    }

    private static func validate(_ configuration: NFAICloudConfiguration) throws {
        guard configuration.endpoint.scheme?.lowercased() == "https",
              let host = configuration.endpoint.host, !host.isEmpty,
              configuration.endpoint.user == nil, configuration.endpoint.password == nil,
              configuration.endpoint.fragment == nil, configuration.endpoint.query == nil,
              !configuration.endpoint.path.isEmpty,
              !configuration.model.isEmpty, configuration.model.utf8.count <= 256,
              !configuration.providerName.isEmpty, configuration.providerName.utf8.count <= 128 else {
            throw NFAILearningError.invalidConfiguration
        }
    }

    private static func validate(_ request: NFAICompletionRequest) throws {
        guard (1...4_096).contains(request.maxOutputTokens), !request.instructions.isEmpty, !request.input.isEmpty,
              request.instructions.utf8.count + request.input.utf8.count <= maximumInputBytes else {
            throw NFAILearningError.inputTooLarge
        }
        if let schema = request.jsonSchema { _ = try NFAILearningJSONSchema.parse(schema) }
    }

    private static func validateOutput(_ text: String, schema: String?) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NFAILearningError.invalidResponse
        }
        guard text.utf8.count <= maximumOutputBytes else { throw NFAILearningError.outputTooLarge }
        if let schema {
            let definition = try NFAILearningJSONSchema.parse(schema)
            guard let data = text.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  NFAILearningJSONSchema.matches(value, definition: definition) else {
                throw NFAILearningError.invalidResponse
            }
        }
    }

    private static func cloudCompletion(
        _ request: NFAICompletionRequest, credentials: NFAIStoredCloudCredentials,
        transport: any NFAIHTTPTransport
    ) async throws -> NFAICompletionResult {
        try validate(credentials.configuration)
        var http = URLRequest(url: credentials.configuration.endpoint, timeoutInterval: 30)
        http.httpMethod = "POST"
        http.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue(request.id.uuidString, forHTTPHeaderField: "X-Client-Request-Id")
        http.httpBody = try cloudBody(request, configuration: credentials.configuration)
        let response = try await transport.send(http, maximumResponseBytes: maximumHTTPResponseBytes)
        guard response.data.count <= maximumHTTPResponseBytes else { throw NFAILearningError.outputTooLarge }
        switch response.statusCode {
        case 200...299: break
        case 401, 403: throw NFAILearningError.authentication
        case 429: throw NFAILearningError.rateLimited
        default: throw NFAILearningError.serverUnavailable(response.statusCode)
        }
        let completion: NFCloudChatCompletion
        do { completion = try JSONDecoder().decode(NFCloudChatCompletion.self, from: response.data) }
        catch { throw NFAILearningError.invalidResponse }
        guard let choice = completion.choices.first else { throw NFAILearningError.invalidResponse }
        guard choice.message.refusal?.isEmpty != false else { throw NFAILearningError.refused }
        guard choice.finishReason == "stop" else { throw NFAILearningError.incompleteResponse }
        guard let text = choice.message.content, !completion.model.isEmpty, completion.model.utf8.count <= 256 else {
            throw NFAILearningError.invalidResponse
        }
        return .init(requestID: request.id, text: text,
                     providerIdentifier: credentials.configuration.endpoint.absoluteString,
                     modelIdentifier: completion.model, route: .cloud, generatedAt: Date())
    }

    private static func cloudBody(_ request: NFAICompletionRequest, configuration: NFAICloudConfiguration) throws -> Data {
        // OpenAI-compatible Chat Completions: non-streamed text, max_completion_tokens and
        // optional strict json_schema. Compatibility depends on the user's endpoint/model.
        // https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": [["role": "system", "content": request.instructions],
                         ["role": "user", "content": request.input]],
            "max_completion_tokens": request.maxOutputTokens,
            "stream": false
        ]
        if let schema = request.jsonSchema {
            body["response_format"] = ["type": "json_schema", "json_schema": [
                "name": "neuroforge_\(request.task.rawValue)", "strict": true,
                "schema": try NFAILearningJSONSchema.parse(schema)
            ]]
        }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}

private struct NFCloudChatCompletion: Decodable {
    let model: String
    let choices: [Choice]
    struct Choice: Decodable {
        let message: Message
        let finishReason: String
        enum CodingKeys: String, CodingKey { case message; case finishReason = "finish_reason" }
    }
    struct Message: Decodable {
        let content: String?
        let refusal: String?
    }
}

struct NFFoundationModelsLearningProvider: NFAILocalModelProvider {
    func availability() async -> NFAILocalAvailability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .init(isAvailable: true, status: "On-device AI is ready and works offline.")
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .init(isAvailable: false, status: "This device does not support Apple's on-device model.")
            case .appleIntelligenceNotEnabled:
                return .init(isAvailable: false, status: "Enable Apple Intelligence in system settings to use on-device AI.")
            case .modelNotReady:
                return .init(isAvailable: false, status: "The on-device model is still downloading or preparing. Try again when it is ready.")
            @unknown default:
                return .init(isAvailable: false, status: "The on-device model is currently unavailable.")
            }
        }
        #else
        return .init(isAvailable: false, status: "On-device AI is not supported on this system.")
        #endif
    }

    func complete(_ request: NFAICompletionRequest) async throws -> NFAICompletionResult {
        let status = await availability()
        guard status.isAvailable else { throw NFAILearningError.localUnavailable(status.status) }
        try Task.checkCancellation()
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        let locale = request.localeIdentifier.map(Locale.init(identifier:)) ?? .current
        guard model.supportsLocale(locale) else {
            throw NFAILearningError.localUnavailable("The on-device model does not support this language. Try a configured cloud provider.")
        }
        let session = LanguageModelSession(model: model, instructions: request.instructions)
        let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: request.maxOutputTokens)
        let schema: GenerationSchema?
        if let json = request.jsonSchema {
            let definition = try NFAILearningJSONSchema.parse(json)
            schema = try GenerationSchema(root: Self.dynamicSchema(definition, name: "LearningResponse"), dependencies: [])
        } else {
            schema = nil
        }
        do {
            // Account for instructions, schema and requested output before sending an oversized local task.
            let promptTokens = try await model.tokenCount(for: request.input)
            let instructionTokens = try await model.tokenCount(for: Instructions(request.instructions))
            let schemaTokens: Int
            if let schema { schemaTokens = try await model.tokenCount(for: schema) }
            else { schemaTokens = 0 }
            guard promptTokens + instructionTokens + schemaTokens + request.maxOutputTokens + 128 <= model.contextSize else {
                throw NFAILearningError.inputTooLarge
            }
            let text: String
            if let schema {
                text = try await session.respond(to: request.input, schema: schema, options: options).content.jsonString
            } else {
                text = try await session.respond(to: request.input, options: options).content
            }
            try Task.checkCancellation()
            return .init(requestID: request.id, text: text,
                         providerIdentifier: "apple.foundation-models",
                         modelIdentifier: "SystemLanguageModel.default", route: .local, generatedAt: Date())
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: throw NFAILearningError.inputTooLarge
            case .assetsUnavailable: throw NFAILearningError.localUnavailable("The on-device model is currently unavailable.")
            case .guardrailViolation, .refusal: throw NFAILearningError.refused
            case .rateLimited, .concurrentRequests: throw NFAILearningError.rateLimited
            case .unsupportedLanguageOrLocale:
                throw NFAILearningError.localUnavailable("The on-device model does not support this language. Try a configured cloud provider.")
            case .unsupportedGuide: throw NFAILearningError.unsupportedSchema
            case .decodingFailure: throw NFAILearningError.invalidResponse
            @unknown default: throw NFAILearningError.invalidResponse
            }
        }
        #else
        throw NFAILearningError.localUnavailable(status.status)
        #endif
    }

    #if canImport(FoundationModels)
    private static func dynamicSchema(_ definition: [String: Any], name: String) throws -> DynamicGenerationSchema {
        let description = definition["description"] as? String
        if let choices = definition["enum"] as? [String], !choices.isEmpty {
            return .init(name: name, description: description, anyOf: choices)
        }
        if let choices = definition["anyOf"] as? [[String: Any]] {
            return .init(name: name, description: description, anyOf: try choices.enumerated().map {
                try dynamicSchema($0.element, name: "\(name)Choice\($0.offset)")
            })
        }
        if let types = definition["type"] as? [String] {
            return .init(name: name, description: description, anyOf: try types.enumerated().map { index, type in
                var variant = definition
                variant["type"] = type
                return try dynamicSchema(variant, name: "\(name)Choice\(index)")
            })
        }
        switch definition["type"] as? String {
        case "object":
            let properties = definition["properties"] as? [String: [String: Any]] ?? [:]
            let required = Set(definition["required"] as? [String] ?? [])
            return .init(name: name, description: description, properties: try properties.keys.sorted().map { key in
                .init(name: key, description: properties[key]?["description"] as? String,
                      schema: try dynamicSchema(properties[key] ?? [:], name: "\(name)_\(key)"),
                      isOptional: !required.contains(key))
            })
        case "array":
            guard let items = definition["items"] as? [String: Any] else { throw NFAILearningError.unsupportedSchema }
            return .init(arrayOf: try dynamicSchema(items, name: "\(name)Item"),
                         minimumElements: definition["minItems"] as? Int,
                         maximumElements: definition["maxItems"] as? Int)
        case "string": return .init(type: String.self)
        case "number": return .init(type: Double.self)
        case "integer": return .init(type: Int.self)
        case "boolean": return .init(type: Bool.self)
        case "null": return .null
        default: throw NFAILearningError.unsupportedSchema
        }
    }
    #endif
}

/// Deliberately bounded schema subset shared by local generation and cloud result validation.
/// Callers still validate domain semantics, rubric totals and evaluator capability before accepting a grade.
private enum NFAILearningJSONSchema {
    static func parse(_ text: String) throws -> [String: Any] {
        guard text.utf8.count <= 32_000,
              let definition = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw NFAILearningError.invalidSchema
        }
        try validate(definition, depth: 0)
        return definition
    }

    private static func validate(_ definition: [String: Any], depth: Int) throws {
        guard depth <= 12, definition.count <= 32 else { throw NFAILearningError.invalidSchema }
        let allowed: Set<String> = ["type", "properties", "required", "additionalProperties", "description", "title",
                                    "$schema", "items", "minItems", "maxItems", "minLength", "maxLength",
                                    "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "enum", "anyOf"]
        guard Set(definition.keys).isSubset(of: allowed) else { throw NFAILearningError.unsupportedSchema }
        let types: [String]
        if let type = definition["type"] as? String { types = [type] }
        else { types = definition["type"] as? [String] ?? [] }
        guard types.allSatisfy({ ["object", "array", "string", "number", "integer", "boolean", "null"].contains($0) }),
              !types.isEmpty || definition["anyOf"] != nil else { throw NFAILearningError.invalidSchema }
        if let choices = definition["anyOf"] {
            guard let choices = choices as? [[String: Any]], !choices.isEmpty, choices.count <= 16 else {
                throw NFAILearningError.invalidSchema
            }
            for choice in choices { try validate(choice, depth: depth + 1) }
        }
        if let properties = definition["properties"] {
            guard let properties = properties as? [String: [String: Any]], properties.count <= 64 else {
                throw NFAILearningError.invalidSchema
            }
            for property in properties.values { try validate(property, depth: depth + 1) }
            if let required = definition["required"] {
                guard let required = required as? [String], Set(required).isSubset(of: Set(properties.keys)) else {
                    throw NFAILearningError.invalidSchema
                }
            }
        }
        if let items = definition["items"] {
            guard let items = items as? [String: Any] else { throw NFAILearningError.invalidSchema }
            try validate(items, depth: depth + 1)
        }
        if types.contains("array"), definition["items"] == nil { throw NFAILearningError.invalidSchema }
        if let options = definition["enum"] {
            guard let options = options as? [String], !options.isEmpty, options.count <= 128 else {
                throw NFAILearningError.unsupportedSchema
            }
        }
        for key in ["minItems", "maxItems", "minLength", "maxLength"] {
            if let value = definition[key] {
                guard let number = value as? Int, number >= 0, number <= 64_000 else {
                    throw NFAILearningError.invalidSchema
                }
            }
        }
        for key in ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"] {
            if let value = definition[key] {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else {
                    throw NFAILearningError.invalidSchema
                }
            }
        }
        if let additional = definition["additionalProperties"], !(additional is Bool) {
            throw NFAILearningError.unsupportedSchema
        }
    }

    static func matches(_ value: Any, definition: [String: Any]) -> Bool {
        if let choices = definition["anyOf"] as? [[String: Any]], !choices.contains(where: { matches(value, definition: $0) }) {
            return false
        }
        let types = (definition["type"] as? String).map { [$0] } ?? definition["type"] as? [String] ?? []
        if !types.isEmpty, !types.contains(where: { matchesType(value, type: $0) }) { return false }
        if let options = definition["enum"] as? [String], !options.contains(value as? String ?? "") { return false }
        if let object = value as? [String: Any] {
            let properties = definition["properties"] as? [String: [String: Any]] ?? [:]
            let required = definition["required"] as? [String] ?? []
            guard required.allSatisfy({ object[$0] != nil }) else { return false }
            if definition["additionalProperties"] as? Bool == false,
               !Set(object.keys).isSubset(of: Set(properties.keys)) { return false }
            for (key, property) in properties {
                if let child = object[key], !matches(child, definition: property) { return false }
            }
        }
        if let array = value as? [Any] {
            if let minimum = definition["minItems"] as? Int, array.count < minimum { return false }
            if let maximum = definition["maxItems"] as? Int, array.count > maximum { return false }
            if let items = definition["items"] as? [String: Any], !array.allSatisfy({ matches($0, definition: items) }) { return false }
        }
        if let string = value as? String {
            if let minimum = definition["minLength"] as? Int, string.unicodeScalars.count < minimum { return false }
            if let maximum = definition["maxLength"] as? Int, string.unicodeScalars.count > maximum { return false }
        }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let number = number.doubleValue
            guard number.isFinite else { return false }
            if let minimum = definition["minimum"] as? Double, number < minimum { return false }
            if let maximum = definition["maximum"] as? Double, number > maximum { return false }
            if let minimum = definition["exclusiveMinimum"] as? Double, number <= minimum { return false }
            if let maximum = definition["exclusiveMaximum"] as? Double, number >= maximum { return false }
        }
        return true
    }

    private static func matchesType(_ value: Any, type: String) -> Bool {
        switch type {
        case "object": value is [String: Any]
        case "array": value is [Any]
        case "string": value is String
        case "null": value is NSNull
        case "boolean": (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        case "number": (value as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite } ?? false
        case "integer": (value as? NSNumber).map {
            CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite && $0.doubleValue.rounded() == $0.doubleValue
        } ?? false
        default: false
        }
    }
}

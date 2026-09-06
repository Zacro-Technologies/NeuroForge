import Foundation
import XCTest
@testable import NeuroForge

@MainActor
final class NFAILearningProviderTests: XCTestCase {
    private let configuration = NFAICloudConfiguration(
        endpoint: URL(string: "https://provider.example/v1/chat/completions")!,
        model: "configured-model", providerName: "Test provider"
    )
    private let schema = """
    {"type":"object","properties":{"credit":{"type":"number","minimum":0,"maximum":1},
    "feedback":{"type":"string","minLength":1}},"required":["credit","feedback"],"additionalProperties":false}
    """

    func testSavedConfigurationNeverExposesTokenAndBlankKeyPreservesSameEndpoint() async throws {
        let store = NFMemoryAICloudCredentials()
        let service = service(store: store)
        try await service.saveConfiguration(configuration, apiKey: " sample-token ")
        let saved = try await service.configuration()
        let hasCredential = try await service.hasSavedCredential()
        XCTAssertEqual(saved, configuration)
        XCTAssertTrue(hasCredential)
        XCTAssertFalse(String(data: try JSONEncoder().encode(saved), encoding: .utf8)!.contains("sample-token"))
        let changedModel = NFAICloudConfiguration(endpoint: configuration.endpoint, model: "other-model")
        try await service.saveConfiguration(changedModel, apiKey: "")
        let credentials = await store.read()
        XCTAssertEqual(credentials?.apiKey, "sample-token")
        XCTAssertEqual(credentials?.configuration.model, "other-model")
    }

    func testChangingEndpointRequiresANewKeyAndPreservesExistingConfigurationOnFailure() async throws {
        let store = NFMemoryAICloudCredentials()
        let service = service(store: store)
        try await service.saveConfiguration(configuration, apiKey: "sample-token")
        do {
            try await service.saveConfiguration(.init(endpoint: URL(string: "https://different.example/chat/completions")!, model: "model"), apiKey: nil)
            XCTFail("A saved key must stay bound to its endpoint.")
        } catch {
            XCTAssertEqual(error as? NFAILearningError, .credentialRequired)
        }
        let saved = try await service.configuration()
        XCTAssertEqual(saved, configuration)
    }

    func testInvalidEndpointAndHeaderInjectionAreRejectedBeforeSaving() async throws {
        let store = NFMemoryAICloudCredentials()
        let service = service(store: store)
        for endpoint in ["http://provider.example/chat/completions", "https://user:password@provider.example/chat/completions", "https://provider.example/chat/completions?key=secret"] {
            do {
                try await service.saveConfiguration(.init(endpoint: URL(string: endpoint)!, model: "model"), apiKey: "sample-token")
                XCTFail("Invalid endpoint was accepted.")
            } catch {
                XCTAssertEqual(error as? NFAILearningError, .invalidConfiguration)
            }
        }
        do {
            try await service.saveConfiguration(configuration, apiKey: "sample\r\nInjected: header")
            XCTFail("Invalid key was accepted.")
        } catch {
            XCTAssertEqual(error as? NFAILearningError, .credentialRequired)
        }
        let saved = await store.read()
        XCTAssertNil(saved)
    }

    func testDeleteConfigurationRemovesSavedKeyAndRoute() async throws {
        let service = service()
        try await service.saveConfiguration(configuration, apiKey: "sample-token")
        try await service.deleteConfiguration()
        let saved = try await service.configuration()
        let hasCredential = try await service.hasSavedCredential()
        let availability = await service.availability(mode: .automatic)
        XCTAssertNil(saved)
        XCTAssertFalse(hasCredential)
        XCTAssertEqual(availability.route, .local)
    }

    func testCloudRequestUsesConfiguredEndpointBoundedOutputAndStrictSchema() async throws {
        let transport = NFRecordingAIHTTPTransport(response: Self.response(text: "{\"credit\":0.5,\"feedback\":\"Explain the causal link.\"}"))
        let service = service(transport: transport)
        try await service.saveConfiguration(configuration, apiKey: "sample-token")
        let request = NFAICompletionRequest(task: .grading, instructions: "Apply the rubric.", input: "Learner response", jsonSchema: schema, maxOutputTokens: 512)
        let result = try await service.complete(request, mode: .automatic)
        let requests = await transport.requests
        let http = try XCTUnwrap(requests.first)
        XCTAssertEqual(http.url, configuration.endpoint)
        XCTAssertEqual(http.httpMethod, "POST")
        XCTAssertEqual(http.value(forHTTPHeaderField: "Authorization"), "Bearer sample-token")
        XCTAssertEqual(http.value(forHTTPHeaderField: "X-Client-Request-Id"), request.id.uuidString)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(http.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "configured-model")
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 512)
        let format = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual((format["json_schema"] as? [String: Any])?["strict"] as? Bool, true)
        XCTAssertEqual(result.requestID, request.id)
        XCTAssertEqual(result.modelIdentifier, "actual-model-snapshot")
        XCTAssertEqual(result.providerIdentifier, configuration.endpoint.absoluteString)
        XCTAssertEqual(result.route, .cloud)
    }

    func testOnDeviceOnlyNeverCallsCloudEvenWithSavedConfiguration() async throws {
        let transport = NFRecordingAIHTTPTransport(response: Self.response())
        let local = NFFakeLearningLocalModel()
        let service = service(transport: transport, local: local)
        try await service.saveConfiguration(configuration, apiKey: "sample-token")
        let result = try await service.complete(request(), mode: .onDeviceOnly)
        let calls = await transport.requests
        let localCalls = await local.requests
        XCTAssertEqual(result.route, .local)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(localCalls.count, 1)
    }

    func testAutomaticFallsBackOfflineAfterPreConnectionFailureWithActualLocalProvenance() async throws {
        let transport = NFRecordingAIHTTPTransport(response: Self.response(), error: .notConnectedToInternet)
        let local = NFFakeLearningLocalModel()
        let service = service(transport: transport, local: local)
        try await service.saveConfiguration(configuration, apiKey: "sample-token")
        let request = request()
        let result = try await service.complete(request, mode: .automatic)
        XCTAssertEqual(result.requestID, request.id)
        XCTAssertEqual(result.route, .local)
        XCTAssertEqual(result.providerIdentifier, "test.local")
        XCTAssertEqual(result.modelIdentifier, "fake-model")
        let cloudCalls = await transport.requests
        let localCalls = await local.requests
        XCTAssertEqual(cloudCalls.count, 1)
        XCTAssertEqual(localCalls.count, 1)
    }

    func testUnknownRemoteOutcomeAndTimeoutNeverTriggerFallback() async throws {
        for code in [URLError.Code.timedOut, .networkConnectionLost] {
            let transport = NFRecordingAIHTTPTransport(response: Self.response(), error: code)
            let local = NFFakeLearningLocalModel()
            let service = service(transport: transport, local: local)
            try await service.saveConfiguration(configuration, apiKey: "sample-token")
            do {
                _ = try await service.complete(request(), mode: .automatic)
                XCTFail("An uncertain remote outcome must require explicit retry.")
            } catch {
                XCTAssertEqual(error as? NFAILearningError, code == .timedOut ? .timedOut : .connectionFailed)
            }
            let localCalls = await local.requests
            XCTAssertTrue(localCalls.isEmpty)
        }
    }

    func testOfflineFallbackStillValidatesLocalStructuredOutput() async throws {
        let transport = NFRecordingAIHTTPTransport(response: Self.response(), error: .notConnectedToInternet)
        let service = service(transport: transport)
        try await service.saveConfiguration(configuration, apiKey: "sample-token")
        do {
            _ = try await service.complete(.init(task: .grading, instructions: "Grade.", input: "Answer", jsonSchema: schema), mode: .automatic)
            XCTFail("Local prose must not pass as a structured grade.")
        } catch { XCTAssertEqual(error as? NFAILearningError, .invalidResponse) }
    }

    func testConnectionCheckNeverReportsOfflineFallbackAsCloudSuccess() async throws {
        let transport = NFRecordingAIHTTPTransport(response: Self.response(), error: .notConnectedToInternet)
        let local = NFFakeLearningLocalModel()
        let service = service(transport: transport, local: local)
        try await service.saveConfiguration(configuration, apiKey: "sample-token")
        do {
            _ = try await service.testConfiguration()
            XCTFail("A cloud check must never use the local model.")
        } catch { XCTAssertEqual(error as? NFAILearningError, .connectionFailed) }
        let localCalls = await local.requests
        XCTAssertTrue(localCalls.isEmpty)
    }

    func testTokenLimitsAreRejectedBeforeProviderDispatch() async throws {
        let local = NFFakeLearningLocalModel()
        let service = service(local: local)
        for tokens in [0, 4_097] {
            do {
                _ = try await service.complete(.init(task: .tutoring, instructions: "Explain", input: "Answer", maxOutputTokens: tokens), mode: .onDeviceOnly)
                XCTFail("An invalid output token limit was dispatched.")
            } catch { XCTAssertEqual(error as? NFAILearningError, .inputTooLarge) }
        }
        let localCalls = await local.requests
        XCTAssertTrue(localCalls.isEmpty)
    }

    func testDisabledModeCallsNeitherProvider() async throws {
        let transport = NFRecordingAIHTTPTransport(response: Self.response())
        let local = NFFakeLearningLocalModel()
        let service = service(transport: transport, local: local)
        do {
            _ = try await service.complete(request(), mode: .disabled)
            XCTFail("Disabled AI performed inference.")
        } catch { XCTAssertEqual(error as? NFAILearningError, .disabled) }
        let cloudCalls = await transport.requests
        let localCalls = await local.requests
        XCTAssertTrue(cloudCalls.isEmpty)
        XCTAssertTrue(localCalls.isEmpty)
    }

    func testAutomaticAvailabilityDistinguishesConfiguredCloudFromUnavailableLocal() async throws {
        let service = service(local: .init(isAvailable: false))
        var status = await service.availability(mode: .automatic)
        XCTAssertFalse(status.isAvailable)
        XCTAssertNil(status.route)
        try await service.saveConfiguration(configuration, apiKey: "sample-token")
        status = await service.availability(mode: .automatic)
        XCTAssertTrue(status.isAvailable)
        XCTAssertTrue(status.cloudConfigured)
        XCTAssertFalse(status.localAvailable)
        XCTAssertEqual(status.route, .cloud)
        let localStatus = await service.availability(mode: .onDeviceOnly)
        XCTAssertFalse(localStatus.isAvailable)
        XCTAssertNil(localStatus.route)
    }

    func testStructuredOutputRejectsWrongTypesMissingFieldsExtraFieldsAndOutOfRangeCredit() async throws {
        for invalid in ["{\"credit\":true,\"feedback\":\"OK\"}", "{\"credit\":1.2,\"feedback\":\"OK\"}", "{\"credit\":0.5}", "{\"credit\":0.5,\"feedback\":\"\"}", "{\"credit\":0.5,\"feedback\":\"OK\",\"extra\":1}", "```json\n{}\n```"] {
            let service = service(transport: .init(response: Self.response(text: invalid)))
            try await service.saveConfiguration(configuration, apiKey: "sample-token")
            do {
                _ = try await service.complete(.init(task: .grading, instructions: "Grade.", input: "Answer", jsonSchema: schema), mode: .automatic)
                XCTFail("Invalid grade passed: \(invalid)")
            } catch { XCTAssertEqual(error as? NFAILearningError, .invalidResponse) }
        }
    }

    func testTruncatedAndRefusedCloudResponsesNeverBecomeSuccessfulResults() async throws {
        for (response, expected) in [(Self.response(finishReason: "length"), NFAILearningError.incompleteResponse),
                                     (Self.response(refusal: "Cannot answer"), NFAILearningError.refused)] {
            let service = service(transport: .init(response: response))
            try await service.saveConfiguration(configuration, apiKey: "sample-token")
            do {
                _ = try await service.complete(request(), mode: .automatic)
                XCTFail("Incomplete response passed.")
            } catch { XCTAssertEqual(error as? NFAILearningError, expected) }
        }
    }

    func testProviderErrorsAreTypedAndNeverExposeServerBodies() async throws {
        for (status, expected) in [(401, NFAILearningError.authentication), (403, .authentication), (429, .rateLimited), (503, .serverUnavailable(503)), (302, .serverUnavailable(302))] {
            let transport = NFRecordingAIHTTPTransport(response: .init(statusCode: status, data: Data("sensitive upstream diagnostic".utf8)))
            let service = service(transport: transport)
            try await service.saveConfiguration(configuration, apiKey: "sample-token")
            do {
                _ = try await service.complete(request(), mode: .automatic)
                XCTFail("Failed HTTP response passed.")
            } catch {
                XCTAssertEqual(error as? NFAILearningError, expected)
                XCTAssertFalse(error.localizedDescription.contains("sensitive"))
            }
        }
    }

    func testOversizedOutputAndHTTPBodyAreRejected() async throws {
        for response in [Self.response(text: String(repeating: "x", count: 64_001)),
                         .init(statusCode: 200, data: Data(repeating: 32, count: 512_001))] {
            let service = service(transport: .init(response: response))
            try await service.saveConfiguration(configuration, apiKey: "sample-token")
            do {
                _ = try await service.complete(request(), mode: .automatic)
                XCTFail("Oversized response passed.")
            } catch { XCTAssertEqual(error as? NFAILearningError, .outputTooLarge) }
        }
    }

    func testInvalidInputAndUnsupportedSchemaDoNotReachProviders() async throws {
        let local = NFFakeLearningLocalModel()
        let service = service(local: local)
        for invalid in [NFAICompletionRequest(task: .tutoring, instructions: "Explain", input: String(repeating: "x", count: 96_001)),
                        .init(task: .grading, instructions: "Grade", input: "Answer", jsonSchema: "{\"type\":\"string\",\"pattern\":\".*\"}")] {
            do {
                _ = try await service.complete(invalid, mode: .onDeviceOnly)
                XCTFail("Invalid request reached a provider.")
            } catch { XCTAssertNotNil(error as? NFAILearningError) }
        }
        let calls = await local.requests
        XCTAssertTrue(calls.isEmpty)
    }

    func testTimeoutCancelsPendingTransportWithoutASecondRequest() async throws {
        let transport = NFRecordingAIHTTPTransport(response: Self.response(), delay: .seconds(10))
        let service = service(transport: transport, timeout: .milliseconds(20))
        try await service.saveConfiguration(configuration, apiKey: "sample-token")
        do {
            _ = try await service.complete(request(), mode: .automatic)
            XCTFail("A stalled provider did not time out.")
        } catch { XCTAssertEqual(error as? NFAILearningError, .timedOut) }
        let requests = await transport.requests
        let cancelled = await transport.cancelled
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(cancelled)
    }

    func testUserCancellationPropagatesToTransport() async throws {
        let transport = NFRecordingAIHTTPTransport(response: Self.response(), delay: .seconds(10))
        let service = service(transport: transport)
        try await service.saveConfiguration(configuration, apiKey: "sample-token")
        let request = request()
        let task = Task { try await service.complete(request, mode: .automatic) }
        while await transport.requests.isEmpty { await Task.yield() }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled inference returned a result.")
        } catch { XCTAssertTrue(error is CancellationError) }
        let cancelled = await transport.cancelled
        XCTAssertTrue(cancelled)
    }

    func testConnectionCheckUsesOnlySavedCloudConfiguration() async throws {
        let transport = NFRecordingAIHTTPTransport(response: Self.response(text: "Ready"))
        let service = service(transport: transport)
        do {
            _ = try await service.testConfiguration()
            XCTFail("Connection check must require a saved cloud provider.")
        } catch { XCTAssertEqual(error as? NFAILearningError, .notConfigured) }
        try await service.saveConfiguration(configuration, apiKey: "sample-token")
        let result = try await service.testConfiguration()
        XCTAssertEqual(result.route, .cloud)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testRetainedCompletionResultRoundTripsWithoutReinvokingProvider() async throws {
        let local = NFFakeLearningLocalModel()
        let service = service(local: local)
        let result = try await service.complete(request(), mode: .automatic)
        let replayed = try JSONDecoder().decode(NFAICompletionResult.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(replayed, result)
        let calls = await local.requests
        XCTAssertEqual(calls.count, 1)
    }

    private func request() -> NFAICompletionRequest {
        .init(task: .tutoring, instructions: "Explain one next step.", input: "Why does this happen?")
    }

    private func service(
        store: NFMemoryAICloudCredentials = .init(),
        transport: NFRecordingAIHTTPTransport = .init(response: NFAIHTTPResponse(statusCode: 500, data: Data())),
        local: NFFakeLearningLocalModel = .init(), timeout: Duration = .seconds(45)
    ) -> NFAILearningService {
        .init(credentialStore: store, transport: transport, localProvider: local, timeout: timeout)
    }

    private static func response(text: String = "A useful explanation.", finishReason: String = "stop", refusal: String? = nil) -> NFAIHTTPResponse {
        let message: [String: Any] = ["content": text, "refusal": refusal as Any? ?? NSNull()]
        let body: [String: Any] = ["model": "actual-model-snapshot", "choices": [["message": message, "finish_reason": finishReason]]]
        return .init(statusCode: 200, data: try! JSONSerialization.data(withJSONObject: body))
    }
}

private actor NFMemoryAICloudCredentials: NFAICloudCredentialStore {
    private var saved: NFAIStoredCloudCredentials?
    func read() -> NFAIStoredCloudCredentials? { saved }
    func write(_ credentials: NFAIStoredCloudCredentials) { saved = credentials }
    func delete() { saved = nil }
}

private actor NFRecordingAIHTTPTransport: NFAIHTTPTransport {
    let response: NFAIHTTPResponse
    let delay: Duration?
    let error: URLError.Code?
    private(set) var requests: [URLRequest] = []
    private(set) var cancelled = false

    init(response: NFAIHTTPResponse, delay: Duration? = nil, error: URLError.Code? = nil) {
        self.response = response
        self.delay = delay
        self.error = error
    }

    func send(_ request: URLRequest, maximumResponseBytes: Int) async throws -> NFAIHTTPResponse {
        requests.append(request)
        if let error { throw URLError(error) }
        if let delay {
            do { try await Task.sleep(for: delay) }
            catch {
                cancelled = true
                throw error
            }
        }
        return response
    }
}

private actor NFFakeLearningLocalModel: NFAILocalModelProvider {
    let isAvailable: Bool
    private(set) var requests: [NFAICompletionRequest] = []
    init(isAvailable: Bool = true) { self.isAvailable = isAvailable }
    func availability() -> NFAILocalAvailability {
        .init(isAvailable: isAvailable, status: isAvailable ? "Ready offline" : "Model unavailable")
    }
    func complete(_ request: NFAICompletionRequest) throws -> NFAICompletionResult {
        guard isAvailable else { throw NFAILearningError.localUnavailable("Model unavailable") }
        requests.append(request)
        return .init(requestID: request.id, text: "Consider the relationship in your example.",
                     providerIdentifier: "test.local", modelIdentifier: "fake-model", route: .local, generatedAt: Date())
    }
}

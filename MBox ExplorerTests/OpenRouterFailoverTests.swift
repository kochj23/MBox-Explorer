//
//  OpenRouterFailoverTests.swift
//  MBox ExplorerTests
//
//  Deterministic (no-network) tests for the OpenRouter provider, the
//  OpenAI-compatible request builder, the automatic-failover selection logic,
//  and the Keychain store round-trip. Adapted from AIStudio (balancer core is
//  copied verbatim; attribution/keychain identifiers are MBox-specific and the
//  chat-message value type is namespaced `BalancerChatMessage`).
//

import XCTest
@testable import MBox_Explorer

final class OpenRouterFailoverTests: XCTestCase {

    private func bodyJSON(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - OpenRouter constants

    func testOpenRouterEndpoints() {
        XCTAssertEqual(OpenRouterProvider.baseURL, "https://openrouter.ai/api/v1")
        XCTAssertEqual(OpenRouterProvider.chatCompletionsURL, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(OpenRouterProvider.modelsURL, "https://openrouter.ai/api/v1/models")
        XCTAssertEqual(LLMBackendType.openRouter.displayName, "OpenRouter (Frontier Models)")
        XCTAssertEqual(LLMBackendType.openRouter.rawValue, "openrouter")
        XCTAssertEqual(LLMBackendType.openRouter.defaultURL, "https://openrouter.ai/api/v1")
    }

    func testOpenRouterAuthHeaders() {
        let headers = OpenRouterProvider.authHeaders(apiKey: "sk-or-test-123")
        XCTAssertEqual(headers["Authorization"], "Bearer sk-or-test-123")
        XCTAssertEqual(headers["HTTP-Referer"], "https://github.com/kochj23/MBox-Explorer")
        XCTAssertEqual(headers["X-Title"], "MBox-Explorer")
    }

    func testOpenRouterParseModels() {
        let json = """
        {"data": [{"id": "openai/gpt-4o"}, {"id": "anthropic/claude-sonnet-4.5"}, {"name": "no-id"}]}
        """
        let models = OpenRouterProvider.parseModels(json.data(using: .utf8)!)
        XCTAssertEqual(models, ["openai/gpt-4o", "anthropic/claude-sonnet-4.5"])
        XCTAssertTrue(OpenRouterProvider.parseModels(Data("nonsense".utf8)).isEmpty)
        XCTAssertFalse(OpenRouterProvider.fallbackModels.isEmpty)
    }

    // MARK: - Request construction

    func testOpenRouterRequestConstruction() throws {
        let messages = OpenAICompatibleRequest.chatMessages(
            prompt: "Hello there",
            systemPrompt: "You are helpful",
            history: []
        )
        let request = try OpenAICompatibleRequest.build(
            endpoint: OpenRouterProvider.chatCompletionsURL,
            model: "anthropic/claude-sonnet-4.5",
            messages: messages,
            temperature: 0.5,
            maxTokens: 1024,
            stream: false,
            headers: OpenRouterProvider.authHeaders(apiKey: "sk-or-abc")
        )

        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-abc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "HTTP-Referer"), "https://github.com/kochj23/MBox-Explorer")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Title"), "MBox-Explorer")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try bodyJSON(request)
        XCTAssertEqual(body["model"] as? String, "anthropic/claude-sonnet-4.5")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["max_tokens"] as? Int, 1024)

        let sentMessages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(sentMessages.count, 2)
        XCTAssertEqual(sentMessages[0]["role"], "system")
        XCTAssertEqual(sentMessages[0]["content"], "You are helpful")
        XCTAssertEqual(sentMessages[1]["role"], "user")
        XCTAssertEqual(sentMessages[1]["content"], "Hello there")
    }

    func testMessageMappingWithHistory() {
        let history = [
            BalancerChatMessage(role: .system, content: "ignored-system"),
            BalancerChatMessage(role: .user, content: "first question"),
            BalancerChatMessage(role: .assistant, content: "an answer")
        ]
        let messages = OpenAICompatibleRequest.chatMessages(
            prompt: "follow up",
            systemPrompt: "top system",
            history: history
        )
        XCTAssertEqual(messages.count, 4)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[0]["content"], "top system")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "first question")
        XCTAssertEqual(messages[2]["role"], "assistant")
        XCTAssertEqual(messages[3]["role"], "user")
        XCTAssertEqual(messages[3]["content"], "follow up")
    }

    func testMessageMappingSkipsDuplicateTrailingPrompt() {
        let history = [BalancerChatMessage(role: .user, content: "same prompt")]
        let messages = OpenAICompatibleRequest.chatMessages(
            prompt: "same prompt",
            systemPrompt: nil,
            history: history
        )
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["content"], "same prompt")
    }

    func testBuildInvalidEndpointThrows() {
        XCTAssertThrowsError(try OpenAICompatibleRequest.build(
            endpoint: "http://a b c/\\invalid",
            model: "m",
            messages: [],
            temperature: 0.7,
            maxTokens: 10,
            stream: false
        ))
    }

    // MARK: - Failover selection logic

    func testFailoverDefaultChain() {
        XCTAssertEqual(FailoverPlanner.defaultChain, [.ollama, .mlx, .openRouter])
    }

    func testFailoverPicksFirstHealthy() {
        let avail1: [LLMBackendType: Bool] = [.ollama: true, .mlx: true, .openRouter: true]
        XCTAssertEqual(FailoverPlanner.firstHealthy(chain: FailoverPlanner.defaultChain, availability: avail1), .ollama)
    }

    func testFailoverFallsThroughToMLX() {
        let avail: [LLMBackendType: Bool] = [.ollama: false, .mlx: true, .openRouter: true]
        XCTAssertEqual(FailoverPlanner.firstHealthy(chain: FailoverPlanner.defaultChain, availability: avail), .mlx)
    }

    func testFailoverFallsThroughToOpenRouter() {
        let avail: [LLMBackendType: Bool] = [.ollama: false, .mlx: false, .openRouter: true]
        XCTAssertEqual(FailoverPlanner.firstHealthy(chain: FailoverPlanner.defaultChain, availability: avail), .openRouter)
    }

    func testFailoverNoneHealthy() {
        let avail: [LLMBackendType: Bool] = [.ollama: false, .mlx: false, .openRouter: false]
        XCTAssertNil(FailoverPlanner.firstHealthy(chain: FailoverPlanner.defaultChain, availability: avail))
        XCTAssertTrue(FailoverPlanner.orderedHealthy(chain: FailoverPlanner.defaultChain, availability: avail).isEmpty)
    }

    func testFailoverOrderedHealthyPreservesChainOrder() {
        let avail: [LLMBackendType: Bool] = [.ollama: false, .mlx: true, .openRouter: true]
        XCTAssertEqual(
            FailoverPlanner.orderedHealthy(chain: FailoverPlanner.defaultChain, availability: avail),
            [.mlx, .openRouter]
        )
    }

    func testFailoverMissingKeyTreatedAsUnavailable() {
        let avail: [LLMBackendType: Bool] = [.openRouter: true]
        XCTAssertEqual(FailoverPlanner.firstHealthy(chain: FailoverPlanner.defaultChain, availability: avail), .openRouter)
    }

    // MARK: - Keychain round-trip

    func testKeychainRoundTrip() {
        let store = KeychainStore(service: "com.jkoch.mboxexplorer.tests.\(UUID().uuidString)", account: "apiKey")
        store.delete()
        XCTAssertNil(store.get())
        XCTAssertFalse(store.hasValue)

        XCTAssertTrue(store.set("sk-or-secret-value"))
        XCTAssertEqual(store.get(), "sk-or-secret-value")
        XCTAssertTrue(store.hasValue)

        XCTAssertTrue(store.set("sk-or-updated"))
        XCTAssertEqual(store.get(), "sk-or-updated")

        XCTAssertTrue(store.delete())
        XCTAssertNil(store.get())
        XCTAssertFalse(store.hasValue)
    }
}

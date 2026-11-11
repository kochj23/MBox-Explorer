//
//  OpenRouterFailoverTests.swift
//  MBox ExplorerTests
//
//  OpenRouter / failover / key storage, now through NovaAIKit: keys only in the (here: in-memory) key store under
//  com.jkoch.mboxexplorer.<backend>, https-only for keyed backends, and Auto failover across backends.
//  Deterministic, no network.
//

import XCTest
import NovaAIKit
@testable import MBox_Explorer

@MainActor
final class OpenRouterFailoverTests: XCTestCase {

    // MARK: - OpenRouter defaults

    func testOpenRouterDefaults() {
        XCTAssertTrue(NovaAIBackend.openRouter.defaultURL.hasPrefix("https://openrouter.ai"))
        XCTAssertTrue(NovaAIBackend.openRouter.requiresKey)
        XCTAssertTrue(NovaAIBackend.openRouter.supportsJSONSchema)
        XCTAssertEqual(NovaAIBackend.openRouter.rawValue, "openrouter")
    }

    func testOpenRouterWithoutKeyIsMissingKey() async {
        let ai = AITestKit.makeAI(NovaAISettings(backend: .openRouter))
        do {
            _ = try await ai.complete(NovaAIRequest(prompt: "hi"))
            XCTFail("expected missing key")
        } catch {
            XCTAssertEqual(error as? NovaAIError, .missingKey(.openRouter))
        }
    }

    // MARK: - Failover

    func testFailoverToNextBackendWhenFirstFails() async throws {
        OllamaStubProtocol.script([.status(500), .status(500), .text("second backend")])
        let ai = AITestKit.makeAI(NovaAISettings(backend: .auto), proto: OllamaStubProtocol.self)
        let r = try await ai.complete(NovaAIRequest(prompt: "hi"))
        XCTAssertEqual(r.text, "second backend")
        XCTAssertNotEqual(r.backend, .ollama)
    }

    func testNoneHealthyFallsBackToBuiltIn() async {
        let ai = AITestKit.makeAI(NovaAISettings(backend: .auto))
        let r = await ai.text(NovaAIRequest(prompt: "hi")) { "built-in" }
        XCTAssertEqual(r.value, "built-in")
        XCTAssertFalse(r.isAI)
    }

    func testFirstHealthyBackendAnswers() async throws {
        OllamaStubProtocol.script([.text("from ollama")])
        let r = try await AITestKit.makeAI(NovaAISettings(backend: .auto), proto: OllamaStubProtocol.self)
            .complete(NovaAIRequest(prompt: "hi"))
        XCTAssertEqual(r.backend, .ollama)
        XCTAssertEqual(r.text, "from ollama")
    }

    func testStatusShowsOfflineWhenNothingReachable() async {
        let ai = AITestKit.makeAI(NovaAISettings(backend: .auto))
        await ai.refreshStatus()
        XCTAssertEqual(ai.status.state, .offline)
    }

    // MARK: - Key store round-trip (in memory; the app uses the Keychain)

    func testKeyRoundTrip() {
        let keys = NovaAIMemoryKeyStore()
        let ai = AITestKit.makeAI(keys: keys)
        XCTAssertFalse(ai.hasAPIKey(for: .openRouter))
        XCTAssertTrue(ai.setAPIKey("sk-or-secret-value", for: .openRouter))
        XCTAssertTrue(ai.hasAPIKey(for: .openRouter))
        XCTAssertEqual(keys.read(service: "com.jkoch.mboxexplorer.openrouter", account: "apiKey"), "sk-or-secret-value")
        XCTAssertTrue(ai.setAPIKey("sk-or-updated", for: .openRouter))
        XCTAssertEqual(ai.keys.key(for: .openRouter), "sk-or-updated")
        XCTAssertTrue(ai.setAPIKey(nil, for: .openRouter))
        XCTAssertFalse(ai.hasAPIKey(for: .openRouter))
    }

    func testKeysNeverPersistInSettings() throws {
        let ai = AITestKit.makeAI()
        ai.setAPIKey("sk-or-secret-value", for: .openRouter)
        let json = String(data: try JSONEncoder().encode(ai.settings), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("sk-or-secret-value"))
    }
}

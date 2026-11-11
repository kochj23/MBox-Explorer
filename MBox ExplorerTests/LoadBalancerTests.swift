//
//  LoadBalancerTests.swift
//  MBox ExplorerTests
//
//  The old in-app load balancer (ModelRegistry / LoadBalancer / LLMBackendType) was replaced by NovaAIKit's Auto
//  failover; the bulk-embedding round-robin stayed app-owned. These tests cover the same ground against the new
//  types: the backend catalogue, Auto's order, candidate assembly (keyed backends only with a key, extra Ollama
//  endpoints), and the embedding pool rotation. Network-free.
//

import XCTest
import NovaAIKit
@testable import MBox_Explorer

final class LoadBalancerTests: XCTestCase {

    private func engine(_ s: NovaAISettings, keys: NovaAIMemoryKeyStore = NovaAIMemoryKeyStore()) -> NovaAIEngine {
        let cfg = NovaAIConfiguration(appID: "mboxexplorer", appName: "MBox Explorer")
        return NovaAIEngine(configuration: cfg, settings: s, keys: NovaAIKeys(configuration: cfg, store: keys),
                            session: URLSession(configuration: .ephemeral), health: NovaAIHealth(), sleep: { _ in })
    }

    // MARK: - Backend catalogue (was LLMBackendType)

    func testBackendCatalogueHasNineEntries() {
        XCTAssertEqual(NovaAIBackend.allCases.count, 9)
    }

    func testNovaGatewayBackend() {
        XCTAssertEqual(NovaAIBackend.novaGateway.rawValue, "novagateway")
        XCTAssertFalse(NovaAIBackend.novaGateway.displayName.isEmpty)
        XCTAssertFalse(NovaAIBackend.novaGateway.symbolName.isEmpty)
        XCTAssertFalse(NovaAIBackend.novaGateway.requiresKey)
    }

    func testEveryBackendHasDefaults() {
        for b in NovaAIBackend.allCases where b != .auto {
            XCTAssertFalse(b.defaultURL.isEmpty, "\(b)")
            XCTAssertFalse(b.displayName.isEmpty, "\(b)")
        }
    }

    // MARK: - Auto order (was the balancer pool)

    func testAutoOrderIsLocalFirstThenCloud() {
        let order = NovaAIBackend.autoOrder
        XCTAssertEqual(order.first, .ollama)
        XCTAssertLessThan(order.firstIndex(of: .ollama)!, order.firstIndex(of: .openRouter)!)
        XCTAssertLessThan(order.firstIndex(of: .novaGateway)!, order.firstIndex(of: .openAI)!)
        XCTAssertFalse(order.contains(.auto))
    }

    func testAutoChainWithoutKeysSkipsCloudBackends() {
        let backends = engine(NovaAISettings(backend: .auto)).candidates().map(\.backend)
        XCTAssertTrue(backends.contains(.ollama))
        XCTAssertFalse(backends.contains(.openRouter))
        XCTAssertFalse(backends.contains(.openAI))
    }

    func testAutoChainWithOpenRouterKeyIncludesIt() {
        let e = engine(NovaAISettings(backend: .auto))
        XCTAssertTrue(e.keys.setKey("sk-or-x", for: .openRouter))
        XCTAssertTrue(e.candidates().map(\.backend).contains(.openRouter))
    }

    func testSingleBackendChain() {
        XCTAssertEqual(engine(NovaAISettings(backend: .tinyChat)).chain(), [.tinyChat])
    }

    func testExtraOllamaEndpointsJoinThePool() {
        var s = NovaAISettings(backend: .ollama)
        s.extraOllamaEndpoints = [NovaAIEndpoint(url: "http://studio.local:11434", model: "")]
        let c = engine(s).candidates()
        XCTAssertEqual(c.count, 2)
        XCTAssertTrue(c.allSatisfy { $0.backend == .ollama })
    }

    func testCandidatesAreDeduplicated() {
        var s = NovaAISettings(backend: .ollama)
        s.extraOllamaEndpoints = [NovaAIEndpoint(url: s.url(for: .ollama), model: "")]
        XCTAssertEqual(engine(s).candidates().count, 1)
    }

    // MARK: - Embedding pool rotation (bulk indexing)

    func testRoundRobinCyclesAndWraps() {
        var rr = EmbeddingRoundRobin()
        let picks = (0..<7).compactMap { _ in rr.next(from: ["a", "b", "c"]) }
        XCTAssertEqual(picks, ["a", "b", "c", "a", "b", "c", "a"])
    }

    func testRoundRobinEmptyPoolReturnsNil() {
        var rr = EmbeddingRoundRobin()
        XCTAssertNil(rr.next(from: []))
    }

    func testRoundRobinSingleModel() {
        var rr = EmbeddingRoundRobin()
        XCTAssertEqual((0..<3).compactMap { _ in rr.next(from: ["only"]) }, ["only", "only", "only"])
    }
}

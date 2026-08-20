//
//  LoadBalancerTests.swift
//  MBox ExplorerTests
//
//  Deterministic (no-network) tests for model discovery parsing, pool
//  composition, and the load-balancer selection policies. Adapted from the
//  AIStudio balancer test suite (the balancer core is copied verbatim).
//

import XCTest
@testable import MBox_Explorer

final class LoadBalancerTests: XCTestCase {

    // MARK: - parseOllamaTags

    func testParseOllamaTagsMapsModels() {
        let json = """
        {"models": [
            {"name": "mistral:latest", "size": 123},
            {"name": "llama3.2:3b"},
            {"size": 5}
        ]}
        """
        let models = ModelRegistry.parseOllamaTags(Data(json.utf8))
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models.map { $0.modelName }, ["mistral:latest", "llama3.2:3b"])
        XCTAssertTrue(models.allSatisfy { $0.backend == .ollama })
        XCTAssertEqual(models[0].id, "ollama|mistral:latest")
        XCTAssertEqual(models[0].endpoint, "http://localhost:11434/api/chat")
    }

    func testParseOllamaTagsEmptyAndGarbage() {
        XCTAssertTrue(ModelRegistry.parseOllamaTags(Data("nonsense".utf8)).isEmpty)
        XCTAssertTrue(ModelRegistry.parseOllamaTags(Data("{}".utf8)).isEmpty)
        XCTAssertTrue(ModelRegistry.parseOllamaTags(Data(#"{"models": []}"#.utf8)).isEmpty)
        XCTAssertTrue(ModelRegistry.parseOllamaTags(Data()).isEmpty)
    }

    // MARK: - parseMLXModels

    func testParseMLXModelsFromHubDirs() {
        let dirs = [
            "models--mlx-community--Llama-3.2-3B-Instruct-4bit",
            "models--meta-llama--Llama-3.1-8B",          // not MLX → excluded
            "models--mlx-community--Qwen2.5-7B-4bit",
            "blobs",                                       // not a model dir → excluded
            "models--"                                     // empty repo → excluded
        ]
        let models = ModelRegistry.parseMLXModels(hubDirectoryNames: dirs)
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models.map { $0.modelName },
                       ["mlx-community/Llama-3.2-3B-Instruct-4bit", "mlx-community/Qwen2.5-7B-4bit"])
        XCTAssertTrue(models.allSatisfy { $0.backend == .mlx })
        XCTAssertEqual(models[0].displayName, "Llama-3.2-3B-Instruct-4bit")
    }

    func testParseMLXModelsEmpty() {
        XCTAssertTrue(ModelRegistry.parseMLXModels(hubDirectoryNames: []).isEmpty)
        XCTAssertTrue(ModelRegistry.parseMLXModels(hubDirectoryNames: ["random", "stuff"]).isEmpty)
    }

    // MARK: - frontier + nova mapping

    func testFrontierModelsMapping() {
        let frontier = ModelRegistry.frontierModels(from: ["openai/gpt-4o", "anthropic/claude-sonnet-4.5", ""])
        XCTAssertEqual(frontier.count, 2)
        XCTAssertTrue(frontier.allSatisfy { $0.backend == .openRouter })
        XCTAssertEqual(frontier[0].endpoint, OpenRouterProvider.chatCompletionsURL)
    }

    func testNovaGatewayModel() {
        let nova = ModelRegistry.novaGatewayModel()
        XCTAssertEqual(nova.backend, .novaGateway)
        XCTAssertEqual(nova.endpoint, "http://127.0.0.1:18792/v1/chat/completions")
    }

    // MARK: - Pool composition (toggles)

    private func samplePool() -> (local: [DiscoveredModel], frontier: [DiscoveredModel], nova: DiscoveredModel) {
        let ollama = [DiscoveredModel(modelName: "mistral:latest", backend: .ollama, endpoint: "e")]
        let mlx = [DiscoveredModel(modelName: "mlx-community/Qwen", backend: .mlx, endpoint: "")]
        let frontier = ModelRegistry.frontierModels(from: ["openai/gpt-4o"])
        let nova = ModelRegistry.novaGatewayModel()
        return (ollama + mlx, frontier, nova)
    }

    func testAssemblePoolLocalOnly() {
        let s = samplePool()
        let pool = ModelRegistry.assemblePool(
            ollama: [s.local[0]], mlx: [s.local[1]], frontier: s.frontier, novaGateway: s.nova,
            useAllLocalModels: true, enableAllFrontierModels: false, useNovaGateway: false)
        XCTAssertEqual(pool.count, 2)
        XCTAssertTrue(pool.allSatisfy { $0.backend == .ollama || $0.backend == .mlx })
    }

    func testAssemblePoolFrontierOnly() {
        let s = samplePool()
        let pool = ModelRegistry.assemblePool(
            ollama: [s.local[0]], mlx: [s.local[1]], frontier: s.frontier, novaGateway: s.nova,
            useAllLocalModels: false, enableAllFrontierModels: true, useNovaGateway: false)
        XCTAssertEqual(pool.count, 1)
        XCTAssertEqual(pool[0].backend, .openRouter)
    }

    func testAssemblePoolBothPlusNova() {
        let s = samplePool()
        let pool = ModelRegistry.assemblePool(
            ollama: [s.local[0]], mlx: [s.local[1]], frontier: s.frontier, novaGateway: s.nova,
            useAllLocalModels: true, enableAllFrontierModels: true, useNovaGateway: true)
        XCTAssertEqual(pool.count, 4)
        XCTAssertTrue(pool.contains { $0.backend == .novaGateway })
    }

    func testAssemblePoolNovaAbsentWhenToggleOff() {
        let s = samplePool()
        let pool = ModelRegistry.assemblePool(
            ollama: [s.local[0]], mlx: [s.local[1]], frontier: s.frontier, novaGateway: s.nova,
            useAllLocalModels: true, enableAllFrontierModels: false, useNovaGateway: false)
        XCTAssertFalse(pool.contains { $0.backend == .novaGateway })
    }

    func testAssemblePoolAllOff() {
        let s = samplePool()
        let pool = ModelRegistry.assemblePool(
            ollama: [s.local[0]], mlx: [s.local[1]], frontier: s.frontier, novaGateway: s.nova,
            useAllLocalModels: false, enableAllFrontierModels: false, useNovaGateway: false)
        XCTAssertTrue(pool.isEmpty)
    }

    func testAssemblePoolDeduplicates() {
        let dup = DiscoveredModel(modelName: "mistral:latest", backend: .ollama, endpoint: "e")
        let pool = ModelRegistry.assemblePool(
            ollama: [dup, dup], mlx: [], frontier: [], novaGateway: nil,
            useAllLocalModels: true, enableAllFrontierModels: false, useNovaGateway: false)
        XCTAssertEqual(pool.count, 1)
    }

    // MARK: - Round-robin policy

    func testRoundRobinCyclesAndWraps() {
        let pool = ["a", "b", "c"].map { DiscoveredModel(modelName: $0, backend: .ollama, endpoint: "e") }
        let health = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, true) })
        let lb = LoadBalancer()

        var picks: [String] = []
        for _ in 0..<7 {
            picks.append(lb.next(pool: pool, health: health, policy: .roundRobin)!.modelName)
        }
        XCTAssertEqual(picks, ["a", "b", "c", "a", "b", "c", "a"])
    }

    // MARK: - Least-busy policy

    func testLeastBusyPicksLowestInFlight() {
        let pool = ["a", "b", "c"].map { DiscoveredModel(modelName: $0, backend: .ollama, endpoint: "e") }
        let health = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, true) })
        let lb = LoadBalancer()

        // a: 2 in-flight, b: 0, c: 1 → b is least busy.
        lb.checkOut(pool[0].id); lb.checkOut(pool[0].id)
        lb.checkOut(pool[2].id)
        XCTAssertEqual(lb.next(pool: pool, health: health, policy: .leastBusy)?.modelName, "b")
    }

    func testLeastBusyTieBreaksByPoolOrder() {
        let pool = ["a", "b", "c"].map { DiscoveredModel(modelName: $0, backend: .ollama, endpoint: "e") }
        let health = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, true) })
        let lb = LoadBalancer()
        XCTAssertEqual(lb.next(pool: pool, health: health, policy: .leastBusy)?.modelName, "a")
    }

    func testCheckInNeverGoesNegative() {
        let lb = LoadBalancer()
        lb.checkIn("x")
        XCTAssertEqual(lb.inFlight["x"], 0)
        lb.checkOut("x"); lb.checkIn("x"); lb.checkIn("x")
        XCTAssertEqual(lb.inFlight["x"], 0)
    }

    // MARK: - Health gating

    func testHealthMapExcludesUnhealthy() {
        let pool = ["a", "b", "c"].map { DiscoveredModel(modelName: $0, backend: .ollama, endpoint: "e") }
        let lb = LoadBalancer()
        let health = [pool[1].id: false]
        let picked = (0..<4).map { _ in lb.next(pool: pool, health: health, policy: .roundRobin)!.modelName }
        XCTAssertFalse(picked.contains("b"))
        XCTAssertEqual(Set(picked), ["a", "c"])
    }

    func testAllUnhealthyReturnsNil() {
        let pool = ["a", "b"].map { DiscoveredModel(modelName: $0, backend: .ollama, endpoint: "e") }
        let health = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, false) })
        let lb = LoadBalancer()
        XCTAssertNil(lb.next(pool: pool, health: health, policy: .roundRobin))
        XCTAssertNil(lb.next(pool: pool, health: health, policy: .leastBusy))
    }

    func testEmptyPoolReturnsNil() {
        let lb = LoadBalancer()
        XCTAssertNil(lb.next(pool: [], health: [:], policy: .roundRobin))
    }

    // MARK: - Backend type

    func testNovaGatewayBackendType() {
        XCTAssertEqual(LLMBackendType.novaGateway.rawValue, "novagateway")
        XCTAssertEqual(LLMBackendType.novaGateway.displayName, "Nova Gateway")
        XCTAssertEqual(LLMBackendType.novaGateway.defaultURL, "http://127.0.0.1:18792")
        XCTAssertFalse(LLMBackendType.novaGateway.icon.isEmpty)
        XCTAssertEqual(LLMBackendType.allCases.count, 8)
    }
}

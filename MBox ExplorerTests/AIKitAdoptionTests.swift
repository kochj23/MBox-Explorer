//
//  AIKitAdoptionTests.swift
//  MBox ExplorerTests
//
//  MBox Explorer's contract with NovaAIKit 1.0.0, in the seven test categories: security, performance, retry,
//  unit, integration, functional and frame (UI state). Nothing here touches the real Keychain or the network:
//  every NovaAI uses an in-memory store and key store and a URLSession whose protocol answers locally.
//

import XCTest
import SwiftUI
import NovaAIKit
@testable import MBox_Explorer

// MARK: - Test support

/// Fails every request (every backend down).
final class RefuseAllProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)) }
    override func stopLoading() {}
}

/// Answers like Ollama: `/api/tags` lists one model, `/api/chat` returns the next scripted reply (or status code).
final class OllamaStubProtocol: URLProtocol {
    enum Reply { case text(String), status(Int) }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [Reply] = []
    nonisolated(unsafe) private(set) static var chatCalls = 0

    static func script(_ r: [Reply]) {
        lock.lock(); replies = r; chatCalls = 0; lock.unlock()
    }

    private static func nextReply() -> Reply {
        lock.lock(); defer { lock.unlock() }
        chatCalls += 1
        return replies.isEmpty ? .text("ok") : replies.removeFirst()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "http://localhost")!
        var status = 200
        var body = Data()
        if url.path.hasSuffix("/api/tags") {
            body = Data(#"{"models":[{"name":"stub-model:latest"}]}"#.utf8)
        } else {
            switch Self.nextReply() {
            case .text(let t):
                let content = (try? JSONSerialization.data(withJSONObject: [t], options: [.fragmentsAllowed]))
                    .flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "\"\""
                body = Data(#"{"model":"stub-model","message":{"role":"assistant","content":\#(content)},"done":true}"#.utf8)
            case .status(let s):
                status = s
            }
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
enum AITestKit {
    static func session(_ proto: AnyClass) -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [proto]
        return URLSession(configuration: cfg)
    }

    /// A NovaAI wired like AppAI but fully local.
    static func makeAI(_ s: NovaAISettings = NovaAISettings(),
                       keys: NovaAIMemoryKeyStore = NovaAIMemoryKeyStore(),
                       proto: AnyClass = RefuseAllProtocol.self) -> NovaAI {
        NovaAI(configuration: NovaAIConfiguration(appID: AppAI.appID, appName: AppAI.appName),
               storage: NovaAIMemoryStorage(s), keyStore: keys,
               session: session(proto), sleep: { _ in })
    }

    /// Ollama only, so the stub decides every answer.
    static func ollamaAI(keys: NovaAIMemoryKeyStore = NovaAIMemoryKeyStore()) -> NovaAI {
        makeAI(NovaAISettings(backend: .ollama), keys: keys, proto: OllamaStubProtocol.self)
    }

    static func email(body: String = "Hi team,\nThe budget review is on Friday.\nPlease send numbers by Thursday.\nThanks") -> Email {
        Email(from: "alice@example.com", subject: "Budget review", date: "Mon, 3 Nov 2026 09:00:00 -0800", body: body)
    }

    static func throwaway() -> UserDefaults {
        let name = "mboxexplorer.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
}

// MARK: - 1. Security

@MainActor
final class AIKitSecurityTests: XCTestCase {
    /// Feature 4: keys live only in the Keychain under com.jkoch.mboxexplorer.<backend>.
    func testKeychainServiceNames() {
        let c = AppAI.configuration
        XCTAssertEqual(c.keychainService(for: .openRouter), "com.jkoch.mboxexplorer.openrouter")
        XCTAssertEqual(c.keychainService(for: .openAI), "com.jkoch.mboxexplorer.openai")
        XCTAssertEqual(c.keychainService(for: .openWebUI), "com.jkoch.mboxexplorer.openwebui")
        XCTAssertEqual(NovaAIConfiguration.keychainAccount, "apiKey")
    }

    /// Step 3 (security fix): a plaintext OpenAI key in UserDefaults moves to the Keychain and leaves UserDefaults;
    /// the removed Google/Azure/AWS/IBM secrets are deleted.
    func testPlaintextKeysLeaveUserDefaults() {
        let d = AITestKit.throwaway()
        d.set("sk-test-plaintext", forKey: "AIBackend_OpenAI_Key")
        d.set("google-secret", forKey: "AIBackend_GoogleCloud_Key")
        d.set("aws-secret", forKey: "AIBackend_AWS_SecretKey")
        let keys = NovaAIMemoryKeyStore()
        let ai = AITestKit.makeAI(keys: keys)
        AppAI.migrateLegacy(ai, defaults: d, credentialsFile: nil)
        XCTAssertNil(d.object(forKey: "AIBackend_OpenAI_Key"))
        XCTAssertNil(d.object(forKey: "AIBackend_GoogleCloud_Key"))
        XCTAssertNil(d.object(forKey: "AIBackend_AWS_SecretKey"))
        XCTAssertEqual(keys.read(service: "com.jkoch.mboxexplorer.openai", account: "apiKey"), "sk-test-plaintext")
    }

    /// Step 3b/3c: the old com.jordankoch.MBoxExplorer items move (OpenAI) or are deleted (removed backends);
    /// the OpenWebUI embedding key (not chat AI) is left alone.
    func testLegacyKeychainItemsMigrate() {
        let old = AppAI.legacyKeychainService
        let keys = NovaAIMemoryKeyStore()
        _ = keys.write("sk-old", service: old, account: "openAIAPIKey")
        _ = keys.write("g", service: old, account: "googleCloudAPIKey")
        _ = keys.write("embed", service: old, account: "OpenWebUIEmbedding_APIKey")
        let ai = AITestKit.makeAI(keys: keys)
        AppAI.migrateLegacy(ai, defaults: AITestKit.throwaway(), credentialsFile: nil)
        XCTAssertEqual(ai.keys.key(for: .openAI), "sk-old")
        XCTAssertNil(keys.read(service: old, account: "openAIAPIKey"), "legacy OpenAI item is MBox Explorer's alone: deleted after a verified copy")
        XCTAssertNil(keys.read(service: old, account: "googleCloudAPIKey"))
        XCTAssertEqual(keys.read(service: old, account: "OpenWebUIEmbedding_APIKey"), "embed")
    }

    /// The old plaintext cloud_credentials.json: OpenAI key → Keychain, file deleted.
    func testPlaintextCredentialsFileIsRemoved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("cloud_credentials.json")
        try Data(#"{"openai":{"apiKey":"sk-file"},"google":{"apiKey":"g"}}"#.utf8).write(to: file)
        let ai = AITestKit.makeAI()
        AppAI.migrateCredentialsFile(file, ai: ai)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(ai.keys.key(for: .openAI), "sk-file")
    }

    /// Keys are never sent over plain http (except a local OpenWebUI).
    func testKeyedBackendsRefuseInsecureTransport() async {
        let keys = NovaAIMemoryKeyStore()
        var s = NovaAISettings(backend: .openRouter)
        s.setURL("http://openrouter.example.com/api/v1", for: .openRouter)
        let ai = AITestKit.makeAI(s, keys: keys, proto: OllamaStubProtocol.self)
        XCTAssertTrue(ai.setAPIKey("sk-or-test", for: .openRouter))
        do {
            _ = try await ai.complete(NovaAIRequest(prompt: "hi"))
            XCTFail("expected insecure transport to be refused")
        } catch {
            XCTAssertTrue("\(error)".contains("insecureTransport"), "\(error)")
        }
    }

    /// No old AI client code is left in the app's sources.
    func testNoLegacyAIClientInSources() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MBox Explorer")
        let banned = ["AIBackendManager", "EthicalAIGuardian", "AIBackendStatusMenu", "OPENAI_API_KEY",
                      "AIBackend_OpenAI_Key", "OllamaClient", "BalancedLLMManager", "OpenRouterProvider",
                      "UnifiedAICapabilities"]
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 50)
        for file in files where file.lastPathComponent != "AppAI.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for word in banned {
                XCTAssertFalse(text.contains(word), "\(file.lastPathComponent) still mentions \(word)")
            }
        }
    }
}

// MARK: - 2. Performance

final class AIKitPerformanceTests: XCTestCase {
    func testValidatorIsFastOnLongReplies() {
        let reply = "<think>planning</think>" + String(repeating: "The budget review is on Friday 14. ", count: 2_000)
        measure {
            for _ in 0..<20 { _ = try? AppAI.validText(reply) }
        }
    }

    func testGroundingCheckIsFastOnLargeSources() {
        let source = (1...5_000).map { "Invoice \($0) for $\($0 * 3).50" }.joined(separator: "\n")
        let text = "Invoices 120 and 4500 total $13500.50."
        measure {
            for _ in 0..<20 { _ = AppAI.inventedFigures(in: text, source: source) }
        }
    }

    @MainActor
    func testOfflineFallbackDoesNotHang() async {
        let ai = AITestKit.makeAI()            // every backend refuses; sleep is a no-op
        let start = Date()
        let summary = await AISummarizer(ai: ai).summarize(email: AITestKit.email())
        XCTAssertTrue(summary.isFallback)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "fallback must not wait on timeouts")
    }
}

// MARK: - 3. Retry

@MainActor
final class AIKitRetryTests: XCTestCase {
    /// Feature 7: a transient 503 is retried and the reply is used.
    func testTransientServerErrorIsRetried() async throws {
        OllamaStubProtocol.script([.status(503), .text("Recovered reply")])
        let reply = try await AppAI.ask(prompt: "hello", ai: AITestKit.ollamaAI())
        XCTAssertEqual(reply, "Recovered reply")
        XCTAssertEqual(OllamaStubProtocol.chatCalls, 2)
    }

    /// Feature 8: a rejected reply is re-asked once with the complaint; the second reply is used.
    func testRejectedReplyIsReAskedOnce() async {
        OllamaStubProtocol.script([.text("Revenue was 98765 dollars."), .text("Budget review on Friday; send numbers by Thursday.")])
        let result = await AISummarizer(ai: AITestKit.ollamaAI()).summarize(email: AITestKit.email())
        XCTAssertFalse(result.isFallback)
        XCTAssertEqual(result.summary, "Budget review on Friday; send numbers by Thursday.")
        XCTAssertEqual(OllamaStubProtocol.chatCalls, 2)
    }

    /// Rejected twice → built-in result, with the reason.
    func testRejectedTwiceFallsBack() async {
        OllamaStubProtocol.script([.text("Revenue was 98765 dollars."), .text("Revenue was 98765 dollars.")])
        let result = await AISummarizer(ai: AITestKit.ollamaAI()).summarize(email: AITestKit.email())
        XCTAssertTrue(result.isFallback)
        XCTAssertTrue(result.unavailableReason?.contains("rejected") == true)
        XCTAssertTrue(result.summary.hasPrefix("Hi team,"))
    }
}

// MARK: - 4. Unit

final class AIKitUnitTests: XCTestCase {
    func testValidTextStripsReasoningAndRejectsEmpty() throws {
        XCTAssertEqual(try AppAI.validText("<think>x</think>  Hello  "), "Hello")
        XCTAssertThrowsError(try AppAI.validText("<think>only thinking</think>"))
        XCTAssertThrowsError(try AppAI.validText("   \n "))
        XCTAssertEqual(try AppAI.validText(String(repeating: "a", count: 20_000)).count, AppAI.maxReplyCharacters)
    }

    func testInventedFiguresAllowsSmallCountsAndSourceNumbers() {
        XCTAssertEqual(AppAI.inventedFigures(in: "3 action items, due 2026", source: "Due in 2026"), [])
        XCTAssertEqual(AppAI.inventedFigures(in: "Total 4,500 and 99", source: "4500"), ["99"])
    }

    func testSummaryValidatorRejectsNonsense() throws {
        let v = SummarizationRequest.validator(source: "Meeting Friday at 10. Budget 25000.")
        XCTAssertEqual(try v("**Meeting** Friday at 10; budget 25,000."), "Meeting Friday at 10; budget 25,000.")
        XCTAssertThrowsError(try v("Budget is 99999."))
        XCTAssertThrowsError(try v(""))
        XCTAssertLessThanOrEqual(try v(String(repeating: "word ", count: 1000)).count, SummarizationRequest.maxSummaryCharacters)
    }

    func testRAGValidatorChecksFiguresOnlyForStatistics() throws {
        let stats = LocalLLM.answerValidator(for: .statistics, source: "Total emails: 1234")
        XCTAssertEqual(try stats("There are 1234 emails."), "There are 1234 emails.")
        XCTAssertThrowsError(try stats("There are 5678 emails."))
        let content = LocalLLM.answerValidator(for: .contentSearch, source: "x")
        XCTAssertNoThrow(try content("Alice mentioned 5678 widgets."))
    }

    func testEmbeddingRoundRobinWraps() {
        var rr = EmbeddingRoundRobin()
        XCTAssertNil(rr.next(from: []))
        XCTAssertEqual((0..<5).compactMap { _ in rr.next(from: ["a", "b"]) }, ["a", "b", "a", "b", "a"])
    }

    func testBackendCatalogue() {
        XCTAssertEqual(NovaAIBackend.allCases.count, 9)
        XCTAssertEqual(NovaAIBackend.selectable.first, .auto)
        XCTAssertTrue(NovaAIBackend.openRouter.requiresKey)
        XCTAssertFalse(NovaAIBackend.ollama.requiresKey)
    }

    func testUnavailableErrorMessages() {
        XCTAssertTrue(AppAIUnavailable(reason: .disabled).localizedDescription.contains("turned off"))
        XCTAssertTrue(AppAIUnavailable(reason: .unavailable("down")).localizedDescription.contains("down"))
        XCTAssertTrue(AppAIUnavailable(reason: .validationFailed("bad")).localizedDescription.contains("rejected"))
    }
}

// MARK: - 5. Integration

@MainActor
final class AIKitIntegrationTests: XCTestCase {
    /// The summarizer goes through the kit to Ollama and labels the source.
    func testSummaryComesFromAIWhenOnline() async {
        OllamaStubProtocol.script([.text("<think>hmm</think>Budget review Friday; numbers due Thursday.")])
        let result = await AISummarizer(ai: AITestKit.ollamaAI()).summarize(email: AITestKit.email())
        XCTAssertFalse(result.isFallback)
        XCTAssertEqual(result.summary, "Budget review Friday; numbers due Thursday.")
        XCTAssertTrue(result.sourceLabel.contains("Ollama"), result.sourceLabel)
    }

    /// Step 3: the old AIBackendManager + balancer settings land in NovaAISettings once.
    func testLegacySettingsMigrate() {
        let d = AITestKit.throwaway()
        d.set("Ollama", forKey: "AIBackendManager_SelectedBackend")
        d.set("llama3.2:latest", forKey: "AIBackendManager_OllamaModel")
        d.set("http://tinychat.local:8000", forKey: "AIBackendManager_TinyChatServerURL")
        d.set("anthropic/claude-sonnet-4.5", forKey: "Balancer_SelectedOpenRouterModel")
        d.set(true, forKey: "Balancer_UseAllLocalModels")
        let ai = AITestKit.makeAI()
        AppAI.migrateLegacy(ai, defaults: d, credentialsFile: nil)
        XCTAssertEqual(ai.settings.backend, .ollama)
        XCTAssertEqual(ai.settings.model(for: .ollama), "llama3.2:latest")
        XCTAssertEqual(ai.settings.url(for: .tinyChat), "http://tinychat.local:8000")
        XCTAssertEqual(ai.settings.model(for: .openRouter), "anthropic/claude-sonnet-4.5")
        XCTAssertNil(d.object(forKey: "Balancer_UseAllLocalModels"))
        XCTAssertNil(d.object(forKey: "AIBackendManager_TinyChatServerURL"))
        // Runs once: a later change is not overwritten.
        ai.settings.backend = .tinyChat
        AppAI.migrateLegacy(ai, defaults: d, credentialsFile: nil)
        XCTAssertEqual(ai.settings.backend, .tinyChat)
    }

    /// Auto failover: Ollama down → the next reachable backend answers (TinyChat here, OpenAI-compatible).
    func testAutoFailsOverPastADeadBackend() async throws {
        OllamaStubProtocol.script([.status(500), .status(500), .text("from the next backend")])
        let ai = AITestKit.makeAI(NovaAISettings(backend: .auto), proto: OllamaStubProtocol.self)
        let response = try await ai.complete(NovaAIRequest(prompt: "hi"))
        XCTAssertNotEqual(response.backend, .ollama)
    }
}

// MARK: - 6. Functional

@MainActor
final class AIKitFunctionalTests: XCTestCase {
    /// Feature 1+2: AI off → every AI path produces its built-in result and nothing is sent.
    func testEveryFeatureWorksWithAIOff() async {
        OllamaStubProtocol.script([])
        let ai = AITestKit.makeAI(NovaAISettings(enabled: false, backend: .ollama), proto: OllamaStubProtocol.self)

        let summary = await AISummarizer(ai: ai).summarize(email: AITestKit.email())
        XCTAssertTrue(summary.isFallback)
        XCTAssertEqual(summary.sourceLabel, "Built-in")
        XCTAssertTrue(summary.unavailableReason?.contains("turned off") == true)
        XCTAssertFalse(summary.summary.isEmpty)

        do {
            _ = try await AppAI.ask(prompt: "Analyze", ai: ai)
            XCTFail("AI off must not return an AI value")
        } catch {
            XCTAssertEqual(error as? AppAIUnavailable, AppAIUnavailable(reason: .disabled))
        }

        let text = await AppAI.text(prompt: "Reply", ai: ai, fallback: { "template" })
        XCTAssertEqual(text.value, "template")
        XCTAssertEqual(OllamaStubProtocol.chatCalls, 0, "nothing is sent when AI is off")
    }

    /// Feature 2+7: every backend down → built-in results, no hang.
    func testEveryFeatureFallsBackWhenOffline() async {
        let ai = AITestKit.makeAI()
        let summary = await AISummarizer(ai: ai).summarize(email: AITestKit.email())
        XCTAssertTrue(summary.isFallback)
        XCTAssertTrue(summary.unavailableReason?.contains("No AI backend answered") == true)
        let text = await AppAI.text(prompt: "x", ai: ai, fallback: { "built-in" })
        XCTAssertEqual(text.value, "built-in")
        XCTAssertFalse(text.isAI)
    }

    /// Built-in answers the app shows without AI.
    func testBuiltInAnswers() {
        let results = [SearchResult(emailId: "1", content: "c", from: "bob@example.com", subject: "Q3 plan", date: "2026-10-01", snippet: "s", score: 0.9)]
        let answer = ConversationManager.builtInAnswer(reason: "AI is turned off (Settings › AI).", results: results)
        XCTAssertTrue(answer.contains("bob@example.com"))
        XCTAssertTrue(answer.contains("Q3 plan"))
        XCTAssertTrue(ConversationManager.builtInAnswer(reason: "r", results: []).contains("No matching emails"))
        XCTAssertTrue(LocalLLM.generateBasicAnswer("q", context: results).contains("Q3 plan"))
        XCTAssertEqual(LocalLLM.generateBasicSummary("Line one\nLine two"), "Line one Line two")
        XCTAssertFalse(SmartReplyGenerator.meetingTemplate(.decline).isEmpty)
        XCTAssertEqual(AISummarizer.basicSummary(""), "")
    }
}

// MARK: - 7. Frame / UI state

@MainActor
final class AIKitFrameTests: XCTestCase {
    func testSettingsViewRendersInAFrame() {
        let host = NSHostingView(rootView: AISettingsView(ai: AITestKit.makeAI(), onClose: {}))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 700)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }

    func testStatusIndicatorStates() {
        let ai = AITestKit.makeAI(NovaAISettings(enabled: false))
        XCTAssertEqual(ai.status.state, .off)
        ai.isEnabled = true
        XCTAssertEqual(ai.status.state, .unknown)
        XCTAssertNotEqual(NovaAIStatusIndicator.color(.online), NovaAIStatusIndicator.color(.offline))
        let host = NSHostingView(rootView: NovaAIStatusIndicator(ai: ai, checksOnAppear: false))
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }

    func testOfflineStatusAfterRefresh() async {
        let ai = AITestKit.makeAI(NovaAISettings(backend: .ollama))
        await ai.refreshStatus()
        XCTAssertEqual(ai.status.state, .offline)
        XCTAssertNil(ai.status.activeBackend)
    }

    func testSummarySheetStateFlags() {
        let ai = AISummary(summary: "s", sourceLabel: "AI · Ollama (m)", unavailableReason: nil)
        let builtIn = AISummary(summary: "s", sourceLabel: "Built-in", unavailableReason: "AI is turned off")
        XCTAssertFalse(ai.isFallback)
        XCTAssertTrue(builtIn.isFallback)
    }
}

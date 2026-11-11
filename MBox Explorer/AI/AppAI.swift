//
//  AppAI.swift
//  MBox Explorer
//
//  The app's one AI object (NovaAIKit 1.0.0). Settings persist in UserDefaults (no secrets); API keys live only in
//  the Keychain under com.jkoch.mboxexplorer.<backend>. Every AI feature in the app goes through here and keeps a
//  built-in (non-AI) result for when AI is off, unreachable, or returns something unusable.
//
//  Author: Jordan Koch
//

import Foundation
import NovaAIKit

@MainActor
enum AppAI {
    static let appID = "mboxexplorer"
    static let appName = "MBox Explorer"

    static let configuration = NovaAIConfiguration(appID: appID, appName: appName)

    static let shared: NovaAI = {
        let ai = NovaAI(configuration: configuration)
        AppAI.migrateLegacy(ai)
        return ai
    }()

    /// Shown under the AI settings.
    static let settingsFooter = "When AI is off or unreachable, MBox Explorer still works: summaries fall back to the "
        + "first lines of the message, Ask shows the matching emails, extractors use their keyword rules, and the "
        + "analysis tools say why AI was not used. Semantic search embeddings are configured separately below."
}

// MARK: - One-shot requests used by the feature classes

/// Thrown by `AppAI.ask` when no AI value can be used. The message says why (AI off / unreachable / bad reply),
/// so each feature's existing `catch` shows a reason or its built-in result.
struct AppAIUnavailable: LocalizedError, Equatable {
    let reason: NovaAIFallbackReason

    var errorDescription: String? {
        switch reason {
        case .disabled: return "AI is turned off (Settings › AI)."
        case .unavailable(let why): return "AI is unavailable: \(why)"
        case .validationFailed(let why): return "AI reply was rejected: \(why)"
        }
    }
}

extension AppAI {
    /// Longest reply any feature accepts (characters).
    nonisolated static let maxReplyCharacters = 12_000

    /// The default validator for generated text: removes reasoning blocks, rejects empty replies, caps the length.
    nonisolated static let validText: @Sendable (String) throws -> String = { raw in
        guard let text = NovaAIText.clean(raw, max: maxReplyCharacters) else {
            throw NovaAIValidationError("empty reply")
        }
        return text
    }

    /// Figures in `text` that do not appear in `source` (small counts up to 20, list markers and the like, are allowed).
    /// Empty = grounded. Used to reject invented numbers (dates, amounts, counts) in summaries and answers.
    nonisolated static func inventedFigures(in text: String, source: String) -> [String] {
        NovaAIText.numbers(text).subtracting(NovaAIText.numbers(source))
            .filter { (Double($0) ?? 0) > 20 }
            .sorted()
    }

    /// One prompt → validated text, with the kit's toggle, Auto failover, retries and one re-ask on a rejected reply.
    /// Throws `AppAIUnavailable` instead of returning a fallback, so callers keep their own built-in path in `catch`.
    static func ask(prompt: String,
                    systemPrompt: String? = nil,
                    temperature: Double = 0.7,
                    maxTokens: Int = 2048,
                    validate: @escaping @Sendable (String) throws -> String = AppAI.validText,
                    ai: NovaAI? = nil) async throws -> String {
        let request = NovaAIRequest(prompt: prompt, system: systemPrompt, temperature: temperature, maxTokens: maxTokens)
        let result = await (ai ?? shared).generate(request,
                                                    validate: { Optional(try validate($0)) },
                                                    fallback: { nil })
        if let value = result.value { return value }
        if case .fallback(let reason) = result.source { throw AppAIUnavailable(reason: reason) }
        throw AppAIUnavailable(reason: .unavailable("no reply"))
    }

    /// Never-throwing text: the AI reply, or `fallback()` (AI off / down / rejected). The result says which.
    static func text(prompt: String,
                     systemPrompt: String? = nil,
                     temperature: Double = 0.3,
                     maxTokens: Int = 1024,
                     validate: @escaping @Sendable (String) throws -> String = AppAI.validText,
                     ai: NovaAI? = nil,
                     fallback: @escaping @Sendable () -> String) async -> NovaAIResult<String> {
        await (ai ?? shared).text(NovaAIRequest(prompt: prompt, system: systemPrompt, temperature: temperature, maxTokens: maxTokens),
                                  validate: validate, fallback: fallback)
    }

    /// A short label for UI: "Ollama (qwen3:8b)" when online, otherwise nil.
    static var activeBackendLabel: String? {
        guard shared.status.isReachable, let b = shared.status.activeBackend else { return nil }
        if let m = shared.status.activeModel { return "\(b.displayName) (\(m))" }
        return b.displayName
    }
}

// MARK: - One-time migration of the old AIBackendManager / balancer settings and keys

extension AppAI {
    /// The Keychain service the pre-NovaAIKit versions used.
    nonisolated static let legacyKeychainService = "com.jordankoch.MBoxExplorer"
    /// Marker so the app-specific part below runs once.
    nonisolated static let legacyMigrationMarker = "MBoxExplorer.NovaAIKitMigrated"

    /// MBox Explorer's own old UserDefaults keys (its AIBackendManager, Ollama settings sheet and load balancer).
    nonisolated static let legacyURLKeys: [String: NovaAIBackend] = [
        "AIBackendManager_TinyLLMServerURL": .tinyLLM,
        "AIBackendManager_TinyChatServerURL": .tinyChat,
        "AIBackendManager_OpenWebUIServerURL": .openWebUI,
        "ollamaServerURL": .ollama,
        "Balancer_NovaGatewayURL": .novaGateway,
    ]
    /// Keys with no successor (the old python-MLX path, temperature sliders, balancer toggles); deleted.
    nonisolated static let legacyObsoleteKeys = [
        "AIBackendManager_SelectedBackend", "AIBackendManager_OllamaModel", "AIBackendManager_PythonPath",
        "AIBackendManager_MLXScriptPath", "AIBackendManager_TinyLLMServerURL", "AIBackendManager_TinyChatServerURL",
        "AIBackendManager_OpenWebUIServerURL", "AIBackendManager_QuestionTemperature",
        "AIBackendManager_SummaryTemperature", "AIBackendManager_CreativeTemperature",
        "ollamaServerURL", "ollamaLLMModel", "ollamaTemperature", "ollamaMaxTokens",
        "Balancer_UseAllLocalModels", "Balancer_EnableAllFrontierModels", "Balancer_UseNovaGateway",
        "Balancer_NovaGatewayURL", "Balancer_SelectedOpenRouterModel",
    ]

    /// Where old versions kept cloud API keys in plaintext JSON (OpenAI + the removed Google/Azure/AWS/IBM backends).
    nonisolated static var legacyCredentialsURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MBoxExplorer/cloud_credentials.json")
    }

    /// Runs once per install. Security fix: plaintext keys (UserDefaults, cloud_credentials.json) move to the
    /// Keychain and the plaintext copies are deleted; the removed cloud backends' secrets are deleted.
    static func migrateLegacy(_ ai: NovaAI, defaults: UserDefaults = .standard, credentialsFile: URL? = AppAI.legacyCredentialsURL) {
        // 3a. Generic AIBackendManager keys (backend, Ollama model, on/off, plaintext OpenAI key, obsolete secrets).
        ai.migrateFromLegacyAIBackendManager(defaults: defaults)

        // 3b. Old Keychain items → com.jkoch.mboxexplorer.<backend>.
        ai.migrateLegacyKey(service: legacyKeychainService, account: "openAIAPIKey", to: .openAI, deleteLegacy: true)
        // The OpenRouter key already lives at com.jkoch.mboxexplorer.openrouter / apiKey (the kit's name): nothing to do.

        // 3c. Removed backends' Keychain secrets.
        ai.keys.deleteObsoleteLegacyItems(service: legacyKeychainService)

        // Old versions could save an embedding model (e.g. nomic-embed-text) as the chat model; it cannot chat.
        dropEmbeddingChatModels(ai)

        // App-specific settings, once.
        guard !defaults.bool(forKey: legacyMigrationMarker) else { return }
        defaults.set(true, forKey: legacyMigrationMarker)
        var s = ai.settings
        for (key, backend) in legacyURLKeys {
            if let v = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty,
               s.urls[backend.rawValue] == nil, v != backend.defaultURL {
                s.setURL(v, for: backend)
            }
        }
        if let m = defaults.string(forKey: "Balancer_SelectedOpenRouterModel"), !m.isEmpty, s.models[NovaAIBackend.openRouter.rawValue] == nil {
            s.setModel(m, for: .openRouter)
        }
        if s != ai.settings { ai.settings = s }
        dropEmbeddingChatModels(ai)
        legacyObsoleteKeys.forEach { defaults.removeObject(forKey: $0) }
        migrateCredentialsFile(credentialsFile, ai: ai)
    }

    /// True for model names that are embedding-only (they cannot answer chat requests).
    nonisolated static func isEmbeddingModel(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("embed") || n.hasPrefix("bge-") || n.contains("/bge-") || n.contains("minilm")
    }

    /// Resets a chat model setting that names an embedding model back to the backend default.
    static func dropEmbeddingChatModels(_ ai: NovaAI) {
        var s = ai.settings
        for (backend, model) in s.models where isEmbeddingModel(model) {
            s.models.removeValue(forKey: backend)
        }
        if s != ai.settings { ai.settings = s }
    }

    /// Moves the OpenAI key out of the old plaintext credentials file into the Keychain, then deletes the file
    /// (it only ever held cloud keys). The file is kept if the Keychain write fails.
    static func migrateCredentialsFile(_ url: URL?, ai: NovaAI) {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        var keepFile = false
        if let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let openai = json["openai"] as? [String: Any],
           let key = (openai["apiKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty,
           !ai.hasAPIKey(for: .openAI) {
            keepFile = !ai.setAPIKey(key, for: .openAI)
        }
        if !keepFile { try? FileManager.default.removeItem(at: url) }
    }
}

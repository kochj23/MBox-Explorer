//
//  AIBackendManager.swift
//  Universal AI Backend Manager
//
//  Drop-in component for Ollama + MLX + TinyLLM support
//  Author: Jordan Koch
//  Date: 2025-01-17
//
//  THIRD-PARTY INTEGRATIONS:
//  - TinyLLM by Jason Cox (https://github.com/jasonacox/TinyLLM)
//    Lightweight LLM server with OpenAI-compatible API
//
//  HOW TO USE:
//  1. Copy this file into your project
//  2. Replace direct MLX/Ollama/TinyLLM calls with AIBackendManager.shared
//  3. Add AIBackendSettingsView to your settings/preferences
//  4. User can switch between Ollama, MLX, and TinyLLM in settings
//

import Foundation
import SwiftUI
import Combine

// MARK: - AI Backend Type

enum AIBackend: String, Codable, CaseIterable {
    case ollama = "Ollama"
    case mlx = "MLX Toolkit"
    case tinyLLM = "TinyLLM"
    case auto = "Auto (Prefer Ollama)"

    var icon: String {
        switch self {
        case .ollama: return "network"
        case .mlx: return "cpu"
        case .tinyLLM: return "cube"
        case .auto: return "sparkles"
        }
    }

    var description: String {
        switch self {
        case .ollama:
            return "HTTP-based API (Ollama running on localhost:11434)"
        case .mlx:
            return "Python MLX Toolkit (runs models locally via Python)"
        case .tinyLLM:
            return "TinyLLM lightweight server (localhost:8000)"
        case .auto:
            return "Automatically choose best available backend"
        }
    }
}

// MARK: - AI Backend Manager

@MainActor
class AIBackendManager: ObservableObject {
    static let shared = AIBackendManager()

    // MARK: - Published Properties

    @Published var selectedBackend: AIBackend = .auto
    @Published var activeBackend: AIBackend? = nil
    @Published var isOllamaAvailable = false
    @Published var isMLXAvailable = false
    @Published var isTinyLLMAvailable = false
    @Published var isProcessing = false
    @Published var lastError: String? = nil

    // Ollama-specific
    @Published var ollamaModels: [String] = []
    @Published var selectedOllamaModel: String = "llama2"

    // MLX-specific
    @Published var pythonPath: String = "/opt/homebrew/bin/python3"
    @Published var mlxScriptPath: String = ""

    // TinyLLM-specific
    @Published var tinyLLMServerURL: String = "http://localhost:8000"

    // MARK: - Private Properties

    private let userDefaults = UserDefaults.standard
    private let ollamaBaseURL = "http://localhost:11434"

    private enum Keys {
        static let selectedBackend = "AIBackendManager_SelectedBackend"
        static let ollamaModel = "AIBackendManager_OllamaModel"
        static let pythonPath = "AIBackendManager_PythonPath"
        static let mlxScriptPath = "AIBackendManager_MLXScriptPath"
        static let tinyLLMServerURL = "AIBackendManager_TinyLLMServerURL"
    }

    // MARK: - Initialization

    private init() {
        loadSettings()
        Task {
            await checkBackendAvailability()
        }
    }

    // MARK: - Settings Management

    private func loadSettings() {
        if let backendRaw = userDefaults.string(forKey: Keys.selectedBackend),
           let backend = AIBackend(rawValue: backendRaw) {
            selectedBackend = backend
        }

        selectedOllamaModel = userDefaults.string(forKey: Keys.ollamaModel) ?? "llama2"
        pythonPath = userDefaults.string(forKey: Keys.pythonPath) ?? "/opt/homebrew/bin/python3"
        mlxScriptPath = userDefaults.string(forKey: Keys.mlxScriptPath) ?? ""
        tinyLLMServerURL = userDefaults.string(forKey: Keys.tinyLLMServerURL) ?? "http://localhost:8000"
    }

    func saveSettings() {
        userDefaults.set(selectedBackend.rawValue, forKey: Keys.selectedBackend)
        userDefaults.set(selectedOllamaModel, forKey: Keys.ollamaModel)
        userDefaults.set(pythonPath, forKey: Keys.pythonPath)
        userDefaults.set(mlxScriptPath, forKey: Keys.mlxScriptPath)
        userDefaults.set(tinyLLMServerURL, forKey: Keys.tinyLLMServerURL)
    }

    // MARK: - Backend Availability Checking

    func checkBackendAvailability() async {
        async let ollamaCheck = checkOllamaAvailability()
        async let mlxCheck = checkMLXAvailability()
        async let tinyLLMCheck = checkTinyLLMAvailability()

        let (ollama, mlx, tinyLLM) = await (ollamaCheck, mlxCheck, tinyLLMCheck)

        isOllamaAvailable = ollama
        isMLXAvailable = mlx
        isTinyLLMAvailable = tinyLLM

        // Determine active backend
        determineActiveBackend()
    }

    private func determineActiveBackend() {
        switch selectedBackend {
        case .ollama:
            activeBackend = isOllamaAvailable ? .ollama : nil
        case .mlx:
            activeBackend = isMLXAvailable ? .mlx : nil
        case .tinyLLM:
            activeBackend = isTinyLLMAvailable ? .tinyLLM : nil
        case .auto:
            // Prefer Ollama, fallback to TinyLLM, then MLX
            if isOllamaAvailable {
                activeBackend = .ollama
            } else if isTinyLLMAvailable {
                activeBackend = .tinyLLM
            } else if isMLXAvailable {
                activeBackend = .mlx
            } else {
                activeBackend = nil
            }
        }
    }

    private func checkTinyLLMAvailability() async -> Bool {
        guard let url = URL(string: "\(tinyLLMServerURL)/") else {
            return false
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func checkOllamaAvailability() async -> Bool {
        guard let url = URL(string: "\(ollamaBaseURL)/api/tags") else {
            return false
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            // Parse available models
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let modelNames = models.compactMap { $0["name"] as? String }
                await MainActor.run {
                    self.ollamaModels = modelNames
                }
            }

            return true
        } catch {
            return false
        }
    }

    private func checkMLXAvailability() async -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: pythonPath)
        task.arguments = ["-c", "import mlx.core as mx; print('OK')"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Unified AI Interface

    /// Generate text completion using active backend
    func generate(
        prompt: String,
        systemPrompt: String? = nil,
        temperature: Float = 0.7,
        maxTokens: Int = 2048
    ) async throws -> String {
        guard let backend = activeBackend else {
            throw AIBackendError.noBackendAvailable
        }

        isProcessing = true
        defer { isProcessing = false }

        switch backend {
        case .ollama:
            return try await generateWithOllama(
                prompt: prompt,
                systemPrompt: systemPrompt,
                temperature: temperature,
                maxTokens: maxTokens
            )
        case .mlx:
            return try await generateWithMLX(
                prompt: prompt,
                systemPrompt: systemPrompt,
                temperature: temperature,
                maxTokens: maxTokens
            )
        case .tinyLLM:
            return try await generateWithTinyLLM(
                prompt: prompt,
                systemPrompt: systemPrompt,
                temperature: temperature,
                maxTokens: maxTokens
            )
        case .auto:
            throw AIBackendError.invalidState
        }
    }

    // MARK: - Ollama Implementation

    private func generateWithOllama(
        prompt: String,
        systemPrompt: String?,
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        guard let url = URL(string: "\(ollamaBaseURL)/api/generate") else {
            throw AIBackendError.invalidConfiguration
        }

        var requestBody: [String: Any] = [
            "model": selectedOllamaModel,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": temperature,
                "num_predict": maxTokens
            ]
        ]

        if let systemPrompt = systemPrompt {
            requestBody["system"] = systemPrompt
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct OllamaResponse: Codable {
            let response: String
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(OllamaResponse.self, from: data)
        return response.response
    }

    // MARK: - MLX Implementation

    private func generateWithMLX(
        prompt: String,
        systemPrompt: String?,
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        guard !mlxScriptPath.isEmpty else {
            throw AIBackendError.mlxScriptNotConfigured
        }

        // Build combined prompt
        var fullPrompt = ""
        if let systemPrompt = systemPrompt {
            fullPrompt += "System: \(systemPrompt)\n\n"
        }
        fullPrompt += "User: \(prompt)\n\nAssistant:"

        // Create Python MLX invocation
        let script = """
        import sys
        import json
        try:
            import mlx_lm

            prompt = '''
            \(fullPrompt)
            '''

            model, tokenizer = mlx_lm.load("mlx-community/Llama-3.2-1B-Instruct-4bit")

            response = mlx_lm.generate(
                model,
                tokenizer,
                prompt=prompt,
                max_tokens=\(maxTokens),
                temp=\(temperature),
                verbose=False
            )

            print(response)
        except Exception as e:
            print(json.dumps({"error": str(e)}), file=sys.stderr)
            sys.exit(1)
        """

        // Write script to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let scriptFile = tempDir.appendingPathComponent("mlx_generate_\(UUID().uuidString).py")
        try script.write(to: scriptFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: scriptFile)
        }

        // Execute Python script
        let task = Process()
        task.executableURL = URL(fileURLWithPath: pythonPath)
        task.arguments = [scriptFile.path]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw AIBackendError.mlxExecutionFailed(errorMessage)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - TinyLLM Implementation
    //
    // TinyLLM by Jason Cox: https://github.com/jasonacox/TinyLLM
    // A lightweight LLM server with OpenAI-compatible API
    // Runs in Docker container, provides /v1/chat/completions endpoint

    private func generateWithTinyLLM(
        prompt: String,
        systemPrompt: String?,
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        guard let url = URL(string: "\(tinyLLMServerURL)/v1/chat/completions") else {
            throw AIBackendError.invalidConfiguration
        }

        // Build messages array for OpenAI-compatible API
        var messages: [[String: String]] = []
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        let requestBody: [String: Any] = [
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct TinyLLMResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(TinyLLMResponse.self, from: data)
        return response.choices.first?.message.content ?? ""
    }

    // MARK: - Embeddings (for semantic search)

    func generateEmbeddings(text: String) async throws -> [Float] {
        guard let backend = activeBackend else {
            throw AIBackendError.noBackendAvailable
        }

        switch backend {
        case .ollama:
            return try await generateEmbeddingsWithOllama(text: text)
        case .mlx:
            return try await generateEmbeddingsWithMLX(text: text)
        case .tinyLLM:
            return try await generateEmbeddingsWithTinyLLM(text: text)
        case .auto:
            throw AIBackendError.invalidState
        }
    }

    private func generateEmbeddingsWithOllama(text: String) async throws -> [Float] {
        guard let url = URL(string: "\(ollamaBaseURL)/api/embeddings") else {
            throw AIBackendError.invalidConfiguration
        }

        let requestBody: [String: Any] = [
            "model": "nomic-embed-text", // Fixed embedding model
            "prompt": text
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct EmbeddingResponse: Codable {
            let embedding: [Float]
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(EmbeddingResponse.self, from: data)
        return response.embedding
    }

    private func generateEmbeddingsWithMLX(text: String) async throws -> [Float] {
        // MLX embeddings implementation would go here
        // For now, throw not implemented
        throw AIBackendError.embeddingsNotSupported
    }

    // TinyLLM embeddings via OpenAI-compatible API
    // TinyLLM by Jason Cox: https://github.com/jasonacox/TinyLLM
    private func generateEmbeddingsWithTinyLLM(text: String) async throws -> [Float] {
        guard let url = URL(string: "\(tinyLLMServerURL)/v1/embeddings") else {
            throw AIBackendError.invalidConfiguration
        }

        let requestBody: [String: Any] = [
            "input": text,
            "model": "text-embedding-ada-002" // TinyLLM compatible model
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        struct TinyLLMEmbeddingResponse: Codable {
            struct Data: Codable {
                let embedding: [Float]
            }
            let data: [Data]
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(TinyLLMEmbeddingResponse.self, from: data)
        return response.data.first?.embedding ?? []
    }
}

// MARK: - Errors

enum AIBackendError: LocalizedError {
    case noBackendAvailable
    case invalidConfiguration
    case invalidState
    case mlxScriptNotConfigured
    case mlxExecutionFailed(String)
    case embeddingsNotSupported

    var errorDescription: String? {
        switch self {
        case .noBackendAvailable:
            return "No AI backend available. Install Ollama or configure MLX."
        case .invalidConfiguration:
            return "AI backend configuration is invalid."
        case .invalidState:
            return "AI backend is in an invalid state."
        case .mlxScriptNotConfigured:
            return "MLX script path not configured."
        case .mlxExecutionFailed(let message):
            return "MLX execution failed: \(message)"
        case .embeddingsNotSupported:
            return "Embeddings not supported with current backend."
        }
    }
}

// MARK: - Settings View

struct AIBackendSettingsView: View {
    @ObservedObject var manager = AIBackendManager.shared
    @State private var isChecking = false

    var body: some View {
        Form {
            Section(header: Text("AI Backend Selection")) {
                Picker("Backend", selection: $manager.selectedBackend) {
                    ForEach(AIBackend.allCases, id: \.self) { backend in
                        HStack {
                            Image(systemName: backend.icon)
                            Text(backend.rawValue)
                        }
                        .tag(backend)
                    }
                }
                .onChange(of: manager.selectedBackend) { _ in
                    manager.saveSettings()
                    Task {
                        await manager.checkBackendAvailability()
                    }
                }

                Text(manager.selectedBackend.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Backend Status")) {
                HStack {
                    Circle()
                        .fill(manager.activeBackend != nil ? .green : .red)
                        .frame(width: 10, height: 10)

                    if let active = manager.activeBackend {
                        Text("Active: \(active.rawValue)")
                            .foregroundColor(.green)
                    } else {
                        Text("No backend available")
                            .foregroundColor(.red)
                    }
                }

                HStack {
                    Image(systemName: "network")
                    Text("Ollama")
                    Spacer()
                    Text(manager.isOllamaAvailable ? "Available" : "Unavailable")
                        .foregroundColor(manager.isOllamaAvailable ? .green : .secondary)
                }

                HStack {
                    Image(systemName: "cpu")
                    Text("MLX Toolkit")
                    Spacer()
                    Text(manager.isMLXAvailable ? "Available" : "Unavailable")
                        .foregroundColor(manager.isMLXAvailable ? .green : .secondary)
                }

                HStack {
                    Image(systemName: "cube")
                    Text("TinyLLM")
                    Spacer()
                    Text(manager.isTinyLLMAvailable ? "Available" : "Unavailable")
                        .foregroundColor(manager.isTinyLLMAvailable ? .green : .secondary)
                }

                Button("Refresh Status") {
                    isChecking = true
                    Task {
                        await manager.checkBackendAvailability()
                        isChecking = false
                    }
                }
                .disabled(isChecking)
            }

            if manager.isOllamaAvailable {
                Section(header: Text("Ollama Configuration")) {
                    Picker("Model", selection: $manager.selectedOllamaModel) {
                        ForEach(manager.ollamaModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .onChange(of: manager.selectedOllamaModel) { _ in
                        manager.saveSettings()
                    }

                    if manager.ollamaModels.isEmpty {
                        Text("No models found. Pull a model: ollama pull llama2")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            if manager.isMLXAvailable || manager.selectedBackend == .mlx {
                Section(header: Text("MLX Configuration")) {
                    TextField("Python Path", text: $manager.pythonPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: manager.pythonPath) { _ in
                            manager.saveSettings()
                        }

                    TextField("MLX Script Path (optional)", text: $manager.mlxScriptPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: manager.mlxScriptPath) { _ in
                            manager.saveSettings()
                        }
                }
            }

            if manager.isTinyLLMAvailable || manager.selectedBackend == .tinyLLM {
                Section(header: Text("TinyLLM Configuration")) {
                    TextField("Server URL", text: $manager.tinyLLMServerURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: manager.tinyLLMServerURL) { _ in
                            manager.saveSettings()
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("TinyLLM provides OpenAI-compatible API on localhost:8000")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Link("TinyLLM by Jason Cox", destination: URL(string: "https://github.com/jasonacox/TinyLLM")!)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }

            Section(header: Text("Setup Instructions")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ollama Setup:").bold()
                    Text("1. Install: brew install ollama")
                    Text("2. Start: ollama serve")
                    Text("3. Pull model: ollama pull llama2")

                    Divider().padding(.vertical, 4)

                    Text("TinyLLM Setup:").bold()
                    Text("By Jason Cox (GitHub: jasonacox/TinyLLM)")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("1. Clone: git clone https://github.com/jasonacox/TinyLLM")
                    Text("2. Run: docker-compose up -d")
                    Text("3. Access: http://localhost:8000")
                    Text("Note: Lightweight, OpenAI-compatible API")

                    Divider().padding(.vertical, 4)

                    Text("MLX Setup:").bold()
                    Text("1. Install Python: brew install python")
                    Text("2. Install MLX: pip install mlx-lm")
                    Text("3. Path: /opt/homebrew/bin/python3")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 600, minHeight: 600)
        .padding()
    }
}

// MARK: - Preview

#if DEBUG
struct AIBackendSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AIBackendSettingsView()
    }
}
#endif

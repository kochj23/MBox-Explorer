//
//  AISettingsView.swift
//  MBox Explorer
//
//  AI configuration settings with multiple backend support
//  Author: Jordan Koch
//  Date: 2025-01-17
//  Updated: 2026-01-30 - Added TinyChat, OpenWebUI, embedding provider selection
//

import SwiftUI

struct AISettingsView: View {
    @StateObject private var ollamaClient = OllamaClient()
    @StateObject private var embeddingManager = EmbeddingManager.shared
    @StateObject private var aiBackend = AIBackendManager.shared

    @State private var serverURL: String = ""
    @State private var selectedLLMModel: String = ""
    @State private var selectedEmbeddingModel: String = ""
    @State private var temperature: Float = 0.7
    @State private var maxTokens: Int = 2048
    @State private var showTestResult = false
    @State private var testResultMessage = ""
    @State private var isTestingConnection = false
    @State private var isPullingModel = false
    @State private var pullProgress = ""
    @State private var modelToPull = ""

    // TinyChat / OpenWebUI settings
    @State private var tinyChatURL: String = "http://localhost:8000"
    @State private var openWebUIURL: String = "http://localhost:8080"
    @State private var openWebUIAPIKey: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Embedding Provider Selection
                GroupBox(label: Label("Embedding Provider", systemImage: "brain.head.profile")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose how semantic search embeddings are generated")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Embedding Provider", selection: $embeddingManager.selectedProvider) {
                            ForEach(EmbeddingProviderType.allCases) { provider in
                                HStack {
                                    Text(provider.rawValue)
                                    if provider == embeddingManager.selectedProvider && embeddingManager.isAvailable {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                                .tag(provider)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())

                        HStack {
                            Circle()
                                .fill(embeddingManager.isAvailable ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(embeddingManager.statusMessage)
                                .font(.caption)
                                .foregroundColor(embeddingManager.isAvailable ? .green : .orange)
                        }

                        if let setup = embeddingManager.selectedProvider.requiresSetup {
                            Text("Setup: \(setup)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .monospaced()
                        }

                        if let attribution = embeddingManager.selectedProvider.attribution {
                            Link(attribution, destination: URL(string: attribution.components(separatedBy: "(").last?.dropLast().description ?? "")!)
                                .font(.caption2)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - LLM Backend Selection
                GroupBox(label: Label("LLM Backend", systemImage: "cpu")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose the AI backend for chat and summarization")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Circle()
                                .fill(aiBackend.activeBackend != nil ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(aiBackend.activeBackend?.rawValue ?? "No backend available")
                                .font(.caption)
                                .foregroundColor(aiBackend.activeBackend != nil ? .green : .red)
                        }

                        Text("Available backends are auto-detected. Configure each below.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - Ollama Configuration
                GroupBox(label: Label("Ollama", systemImage: "server.rack")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle()
                                .fill(ollamaClient.isConnected ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                            Text(ollamaClient.isConnected ? "Connected" : "Not Connected")
                                .foregroundColor(ollamaClient.isConnected ? .green : .red)
                        }

                        TextField("Server URL", text: $serverURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: serverURL) { newValue in
                                UserDefaults.standard.set(newValue, forKey: "ollamaServerURL")
                            }

                        HStack {
                            Button("Test Connection") {
                                testOllamaConnection()
                            }
                            .disabled(isTestingConnection)

                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }

                        if showTestResult {
                            Text(testResultMessage)
                                .foregroundColor(ollamaClient.isConnected ? .green : .red)
                                .font(.caption)
                        }

                        Divider()

                        // Model selection
                        if !ollamaClient.availableModels.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("LLM Model")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Picker("LLM Model", selection: $selectedLLMModel) {
                                    ForEach(ollamaClient.availableModels, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .onChange(of: selectedLLMModel) { newValue in
                                    ollamaClient.updateLLMModel(newValue)
                                }

                                Text("Embedding Model")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Picker("Embedding Model", selection: $selectedEmbeddingModel) {
                                    ForEach(ollamaClient.availableModels, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .onChange(of: selectedEmbeddingModel) { newValue in
                                    ollamaClient.updateEmbeddingModel(newValue)
                                }
                            }
                        }

                        // Pull model
                        Divider()

                        Text("Pull Model")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("Model name (e.g., llama2)", text: $modelToPull)
                                .textFieldStyle(RoundedBorderTextFieldStyle())

                            Button("Pull") {
                                pullModel()
                            }
                            .disabled(modelToPull.isEmpty || isPullingModel)
                        }

                        if isPullingModel {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text(pullProgress)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - TinyChat Configuration
                GroupBox(label: Label("TinyChat", systemImage: "bubble.left.and.bubble.right")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TinyChat by Jason Cox - OpenAI-compatible chat interface")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Server URL", text: $tinyChatURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: tinyChatURL) { newValue in
                                UserDefaults.standard.set(newValue, forKey: "TinyChatEmbedding_URL")
                                embeddingManager.tinyChat?.setBaseURL(newValue)
                            }

                        Button("Test TinyChat Connection") {
                            Task {
                                await embeddingManager.tinyChat?.checkAvailability()
                            }
                        }

                        HStack {
                            Circle()
                                .fill(embeddingManager.tinyChat?.isAvailable == true ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(embeddingManager.tinyChat?.isAvailable == true ? "Available" : "Not detected")
                                .font(.caption)
                                .foregroundColor(embeddingManager.tinyChat?.isAvailable == true ? .green : .gray)
                        }

                        Link("github.com/jasonacox/tinychat", destination: URL(string: "https://github.com/jasonacox/tinychat")!)
                            .font(.caption)
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - OpenWebUI Configuration
                GroupBox(label: Label("OpenWebUI", systemImage: "globe")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Self-hosted AI platform with OpenAI-compatible API")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Server URL", text: $openWebUIURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: openWebUIURL) { newValue in
                                UserDefaults.standard.set(newValue, forKey: "OpenWebUIEmbedding_URL")
                                embeddingManager.openWebUI?.setBaseURL(newValue)
                            }

                        SecureField("API Key (optional)", text: $openWebUIAPIKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: openWebUIAPIKey) { newValue in
                                embeddingManager.openWebUI?.setAPIKey(newValue)
                            }

                        Button("Test OpenWebUI Connection") {
                            Task {
                                await embeddingManager.openWebUI?.checkAvailability()
                            }
                        }

                        HStack {
                            Circle()
                                .fill(embeddingManager.openWebUI?.isAvailable == true ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(embeddingManager.openWebUI?.isAvailable == true ? "Available" : "Not detected")
                                .font(.caption)
                                .foregroundColor(embeddingManager.openWebUI?.isAvailable == true ? .green : .gray)
                        }

                        Link("github.com/open-webui/open-webui", destination: URL(string: "https://github.com/open-webui/open-webui")!)
                            .font(.caption)
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - Generation Parameters
                GroupBox(label: Label("Generation Parameters", systemImage: "slider.horizontal.3")) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("Temperature: \(String(format: "%.2f", temperature))")
                                .font(.caption)

                            Slider(value: $temperature, in: 0.0...1.0, step: 0.1)
                                .onChange(of: temperature) { newValue in
                                    ollamaClient.updateTemperature(newValue)
                                }

                            Text("Lower = more conservative, Higher = more creative")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        VStack(alignment: .leading) {
                            Stepper("Max Tokens: \(maxTokens)", value: $maxTokens, in: 512...8192, step: 512)
                                .onChange(of: maxTokens) { newValue in
                                    UserDefaults.standard.set(newValue, forKey: "ollamaMaxTokens")
                                }

                            Text("Maximum length of generated responses")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - Database & Reindexing
                GroupBox(label: Label("Database", systemImage: "cylinder")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: {
                            // Trigger reindex - to be implemented via notification
                            NotificationCenter.default.post(name: NSNotification.Name("RegenerateEmbeddings"), object: nil)
                        }) {
                            Label("Regenerate All Embeddings", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        Text("Re-index emails if you change the embedding provider. This will take several minutes for large mailboxes.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - Help
                GroupBox(label: Label("Quick Setup Guide", systemImage: "questionmark.circle")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ollama (Recommended for local):")
                            .font(.caption)
                            .bold()

                        Group {
                            Text("brew install ollama")
                            Text("ollama serve")
                            Text("ollama pull llama3.2")
                            Text("ollama pull nomic-embed-text")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospaced()

                        Divider()

                        Text("TinyChat:")
                            .font(.caption)
                            .bold()

                        Text("docker run -d -p 8000:8000 jasonacox/tinychat:latest")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospaced()

                        Divider()

                        Text("OpenWebUI:")
                            .font(.caption)
                            .bold()

                        Text("docker run -d -p 8080:8080 ghcr.io/open-webui/open-webui:main")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospaced()
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding()
        }
        .frame(minWidth: 550, minHeight: 600)
        .onAppear {
            loadSettings()
        }
    }

    private func loadSettings() {
        serverURL = UserDefaults.standard.string(forKey: "ollamaServerURL") ?? "http://localhost:11434"
        selectedLLMModel = UserDefaults.standard.string(forKey: "ollamaLLMModel") ?? "llama2"
        selectedEmbeddingModel = UserDefaults.standard.string(forKey: "ollamaEmbeddingModel") ?? "nomic-embed-text"
        tinyChatURL = UserDefaults.standard.string(forKey: "TinyChatEmbedding_URL") ?? "http://localhost:8000"
        openWebUIURL = UserDefaults.standard.string(forKey: "OpenWebUIEmbedding_URL") ?? "http://localhost:8080"
        openWebUIAPIKey = UserDefaults.standard.string(forKey: "OpenWebUIEmbedding_APIKey") ?? ""

        temperature = UserDefaults.standard.float(forKey: "ollamaTemperature")
        if temperature == 0 {
            temperature = 0.7
        }
        maxTokens = UserDefaults.standard.integer(forKey: "ollamaMaxTokens")
        if maxTokens == 0 {
            maxTokens = 4096
        }

        Task {
            await ollamaClient.checkConnection()
            await embeddingManager.updateActiveProvider()
        }
    }

    private func testOllamaConnection() {
        isTestingConnection = true
        showTestResult = false

        Task {
            await ollamaClient.updateServerURL(serverURL)
            await ollamaClient.checkConnection()

            await MainActor.run {
                isTestingConnection = false
                showTestResult = true

                if ollamaClient.isConnected {
                    testResultMessage = "Successfully connected to Ollama"
                } else {
                    testResultMessage = "Failed to connect. Make sure Ollama is running."
                }
            }
        }
    }

    private func pullModel() {
        isPullingModel = true
        pullProgress = "Pulling \(modelToPull)..."

        Task {
            do {
                try await ollamaClient.pullModel(name: modelToPull) { status in
                    Task { @MainActor in
                        pullProgress = status
                    }
                }

                await MainActor.run {
                    isPullingModel = false
                    pullProgress = "Successfully pulled \(modelToPull)"
                    modelToPull = ""

                    Task {
                        await ollamaClient.loadAvailableModels()
                    }
                }
            } catch {
                await MainActor.run {
                    isPullingModel = false
                    pullProgress = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct AISettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AISettingsView()
    }
}

//
//  AISettingsView.swift
//  MBox Explorer
//
//  Ollama AI configuration settings
//  Author: Jordan Koch
//  Date: 2025-01-17
//

import SwiftUI

struct AISettingsView: View {
    @StateObject private var ollamaClient = OllamaClient()
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

    var body: some View {
        Form {
            Section(header: Text("Connection")) {
                HStack {
                    Circle()
                        .fill(ollamaClient.isConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(ollamaClient.isConnected ? "Connected to Ollama" : "Not Connected")
                        .foregroundColor(ollamaClient.isConnected ? .green : .red)
                }

                TextField("Server URL", text: $serverURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: serverURL) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "ollamaServerURL")
                    }

                HStack {
                    Button("Test Connection") {
                        testConnection()
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
            }

            Section(header: Text("Models")) {
                VStack(alignment: .leading) {
                    Text("LLM Model (Chat & Summarization)")
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
                }

                VStack(alignment: .leading) {
                    Text("Embedding Model (Semantic Search)")
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

                if ollamaClient.availableModels.isEmpty {
                    Text("No models found. Pull a model using the section below.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Section(header: Text("Model Management")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pull Model from Ollama Library")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        TextField("Model name (e.g., llama2, mistral)", text: $modelToPull)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button("Pull") {
                            pullModel()
                        }
                        .disabled(modelToPull.isEmpty || isPullingModel)
                    }

                    if isPullingModel {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text(pullProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommended Models:")
                        .font(.caption)
                        .bold()

                    Group {
                        Text("• llama2 - Good general purpose LLM")
                        Text("• mistral - Faster, high quality LLM")
                        Text("• nomic-embed-text - Embeddings for semantic search")
                        Text("• all-minilm - Faster embeddings model")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Generation Parameters")) {
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

                VStack(alignment: .leading) {
                    Stepper("Max Tokens: \(maxTokens)", value: $maxTokens, in: 512...4096, step: 512)
                        .onChange(of: maxTokens) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "ollamaMaxTokens")
                        }

                    Text("Maximum length of generated responses")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Database")) {
                Button("Regenerate All Embeddings") {
                    // This would trigger a re-index
                    // Implementation would be in the main view
                }
                .foregroundColor(.orange)

                Text("Re-index emails if you change the embedding model. This will take several minutes for large mailboxes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Help")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Setup Instructions:")
                        .font(.caption)
                        .bold()

                    Group {
                        Text("1. Install Ollama: brew install ollama")
                        Text("2. Start Ollama: ollama serve")
                        Text("3. Pull a model: ollama pull llama2")
                        Text("4. Pull embedding model: ollama pull nomic-embed-text")
                        Text("5. Click 'Test Connection' above")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospaced()
                }

                Link("Ollama Documentation", destination: URL(string: "https://ollama.com/library")!)
                    .font(.caption)
            }
        }
        .frame(minWidth: 600, minHeight: 700)
        .padding()
        .onAppear {
            loadSettings()
        }
    }

    private func loadSettings() {
        serverURL = UserDefaults.standard.string(forKey: "ollamaServerURL") ?? "http://localhost:11434"
        selectedLLMModel = UserDefaults.standard.string(forKey: "ollamaLLMModel") ?? "llama2"
        selectedEmbeddingModel = UserDefaults.standard.string(forKey: "ollamaEmbeddingModel") ?? "nomic-embed-text"
        temperature = UserDefaults.standard.float(forKey: "ollamaTemperature")
        if temperature == 0 {
            temperature = 0.7
        }
        maxTokens = UserDefaults.standard.integer(forKey: "ollamaMaxTokens")
        if maxTokens == 0 {
            maxTokens = 2048
        }

        Task {
            await ollamaClient.checkConnection()
        }
    }

    private func testConnection() {
        isTestingConnection = true
        showTestResult = false

        Task {
            await ollamaClient.updateServerURL(serverURL)
            await ollamaClient.checkConnection()

            await MainActor.run {
                isTestingConnection = false
                showTestResult = true

                if ollamaClient.isConnected {
                    testResultMessage = "✓ Successfully connected to Ollama"
                } else {
                    testResultMessage = "✗ Failed to connect. Make sure Ollama is running: ollama serve"
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
                    pullProgress = "✓ Successfully pulled \(modelToPull)"
                    modelToPull = ""

                    // Refresh available models
                    Task {
                        await ollamaClient.loadAvailableModels()
                    }
                }
            } catch {
                await MainActor.run {
                    isPullingModel = false
                    pullProgress = "✗ Failed to pull model: \(error.localizedDescription)"
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

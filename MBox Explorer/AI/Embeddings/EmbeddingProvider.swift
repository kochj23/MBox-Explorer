//
//  EmbeddingProvider.swift
//  MBox Explorer
//
//  Unified interface for embedding providers (Ollama, MLX, OpenAI, etc.)
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation

/// Protocol for embedding providers
protocol EmbeddingProvider {
    var name: String { get }
    var isAvailable: Bool { get }
    var embeddingDimension: Int { get }

    func checkAvailability() async
    func generateEmbedding(for text: String) async throws -> [Float]
    func generateBatchEmbeddings(for texts: [String]) async throws -> [[Float]]
}

/// Errors for embedding operations
enum EmbeddingError: LocalizedError {
    case providerUnavailable(String)
    case modelNotFound(String)
    case generationFailed(String)
    case dimensionMismatch(expected: Int, got: Int)
    case networkError(String)
    case apiKeyMissing
    case pythonBridgeError(String)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let provider):
            return "Embedding provider '\(provider)' is not available"
        case .modelNotFound(let model):
            return "Embedding model '\(model)' not found"
        case .generationFailed(let reason):
            return "Embedding generation failed: \(reason)"
        case .dimensionMismatch(let expected, let got):
            return "Embedding dimension mismatch: expected \(expected), got \(got)"
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .apiKeyMissing:
            return "API key is missing"
        case .pythonBridgeError(let reason):
            return "Python bridge error: \(reason)"
        }
    }
}

/// Embedding provider type
enum EmbeddingProviderType: String, CaseIterable, Identifiable {
    case ollama = "Ollama"
    case mlx = "MLX"
    case openai = "OpenAI"
    case sentenceTransformers = "Sentence Transformers"
    case none = "None (Keyword Search Only)"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .ollama:
            return "Local embeddings via Ollama (free, private)"
        case .mlx:
            return "Apple Silicon native via MLX (free, fast)"
        case .openai:
            return "Cloud embeddings via OpenAI API (paid, high quality)"
        case .sentenceTransformers:
            return "Python sentence-transformers (free, flexible)"
        case .none:
            return "No semantic search - keyword matching only"
        }
    }

    var requiresSetup: String? {
        switch self {
        case .ollama:
            return "brew install ollama && ollama pull nomic-embed-text"
        case .mlx:
            return "Included - uses MLX Swift package"
        case .openai:
            return "Requires OpenAI API key"
        case .sentenceTransformers:
            return "pip install sentence-transformers"
        case .none:
            return nil
        }
    }
}

/// Manager for embedding providers
class EmbeddingManager: ObservableObject {
    static let shared = EmbeddingManager()

    @Published var selectedProvider: EmbeddingProviderType {
        didSet {
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: "EmbeddingManager_SelectedProvider")
            Task {
                await updateActiveProvider()
            }
        }
    }

    @Published var isAvailable = false
    @Published var statusMessage = "Checking..."

    private var ollamaProvider: OllamaEmbeddingProvider?
    private var mlxProvider: MLXEmbeddingProvider?
    private var openaiProvider: OpenAIEmbeddingProvider?
    private var pythonProvider: SentenceTransformerProvider?

    private var activeProvider: EmbeddingProvider?

    private init() {
        let savedProvider = UserDefaults.standard.string(forKey: "EmbeddingManager_SelectedProvider") ?? "Ollama"
        self.selectedProvider = EmbeddingProviderType(rawValue: savedProvider) ?? .ollama

        // Initialize providers
        ollamaProvider = OllamaEmbeddingProvider()
        mlxProvider = MLXEmbeddingProvider()
        openaiProvider = OpenAIEmbeddingProvider()
        pythonProvider = SentenceTransformerProvider()

        Task {
            await updateActiveProvider()
        }
    }

    func updateActiveProvider() async {
        await MainActor.run {
            statusMessage = "Checking \(selectedProvider.rawValue)..."
        }

        let provider: EmbeddingProvider?

        switch selectedProvider {
        case .ollama:
            await ollamaProvider?.checkAvailability()
            provider = ollamaProvider
        case .mlx:
            await mlxProvider?.checkAvailability()
            provider = mlxProvider
        case .openai:
            await openaiProvider?.checkAvailability()
            provider = openaiProvider
        case .sentenceTransformers:
            await pythonProvider?.checkAvailability()
            provider = pythonProvider
        case .none:
            provider = nil
        }

        await MainActor.run {
            activeProvider = provider
            isAvailable = provider?.isAvailable ?? false

            if selectedProvider == .none {
                statusMessage = "Keyword search only (no embeddings)"
                isAvailable = true
            } else if let p = provider, p.isAvailable {
                statusMessage = "\(p.name) ready (\(p.embeddingDimension) dimensions)"
            } else {
                statusMessage = "\(selectedProvider.rawValue) not available"
            }
        }
    }

    func generateEmbedding(for text: String) async throws -> [Float] {
        guard let provider = activeProvider, provider.isAvailable else {
            throw EmbeddingError.providerUnavailable(selectedProvider.rawValue)
        }
        return try await provider.generateEmbedding(for: text)
    }

    func generateBatchEmbeddings(for texts: [String]) async throws -> [[Float]] {
        guard let provider = activeProvider, provider.isAvailable else {
            throw EmbeddingError.providerUnavailable(selectedProvider.rawValue)
        }
        return try await provider.generateBatchEmbeddings(for: texts)
    }

    var currentDimension: Int {
        activeProvider?.embeddingDimension ?? 0
    }

    var useSemanticSearch: Bool {
        selectedProvider != .none && isAvailable
    }
}

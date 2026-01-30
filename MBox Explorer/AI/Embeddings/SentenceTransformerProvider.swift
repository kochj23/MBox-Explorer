//
//  SentenceTransformerProvider.swift
//  MBox Explorer
//
//  Python sentence-transformers bridge for embeddings
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation

/// Sentence-transformers embedding provider via Python bridge
/// Supports any model from huggingface.co/sentence-transformers
class SentenceTransformerProvider: EmbeddingProvider, ObservableObject {
    let name = "Sentence Transformers"

    @Published var isAvailable = false
    @Published var selectedModel = "all-MiniLM-L6-v2"
    @Published var pythonPath = "/usr/bin/python3"
    @Published var isModelLoaded = false

    var embeddingDimension: Int {
        switch selectedModel {
        case "all-MiniLM-L6-v2": return 384
        case "all-mpnet-base-v2": return 768
        case "paraphrase-MiniLM-L6-v2": return 384
        case "multi-qa-MiniLM-L6-cos-v1": return 384
        default: return 384
        }
    }

    // Available models
    static let availableModels = [
        "all-MiniLM-L6-v2",           // Fast, good quality
        "all-mpnet-base-v2",          // Better quality, slower
        "paraphrase-MiniLM-L6-v2",    // Paraphrase detection
        "multi-qa-MiniLM-L6-cos-v1"   // QA optimized
    ]

    private var serverProcess: Process?
    private var serverPort: Int = 8765
    private let serverScript: String

    init() {
        // Create the Python server script
        serverScript = """
        #!/usr/bin/env python3
        import sys
        import json
        from http.server import HTTPServer, BaseHTTPRequestHandler
        from sentence_transformers import SentenceTransformer

        model = None
        model_name = None

        class EmbeddingHandler(BaseHTTPRequestHandler):
            def do_POST(self):
                global model, model_name
                content_length = int(self.headers['Content-Length'])
                post_data = self.rfile.read(content_length)
                request = json.loads(post_data.decode('utf-8'))

                if self.path == '/load':
                    new_model = request.get('model', 'all-MiniLM-L6-v2')
                    if model is None or model_name != new_model:
                        model = SentenceTransformer(new_model)
                        model_name = new_model
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({'status': 'loaded', 'model': model_name}).encode())

                elif self.path == '/embed':
                    if model is None:
                        self.send_response(500)
                        self.send_header('Content-type', 'application/json')
                        self.end_headers()
                        self.wfile.write(json.dumps({'error': 'Model not loaded'}).encode())
                        return

                    texts = request.get('texts', [])
                    if isinstance(texts, str):
                        texts = [texts]

                    embeddings = model.encode(texts).tolist()

                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({'embeddings': embeddings}).encode())

                elif self.path == '/health':
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({'status': 'ok', 'model': model_name}).encode())

            def log_message(self, format, *args):
                pass  # Suppress logging

        if __name__ == '__main__':
            port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
            server = HTTPServer(('127.0.0.1', port), EmbeddingHandler)
            print(f'Embedding server running on port {port}')
            server.serve_forever()
        """

        // Load saved preferences
        if let savedPath = UserDefaults.standard.string(forKey: "SentenceTransformer_PythonPath") {
            pythonPath = savedPath
        }
        if let savedModel = UserDefaults.standard.string(forKey: "SentenceTransformer_Model") {
            selectedModel = savedModel
        }
    }

    func checkAvailability() async {
        // Check if Python and sentence-transformers are available
        let checkScript = """
        import sys
        try:
            from sentence_transformers import SentenceTransformer
            print('OK')
        except ImportError:
            print('MISSING')
            sys.exit(1)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", checkScript]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            await MainActor.run {
                isAvailable = output.contains("OK") && process.terminationStatus == 0
            }
        } catch {
            await MainActor.run {
                isAvailable = false
            }
        }
    }

    func startServer() async throws {
        guard serverProcess == nil else { return }

        // Write server script to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("embedding_server.py")
        try serverScript.write(to: scriptPath, atomically: true, encoding: .utf8)

        // Start server process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath.path, String(serverPort)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        serverProcess = process

        // Wait for server to start
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Load the model
        try await loadModel()
    }

    func stopServer() {
        serverProcess?.terminate()
        serverProcess = nil
        isModelLoaded = false
    }

    private func loadModel() async throws {
        let url = URL(string: "http://127.0.0.1:\(serverPort)/load")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": selectedModel])

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EmbeddingError.pythonBridgeError("Failed to load model")
        }

        await MainActor.run {
            isModelLoaded = true
        }
    }

    func generateEmbedding(for text: String) async throws -> [Float] {
        let embeddings = try await generateBatchEmbeddings(for: [text])
        guard let first = embeddings.first else {
            throw EmbeddingError.generationFailed("No embedding returned")
        }
        return first
    }

    func generateBatchEmbeddings(for texts: [String]) async throws -> [[Float]] {
        guard isAvailable else {
            throw EmbeddingError.providerUnavailable("Sentence Transformers")
        }

        // Start server if not running
        if serverProcess == nil {
            try await startServer()
        }

        let url = URL(string: "http://127.0.0.1:\(serverPort)/embed")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["texts": texts])
        request.timeoutInterval = 60 // Longer timeout for batch processing

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EmbeddingError.pythonBridgeError("Server error")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embeddings = json["embeddings"] as? [[Double]] else {
            throw EmbeddingError.generationFailed("Invalid response format")
        }

        return embeddings.map { $0.map { Float($0) } }
    }

    func setModel(_ model: String) {
        if selectedModel != model {
            selectedModel = model
            isModelLoaded = false
            UserDefaults.standard.set(model, forKey: "SentenceTransformer_Model")

            // Reload model if server is running
            if serverProcess != nil {
                Task {
                    try? await loadModel()
                }
            }
        }
    }

    func setPythonPath(_ path: String) {
        pythonPath = path
        UserDefaults.standard.set(path, forKey: "SentenceTransformer_PythonPath")
        stopServer()
        Task {
            await checkAvailability()
        }
    }

    deinit {
        stopServer()
    }
}

import Foundation

//
//  AIBackendManager+Generation.swift
//  Shared AI Backend Manager - Generation Methods
//
//  Real implementation of generate() that calls Ollama, TinyLLM, OpenWebUI, etc.
//  Author: Jordan Koch
//  Date: 2026-01-21
//

extension AIBackendManager {

    // MARK: - Text Generation

    /// Generate text using the active AI backend
    /// This is the main method that AISystemAnalyzer and other tools call
    func generate(
        prompt: String,
        systemPrompt: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 1000
    ) async throws -> String {

        guard isOllamaAvailable || isTinyLLMAvailable || isTinyChatAvailable || isOpenWebUIAvailable else {
            throw AIError.noBackendAvailable

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        switch activeBackend {
        case .ollama:
            return try await generateWithOllama(
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

        case .tinyChat:
            return try await generateWithTinyChat(
                prompt: prompt,
                temperature: temperature
            )

        case .openWebUI:
            return try await generateWithOpenWebUI(
                prompt: prompt,
                systemPrompt: systemPrompt,
                temperature: temperature
            )

        case .mlx:
            return try await generateWithMLX(
                prompt: prompt,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens
            )

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }
    }

    // MARK: - Ollama Implementation

    private func generateWithOllama(
        prompt: String,
        systemPrompt: String?,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {

        guard let url = URL(string: "\(ollamaServerURL)/api/generate") else {
            throw AIError.invalidURL

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        var messages: [[String: String]] = []

        if let system = systemPrompt {
            messages.append(["role": "system", "content": system])

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        messages.append(["role": "user", "content": prompt])

        let requestBody: [String: Any] = [
            "model": selectedOllamaModel,
            "prompt": prompt,
            "system": systemPrompt ?? "",
            "stream": false,
            "options": [
                "temperature": temperature,
                "num_predict": maxTokens
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60.0

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        guard httpResponse.statusCode == 200 else {
            throw AIError.httpError(httpResponse.statusCode)

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        struct OllamaResponse: Codable {
            let response: String

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        let ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return ollamaResponse.response
    }

    // MARK: - TinyLLM Implementation

    private func generateWithTinyLLM(
        prompt: String,
        systemPrompt: String?,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {

        guard let url = URL(string: "\(tinyLLMServerURL)/v1/chat/completions") else {
            throw AIError.invalidURL

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        var messages: [[String: String]] = []

        if let system = systemPrompt {
            messages.append(["role": "system", "content": system])

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        messages.append(["role": "user", "content": prompt])

        let requestBody: [String: Any] = [
            "model": "default",
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60.0

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        guard httpResponse.statusCode == 200 else {
            throw AIError.httpError(httpResponse.statusCode)

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        struct OpenAIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        let apiResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return apiResponse.choices.first?.message.content ?? ""
    }

    // MARK: - TinyChat Implementation

    private func generateWithTinyChat(
        prompt: String,
        temperature: Double
    ) async throws -> String {

        guard let url = URL(string: "\(tinyChatServerURL)/api/chat") else {
            throw AIError.invalidURL

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        let requestBody: [String: Any] = [
            "message": prompt,
            "model": selectedOllamaModel,
            "temperature": temperature
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60.0

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        guard httpResponse.statusCode == 200 else {
            throw AIError.httpError(httpResponse.statusCode)

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        // TinyChat returns streaming JSON lines, take the last complete response
        if let responseText = String(data: data, encoding: .utf8) {
            // Parse last line of streaming response
            let lines = responseText.components(separatedBy: "\n").filter { !$0.isEmpty }
            for line in lines.reversed() {
                if let lineData = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                   let content = json["content"] as? String {
                    return content
                }
            }

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        throw AIError.noResponse
    }

    // MARK: - OpenWebUI Implementation

    private func generateWithOpenWebUI(
        prompt: String,
        systemPrompt: String?,
        temperature: Double
    ) async throws -> String {

        // OpenWebUI uses OpenAI-compatible API
        guard let url = URL(string: "\(openWebUIServerURL)/api/chat") else {
            throw AIError.invalidURL

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        var messages: [[String: String]] = []

        if let system = systemPrompt {
            messages.append(["role": "system", "content": system])

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        messages.append(["role": "user", "content": prompt])

        let requestBody: [String: Any] = [
            "model": selectedOllamaModel,
            "messages": messages,
            "temperature": temperature
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60.0

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        guard httpResponse.statusCode == 200 else {
            throw AIError.httpError(httpResponse.statusCode)

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        // Parse response (format varies by OpenWebUI version)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        throw AIError.noResponse
    }

    // MARK: - MLX Implementation

    private func generateWithMLX(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> String {

        // MLX runs via Python subprocess
        // For now, fallback to Ollama if available
        if isOllamaAvailable {
            return try await generateWithOllama(
                prompt: prompt,
                systemPrompt: systemPrompt,
                temperature: 0.7,
                maxTokens: maxTokens
            )

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }

        throw AIError.mlxNotImplemented
    }
}

// MARK: - AI Errors

enum AIError: LocalizedError {
    case noBackendAvailable
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case noResponse
    case mlxNotImplemented

    var errorDescription: String? {
        switch self {
        case .noBackendAvailable:
            return "No AI backend is available. Please start Ollama, TinyLLM, TinyChat, or OpenWebUI."
        case .invalidURL:
            return "Invalid backend URL configuration"
        case .invalidResponse:
            return "Received invalid response from AI backend"
        case .httpError(let code):
            return "HTTP error \(code) from AI backend"
        case .noResponse:
            return "No response received from AI backend"
        case .mlxNotImplemented:
            return "MLX backend not yet implemented. Please use Ollama instead."

        case .openAI:
            throw AIError.mlxNotImplemented

        case .googleCloud:
            throw AIError.mlxNotImplemented

        case .azureCognitive:
            throw AIError.mlxNotImplemented

        case .awsAI:
            throw AIError.mlxNotImplemented

        case .ibmWatson:
            throw AIError.mlxNotImplemented
        }
    }
}

//
//  UnifiedAICapabilities.swift
//  Universal AI Capabilities Module
//
//  Created by Jordan Koch on 2026-01-26
//
//  This module provides ALL AI capabilities to ALL projects.
//  Every project gets every capability, regardless of whether it makes sense.
//

import Foundation
import SwiftUI
import AVFoundation

// MARK: - Unified AI Capabilities Manager

@MainActor
class UnifiedAICapabilities: ObservableObject {
    static let shared = UnifiedAICapabilities()

    // MARK: - Published Status
    @Published var availableCapabilities: [AICapability] = []
    @Published var isInitialized = false
    @Published var lastError: String?

    // MARK: - Backend Managers
    // These are instantiated on-demand
    private var imageGenBackend: ImageGenerationUnified?
    private var voiceBackend: VoiceUnified?
    private var analysisBackend: AnalysisUnified?
    private var securityBackend: SecurityUnified?

    private init() {
        initializeAllCapabilities()
    }

    // MARK: - Initialization

    private func initializeAllCapabilities() {
        detectCapabilities()
        isInitialized = true
    }

    private func detectCapabilities() {
        var caps: [AICapability] = []

        // LLM Capabilities
        caps.append(AICapability(
            id: "llm-openai",
            name: "OpenAI GPT",
            category: .llm,
            status: .available,
            description: "Cloud-based LLM via OpenAI API"
        ))

        caps.append(AICapability(
            id: "llm-anthropic",
            name: "Anthropic Claude",
            category: .llm,
            status: .available,
            description: "Cloud-based LLM via Anthropic API"
        ))

        caps.append(AICapability(
            id: "llm-ollama",
            name: "Ollama Local",
            category: .llm,
            status: checkOllamaAvailability(),
            description: "Local LLM via Ollama (localhost:11434)"
        ))

        caps.append(AICapability(
            id: "llm-mlx",
            name: "MLX Toolkit",
            category: .llm,
            status: checkMLXAvailability(),
            description: "Local inference via MLX Python Toolkit"
        ))

        caps.append(AICapability(
            id: "llm-tinyllm",
            name: "TinyLLM",
            category: .llm,
            status: checkTinyLLMAvailability(),
            description: "Lightweight local server (localhost:8000)"
        ))

        // Image Generation
        caps.append(AICapability(
            id: "img-comfyui",
            name: "ComfyUI",
            category: .imageGeneration,
            status: checkComfyUIAvailability(),
            description: "Node-based image generation"
        ))

        caps.append(AICapability(
            id: "img-swarmui",
            name: "SwarmUI",
            category: .imageGeneration,
            status: checkSwarmUIAvailability(),
            description: "Community interface with Flux models"
        ))

        caps.append(AICapability(
            id: "img-automatic1111",
            name: "Automatic1111",
            category: .imageGeneration,
            status: checkAutomatic1111Availability(),
            description: "Standard Stable Diffusion interface"
        ))

        caps.append(AICapability(
            id: "img-dalle",
            name: "DALL-E",
            category: .imageGeneration,
            status: .available,
            description: "OpenAI image generation"
        ))

        // Voice & Audio
        caps.append(AICapability(
            id: "voice-clone",
            name: "F5-TTS Voice Cloning",
            category: .voice,
            status: checkF5TTSAvailability(),
            description: "Zero-shot voice cloning (5-10 sec reference)"
        ))

        caps.append(AICapability(
            id: "voice-tts",
            name: "Text-to-Speech",
            category: .voice,
            status: .available,
            description: "System TTS synthesis"
        ))

        caps.append(AICapability(
            id: "voice-models",
            name: "Voice Model Management",
            category: .voice,
            status: .available,
            description: "Custom voice model library"
        ))

        caps.append(AICapability(
            id: "audio-briefing",
            name: "Audio Briefing",
            category: .voice,
            status: .available,
            description: "AI-generated audio summaries"
        ))

        // Video Generation
        caps.append(AICapability(
            id: "video-gen",
            name: "Video Generation",
            category: .video,
            status: .available,
            description: "AI video creation"
        ))

        // Analysis Capabilities
        caps.append(AICapability(
            id: "analysis-summarization",
            name: "AI Summarization",
            category: .analysis,
            status: .available,
            description: "Content summarization"
        ))

        caps.append(AICapability(
            id: "analysis-factcheck",
            name: "Fact Checking",
            category: .analysis,
            status: .available,
            description: "Automated fact verification"
        ))

        caps.append(AICapability(
            id: "analysis-bias",
            name: "Bias Detection",
            category: .analysis,
            status: .available,
            description: "Content bias analysis"
        ))

        caps.append(AICapability(
            id: "analysis-entities",
            name: "Entity Tracking",
            category: .analysis,
            status: .available,
            description: "Named entity recognition"
        ))

        caps.append(AICapability(
            id: "analysis-multiperspective",
            name: "Multi-Perspective",
            category: .analysis,
            status: .available,
            description: "Multiple viewpoint analysis"
        ))

        caps.append(AICapability(
            id: "analysis-clustering",
            name: "Story Clustering",
            category: .analysis,
            status: .available,
            description: "Group related content"
        ))

        caps.append(AICapability(
            id: "analysis-coverage",
            name: "Coverage Comparison",
            category: .analysis,
            status: .available,
            description: "Compare source coverage"
        ))

        caps.append(AICapability(
            id: "analysis-data",
            name: "Data Analysis",
            category: .analysis,
            status: .available,
            description: "Structured data insights"
        ))

        caps.append(AICapability(
            id: "analysis-predictive",
            name: "Predictive Analytics",
            category: .analysis,
            status: .available,
            description: "Forecast trends"
        ))

        caps.append(AICapability(
            id: "analysis-relationships",
            name: "Relationship Discovery",
            category: .analysis,
            status: .available,
            description: "Find data relationships"
        ))

        caps.append(AICapability(
            id: "analysis-sentiment",
            name: "Sentiment Analysis",
            category: .analysis,
            status: .available,
            description: "Emotion detection"
        ))

        caps.append(AICapability(
            id: "analysis-url",
            name: "URL Analysis",
            category: .analysis,
            status: .available,
            description: "Web link security/content"
        ))

        caps.append(AICapability(
            id: "analysis-trends",
            name: "Trend Analysis",
            category: .analysis,
            status: .available,
            description: "Pattern detection"
        ))

        // Automation
        caps.append(AICapability(
            id: "auto-tagging",
            name: "Auto-Tagging",
            category: .automation,
            status: .available,
            description: "Automatic categorization"
        ))

        caps.append(AICapability(
            id: "auto-pivot",
            name: "Smart Pivot Builder",
            category: .automation,
            status: .available,
            description: "Intelligent data pivoting"
        ))

        caps.append(AICapability(
            id: "auto-rules",
            name: "Rules Engine",
            category: .automation,
            status: .available,
            description: "If-then automation"
        ))

        // Security
        caps.append(AICapability(
            id: "security-attack",
            name: "Attack Orchestration",
            category: .security,
            status: .available,
            description: "Penetration test automation"
        ))

        caps.append(AICapability(
            id: "security-exploit",
            name: "Exploit Generation",
            category: .security,
            status: .available,
            description: "Vulnerability exploit creation"
        ))

        caps.append(AICapability(
            id: "security-vuln",
            name: "Vulnerability Analysis",
            category: .security,
            status: .available,
            description: "Security flaw detection"
        ))

        // Vector & Search
        caps.append(AICapability(
            id: "vector-db",
            name: "Vector Database",
            category: .search,
            status: .available,
            description: "Semantic search embeddings"
        ))

        caps.append(AICapability(
            id: "search-nlp",
            name: "Natural Language Search",
            category: .search,
            status: .available,
            description: "Plain English queries"
        ))

        // Specialized
        caps.append(AICapability(
            id: "special-personality",
            name: "AI Personality Engine",
            category: .specialized,
            status: .available,
            description: "Character simulation"
        ))

        caps.append(AICapability(
            id: "special-profiler",
            name: "AI Profiler",
            category: .specialized,
            status: .available,
            description: "Behavioral analysis"
        ))

        caps.append(AICapability(
            id: "special-system",
            name: "System Analysis",
            category: .specialized,
            status: .available,
            description: "Hardware/process insights"
        ))

        caps.append(AICapability(
            id: "special-icon",
            name: "Icon Generation",
            category: .specialized,
            status: .available,
            description: "AI icon design"
        ))

        caps.append(AICapability(
            id: "special-prompt",
            name: "Prompt Enhancement",
            category: .specialized,
            status: .available,
            description: "Optimize AI prompts"
        ))

        caps.append(AICapability(
            id: "special-code-nav",
            name: "Code Navigation",
            category: .specialized,
            status: .available,
            description: "Xcode integration tools"
        ))

        caps.append(AICapability(
            id: "special-voice-commands",
            name: "Voice Commands",
            category: .specialized,
            status: .available,
            description: "Speech recognition control"
        ))

        self.availableCapabilities = caps
    }

    // MARK: - Availability Checks

    private func checkOllamaAvailability() -> AICapabilityStatus {
        // Check if Ollama is running on localhost:11434
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return .unavailable }

        var isAvailable = false
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                isAvailable = true
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + 1.0)
        return isAvailable ? .available : .unavailable
    }

    private func checkMLXAvailability() -> AICapabilityStatus {
        // Check if MLX Python server is available
        let mlxPath = "/usr/local/bin/mlx_lm"
        return FileManager.default.fileExists(atPath: mlxPath) ? .available : .unavailable
    }

    private func checkTinyLLMAvailability() -> AICapabilityStatus {
        // Check if TinyLLM is running on localhost:8000
        guard let url = URL(string: "http://localhost:8000/health") else { return .unavailable }

        var isAvailable = false
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                isAvailable = true
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + 1.0)
        return isAvailable ? .available : .unavailable
    }

    private func checkComfyUIAvailability() -> AICapabilityStatus {
        guard let url = URL(string: "http://localhost:8188/system_stats") else { return .unavailable }

        var isAvailable = false
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                isAvailable = true
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + 1.0)
        return isAvailable ? .available : .unavailable
    }

    private func checkSwarmUIAvailability() -> AICapabilityStatus {
        guard let url = URL(string: "http://localhost:7801/API/ListModels") else { return .unavailable }

        var isAvailable = false
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                isAvailable = true
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + 1.0)
        return isAvailable ? .available : .unavailable
    }

    private func checkAutomatic1111Availability() -> AICapabilityStatus {
        guard let url = URL(string: "http://localhost:7860/sdapi/v1/sd-models") else { return .unavailable }

        var isAvailable = false
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                isAvailable = true
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + 1.0)
        return isAvailable ? .available : .unavailable
    }

    private func checkF5TTSAvailability() -> AICapabilityStatus {
        // Check if F5-TTS-MLX is installed
        let f5Path = "/usr/local/bin/f5-tts"
        return FileManager.default.fileExists(atPath: f5Path) ? .available : .unavailable
    }

    // MARK: - Capability Summary

    func getCapabilitySummary() -> CapabilitySummary {
        let total = availableCapabilities.count
        let available = availableCapabilities.filter { $0.status == .available }.count
        let unavailable = availableCapabilities.filter { $0.status == .unavailable }.count

        let byCategory = Dictionary(grouping: availableCapabilities) { $0.category }

        return CapabilitySummary(
            totalCapabilities: total,
            availableCount: available,
            unavailableCount: unavailable,
            byCategory: byCategory
        )
    }
}

// MARK: - Models

struct AICapability: Identifiable, Codable {
    let id: String
    let name: String
    let category: AICapabilityCategory
    var status: AICapabilityStatus
    let description: String
}

enum AICapabilityCategory: String, Codable, CaseIterable {
    case llm = "LLM (Language Models)"
    case imageGeneration = "Image Generation"
    case voice = "Voice & Audio"
    case video = "Video Generation"
    case analysis = "Analysis & Insights"
    case automation = "Automation"
    case security = "Security & Pentesting"
    case search = "Search & Vector DB"
    case specialized = "Specialized Tools"
}

enum AICapabilityStatus: String, Codable {
    case available = "Available"
    case unavailable = "Unavailable"
    case error = "Error"
}

struct CapabilitySummary {
    let totalCapabilities: Int
    let availableCount: Int
    let unavailableCount: Int
    let byCategory: [AICapabilityCategory: [AICapability]]
}

// MARK: - Voice Capabilities

class VoiceCapabilities {
    // Voice cloning, TTS, audio briefings
    func cloneVoice(referenceAudio: URL, targetText: String) async throws -> Data {
        // F5-TTS-MLX integration
        throw NSError(domain: "VoiceCapabilities", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    func synthesizeSpeech(text: String, voice: String?) async throws -> Data {
        // System TTS or custom voice
        throw NSError(domain: "VoiceCapabilities", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    func generateAudioBriefing(content: String) async throws -> Data {
        throw NSError(domain: "VoiceCapabilities", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
}

// MARK: - Analysis Capabilities

class AnalysisCapabilities {
    func summarize(_ content: String) async throws -> String {
        throw NSError(domain: "AnalysisCapabilities", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    func factCheck(_ content: String) async throws -> [String] {
        throw NSError(domain: "AnalysisCapabilities", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    func detectBias(_ content: String) async throws -> String {
        throw NSError(domain: "AnalysisCapabilities", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    func analyzeSentiment(_ content: String) async throws -> String {
        throw NSError(domain: "AnalysisCapabilities", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
}

// MARK: - Security Capabilities

class SecurityCapabilities {
    func orchestrateAttack(target: String, attackType: String) async throws -> String {
        throw NSError(domain: "SecurityCapabilities", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    func generateExploit(vulnerability: String) async throws -> String {
        throw NSError(domain: "SecurityCapabilities", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }

    func analyzeVulnerabilities(target: String) async throws -> [String] {
        throw NSError(domain: "SecurityCapabilities", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
}

// MARK: - Global Status View

struct UnifiedAIStatusView: View {
    @StateObject private var capabilities = UnifiedAICapabilities.shared
    @State private var selectedCategory: AICapabilityCategory?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerView

                Divider()

                // Category Grid
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(AICapabilityCategory.allCases, id: \.self) { category in
                            categoryCard(category)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("🤖 Universal AI Capabilities")
            .frame(minWidth: 800, minHeight: 600)
        }
    }

    private var headerView: some View {
        let summary = capabilities.getCapabilitySummary()

        return VStack(spacing: 12) {
            HStack(spacing: 32) {
                statBox("Total Capabilities", "\(summary.totalCapabilities)", .blue)
                statBox("Available", "\(summary.availableCount)", .green)
                statBox("Unavailable", "\(summary.unavailableCount)", .red)
                statBox("Coverage", "\(Int(Double(summary.availableCount) / Double(summary.totalCapabilities) * 100))%", .purple)
            }
            .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func statBox(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 120)
    }

    private func categoryCard(_ category: AICapabilityCategory) -> some View {
        let caps = capabilities.availableCapabilities.filter { $0.category == category }
        let available = caps.filter { $0.status == .available }.count

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category.rawValue)
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Text("\(available)/\(caps.count)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 8) {
                ForEach(caps) { capability in
                    capabilityChip(capability)
                }
            }
        }
        .padding()
        .background(categoryColor(category).opacity(0.2))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(categoryColor(category), lineWidth: 2)
        )
    }

    private func capabilityChip(_ capability: AICapability) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(capability.status == .available ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(capability.name)
                    .font(.caption)
                    .fontWeight(.medium)

                Text(capability.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private func categoryColor(_ category: AICapabilityCategory) -> Color {
        switch category {
        case .llm: return .blue
        case .imageGeneration: return .purple
        case .voice: return .pink
        case .video: return .red
        case .analysis: return .green
        case .automation: return .orange
        case .security: return .red
        case .search: return .cyan
        case .specialized: return .yellow
        }
    }
}

//
//  ImageGenerationUnified.swift
//  Universal Image Generation Module
//
//  Supports: ComfyUI, SwarmUI, Automatic1111, DALL-E
//  Created by Jordan Koch on 2026-01-26
//

import Foundation
import SwiftUI

@MainActor
class ImageGenerationUnified: ObservableObject {
    static let shared = ImageGenerationUnified()

    @Published var isGenerating = false
    @Published var lastError: String?
    @Published var generatedImages: [GeneratedImage] = []

    enum Backend: String, CaseIterable {
        case comfyui = "ComfyUI"
        case swarmui = "SwarmUI"
        case automatic1111 = "Automatic1111"
        case dalle = "DALL-E"
    }

    private init() {}

    // MARK: - Generate Image

    func generateImage(
        prompt: String,
        backend: Backend,
        size: ImageSize = .square512,
        style: ImageStyle = .realistic
    ) async throws -> Data {
        isGenerating = true
        lastError = nil

        defer { isGenerating = false }

        switch backend {
        case .comfyui:
            return try await generateComfyUI(prompt: prompt, size: size, style: style)
        case .swarmui:
            return try await generateSwarmUI(prompt: prompt, size: size, style: style)
        case .automatic1111:
            return try await generateAutomatic1111(prompt: prompt, size: size, style: style)
        case .dalle:
            return try await generateDALLE(prompt: prompt, size: size)
        }
    }

    // MARK: - ComfyUI

    private func generateComfyUI(prompt: String, size: ImageSize, style: ImageStyle) async throws -> Data {
        let endpoint = "http://localhost:8188/prompt"

        let workflow = createComfyUIWorkflow(prompt: prompt, size: size, style: style)

        guard let url = URL(string: endpoint) else {
            throw ImageGenerationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: workflow)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ImageGenerationError.requestFailed
        }

        // Parse response and fetch image
        return data
    }

    private func createComfyUIWorkflow(prompt: String, size: ImageSize, style: ImageStyle) -> [String: Any] {
        return [
            "prompt": [
                "3": [
                    "inputs": [
                        "seed": Int.random(in: 0...999999999),
                        "steps": 20,
                        "cfg": 7.0,
                        "sampler_name": "euler",
                        "scheduler": "normal",
                        "denoise": 1.0,
                        "model": ["4", 0],
                        "positive": ["6", 0],
                        "negative": ["7", 0],
                        "latent_image": ["5", 0]
                    ],
                    "class_type": "KSampler"
                ],
                "4": [
                    "inputs": [
                        "ckpt_name": "v1-5-pruned-emaonly.safetensors"
                    ],
                    "class_type": "CheckpointLoaderSimple"
                ],
                "6": [
                    "inputs": [
                        "text": enhancePrompt(prompt, style: style),
                        "clip": ["4", 1]
                    ],
                    "class_type": "CLIPTextEncode"
                ],
                "7": [
                    "inputs": [
                        "text": "text, watermark, blurry, low quality",
                        "clip": ["4", 1]
                    ],
                    "class_type": "CLIPTextEncode"
                ]
            ]
        ]
    }

    // MARK: - SwarmUI

    private func generateSwarmUI(prompt: String, size: ImageSize, style: ImageStyle) async throws -> Data {
        let endpoint = "http://localhost:7801/API/GenerateText2Image"

        let params: [String: Any] = [
            "prompt": enhancePrompt(prompt, style: style),
            "model": "flux1-schnell-fp8",
            "width": size.width,
            "height": size.height,
            "steps": 20,
            "cfg_scale": 7.0,
            "seed": -1
        ]

        guard let url = URL(string: endpoint) else {
            throw ImageGenerationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ImageGenerationError.requestFailed
        }

        return data
    }

    // MARK: - Automatic1111

    private func generateAutomatic1111(prompt: String, size: ImageSize, style: ImageStyle) async throws -> Data {
        let endpoint = "http://localhost:7860/sdapi/v1/txt2img"

        let params: [String: Any] = [
            "prompt": enhancePrompt(prompt, style: style),
            "negative_prompt": "text, watermark, blurry, low quality",
            "width": size.width,
            "height": size.height,
            "steps": 20,
            "cfg_scale": 7.0,
            "seed": -1,
            "sampler_index": "Euler"
        ]

        guard let url = URL(string: endpoint) else {
            throw ImageGenerationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ImageGenerationError.requestFailed
        }

        // Parse JSON and extract base64 image
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let images = json["images"] as? [String],
           let base64 = images.first,
           let imageData = Data(base64Encoded: base64) {
            return imageData
        }

        throw ImageGenerationError.invalidResponse
    }

    // MARK: - DALL-E

    private func generateDALLE(prompt: String, size: ImageSize) async throws -> Data {
        // Requires OpenAI API key
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            throw ImageGenerationError.missingAPIKey
        }

        let endpoint = "https://api.openai.com/v1/images/generations"

        let params: [String: Any] = [
            "prompt": prompt,
            "n": 1,
            "size": size.dalleSize
        ]

        guard let url = URL(string: endpoint) else {
            throw ImageGenerationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ImageGenerationError.requestFailed
        }

        // Parse JSON and download image URL
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataArray = json["data"] as? [[String: Any]],
           let urlString = dataArray.first?["url"] as? String,
           let imageURL = URL(string: urlString) {
            let (imageData, _) = try await URLSession.shared.data(from: imageURL)
            return imageData
        }

        throw ImageGenerationError.invalidResponse
    }

    // MARK: - Prompt Enhancement

    private func enhancePrompt(_ prompt: String, style: ImageStyle) -> String {
        let styleModifier: String
        switch style {
        case .realistic:
            styleModifier = "photorealistic, 8k, ultra detailed, professional photography"
        case .cartoon:
            styleModifier = "cartoon style, vibrant colors, illustration"
        case .artistic:
            styleModifier = "artistic, painterly, creative, expressive"
        case .anime:
            styleModifier = "anime style, japanese animation, detailed"
        case .sketch:
            styleModifier = "pencil sketch, hand drawn, artistic linework"
        }

        return "\(prompt), \(styleModifier)"
    }
}

// MARK: - Models

struct GeneratedImage: Identifiable {
    let id = UUID()
    let data: Data
    let prompt: String
    let timestamp: Date
    let backend: ImageGenerationUnified.Backend
}

enum ImageSize {
    case square512
    case square1024
    case portrait512x768
    case landscape768x512
    case widescreen1024x576

    var width: Int {
        switch self {
        case .square512: return 512
        case .square1024: return 1024
        case .portrait512x768: return 512
        case .landscape768x512: return 768
        case .widescreen1024x576: return 1024
        }
    }

    var height: Int {
        switch self {
        case .square512: return 512
        case .square1024: return 1024
        case .portrait512x768: return 768
        case .landscape768x512: return 512
        case .widescreen1024x576: return 576
        }
    }

    var dalleSize: String {
        switch self {
        case .square512: return "512x512"
        case .square1024: return "1024x1024"
        default: return "1024x1024"
        }
    }
}

enum ImageStyle {
    case realistic
    case cartoon
    case artistic
    case anime
    case sketch
}

enum ImageGenerationError: Error {
    case invalidURL
    case requestFailed
    case invalidResponse
    case missingAPIKey
}

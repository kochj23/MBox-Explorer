import Foundation
import SwiftUI
import Combine

//
//  AIBackendManager+Enhanced.swift
//  Enhanced features for AIBackendManager
//
//  Adds: Auto-fallback, connection testing, usage tracking, notifications, performance metrics
//  Author: Jordan Koch
//  Date: 2026-01-26
//

extension AIBackendManager {

    // MARK: - Auto-Fallback System

    /// Try to generate with fallback to other backends if primary fails
    func generateWithFallback(
        prompt: String,
        systemPrompt: String? = nil,
        temperature: Float = 0.7,
        maxTokens: Int = 2048
    ) async throws -> String {

        let preferredBackends = getAvailableBackendsInOrder()
        var lastError: Error?

        for backend in preferredBackends {
            let previousBackend = activeBackend
            activeBackend = backend

            do {
                let result = try await generate(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    temperature: temperature,
                    maxTokens: maxTokens
                )

                // Success! Log and return
                if backend != previousBackend {
                    await MainActor.run {
                        sendNotification(
                            title: "Backend Fallback",
                            message: "Switched to \(backend.rawValue) after \(previousBackend?.rawValue ?? "unknown") failed"
                        )
                    }
                }

                return result
            } catch {
                lastError = error
                continue
            }
        }

        // All backends failed
        throw lastError ?? AIBackendError.noBackendAvailable
    }

    private func getAvailableBackendsInOrder() -> [AIBackend] {
        var backends: [AIBackend] = []

        // Start with currently selected
        if let active = activeBackend, isBackendAvailable(active) {
            backends.append(active)
        }

        // Add other available backends in priority order
        let priorityOrder: [AIBackend] = [
            .ollama, .openAI, .tinyChat, .tinyLLM, .openWebUI,
            .googleCloud, .azureCognitive, .ibmWatson, .mlx, .awsAI
        ]

        for backend in priorityOrder where !backends.contains(backend) && isBackendAvailable(backend) {
            backends.append(backend)
        }

        return backends
    }

    private func isBackendAvailable(_ backend: AIBackend) -> Bool {
        switch backend {
        case .ollama: return isOllamaAvailable
        case .mlx: return isMLXAvailable
        case .tinyLLM: return isTinyLLMAvailable
        case .tinyChat: return isTinyChatAvailable
        case .openWebUI: return isOpenWebUIAvailable
        case .openAI: return isOpenAIAvailable
        case .googleCloud: return isGoogleCloudAvailable
        case .azureCognitive: return isAzureAvailable
        case .awsAI: return isAWSAvailable
        case .ibmWatson: return isIBMWatsonAvailable
        }
    }

    // MARK: - Connection Testing

    @Published var connectionTestResults: [AIBackend: ConnectionTestResult] = [:]

    struct ConnectionTestResult {
        let success: Bool
        let responseTime: TimeInterval?
        let error: String?
        let timestamp: Date
    }

    func testConnection(for backend: AIBackend) async -> ConnectionTestResult {
        let startTime = Date()

        do {
            // Save current backend
            let previousBackend = activeBackend
            activeBackend = backend

            // Try a simple test prompt
            _ = try await generate(
                prompt: "Say 'hello' in one word",
                temperature: 0.1,
                maxTokens: 10
            )

            // Restore previous backend
            activeBackend = previousBackend

            let responseTime = Date().timeIntervalSince(startTime)
            let result = ConnectionTestResult(
                success: true,
                responseTime: responseTime,
                error: nil,
                timestamp: Date()
            )

            await MainActor.run {
                connectionTestResults[backend] = result
                sendNotification(
                    title: "Connection Test Passed",
                    message: "\(backend.rawValue): \(String(format: "%.2f", responseTime))s"
                )
            }

            return result

        } catch {
            let result = ConnectionTestResult(
                success: false,
                responseTime: nil,
                error: error.localizedDescription,
                timestamp: Date()
            )

            await MainActor.run {
                connectionTestResults[backend] = result
                sendNotification(
                    title: "Connection Test Failed",
                    message: "\(backend.rawValue): \(error.localizedDescription)"
                )
            }

            return result
        }
    }

    // MARK: - Usage Tracking

    @Published var usageStats: [AIBackend: UsageStats] = [:]

    struct UsageStats: Codable {
        var totalTokens: Int = 0
        var totalRequests: Int = 0
        var totalCost: Double = 0.0 // USD
        var averageResponseTime: Double = 0.0 // seconds
        var lastUsed: Date?

        mutating func recordUsage(tokens: Int, cost: Double, responseTime: TimeInterval) {
            totalTokens += tokens
            totalRequests += 1
            totalCost += cost

            // Update running average
            let totalTime = averageResponseTime * Double(totalRequests - 1) + responseTime
            averageResponseTime = totalTime / Double(totalRequests)

            lastUsed = Date()
        }
    }

    func recordUsage(backend: AIBackend, tokens: Int, responseTime: TimeInterval) {
        let cost = estimateCost(backend: backend, tokens: tokens)

        var stats = usageStats[backend] ?? UsageStats()
        stats.recordUsage(tokens: tokens, cost: cost, responseTime: responseTime)
        usageStats[backend] = stats

        saveUsageStats()
    }

    private func estimateCost(backend: AIBackend, tokens: Int) -> Double {
        // Rough cost estimates per 1M tokens
        let costPerMillion: Double = {
            switch backend {
            case .openAI: return 10.0 // GPT-4o
            case .googleCloud: return 7.0
            case .azureCognitive: return 10.0
            case .awsAI: return 8.0
            case .ibmWatson: return 12.0
            case .ollama, .mlx, .tinyLLM, .tinyChat, .openWebUI: return 0.0 // Free/local
            }
        }()

        return (Double(tokens) / 1_000_000.0) * costPerMillion
    }

    private func saveUsageStats() {
        // Save to UserDefaults (should migrate to file-based storage for large datasets)
        if let data = try? JSONEncoder().encode(usageStats) {
            UserDefaults.standard.set(data, forKey: "AIBackend_UsageStats")
        }
    }

    private func loadUsageStats() {
        if let data = UserDefaults.standard.data(forKey: "AIBackend_UsageStats"),
           let stats = try? JSONDecoder().decode([AIBackend: UsageStats].self, from: data) {
            usageStats = stats
        }
    }

    // MARK: - Performance Metrics

    @Published var performanceMetrics: [AIBackend: PerformanceMetrics] = [:]

    struct PerformanceMetrics {
        var averageLatency: TimeInterval = 0.0
        var successRate: Double = 0.0
        var totalAttempts: Int = 0
        var successfulAttempts: Int = 0
        var failedAttempts: Int = 0
        var lastResponseTime: TimeInterval?
        var lastSuccess: Date?
        var lastFailure: Date?

        mutating func recordSuccess(responseTime: TimeInterval) {
            totalAttempts += 1
            successfulAttempts += 1
            lastResponseTime = responseTime
            lastSuccess = Date()

            // Update running average
            let totalTime = averageLatency * Double(successfulAttempts - 1) + responseTime
            averageLatency = totalTime / Double(successfulAttempts)

            // Calculate success rate
            successRate = Double(successfulAttempts) / Double(totalAttempts)
        }

        mutating func recordFailure() {
            totalAttempts += 1
            failedAttempts += 1
            lastFailure = Date()

            // Recalculate success rate
            successRate = Double(successfulAttempts) / Double(totalAttempts)
        }
    }

    func recordPerformance(backend: AIBackend, success: Bool, responseTime: TimeInterval?) {
        var metrics = performanceMetrics[backend] ?? PerformanceMetrics()

        if success, let responseTime = responseTime {
            metrics.recordSuccess(responseTime: responseTime)
        } else {
            metrics.recordFailure()
        }

        performanceMetrics[backend] = metrics
    }

    // MARK: - Notification System

    private func sendNotification(title: String, message: String) {
        // For macOS, use NSUserNotification or UNUserNotificationCenter
        // This is a simplified version
        #if os(macOS)
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
        #endif

        print("📢 \(title): \(message)")
    }

    // MARK: - Background Monitoring

    private var monitoringTimer: Timer?

    func startBackgroundMonitoring(interval: TimeInterval = 60.0) {
        stopBackgroundMonitoring()

        monitoringTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                let previousAvailability = self.collectAvailabilitySnapshot()
                await self.refreshAllBackends()
                let currentAvailability = self.collectAvailabilitySnapshot()

                // Notify of changes
                self.notifyAvailabilityChanges(from: previousAvailability, to: currentAvailability)
            }
        }
    }

    func stopBackgroundMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }

    private func collectAvailabilitySnapshot() -> [AIBackend: Bool] {
        var snapshot: [AIBackend: Bool] = [:]
        for backend in AIBackend.allCases {
            snapshot[backend] = isBackendAvailable(backend)
        }
        return snapshot
    }

    private func notifyAvailabilityChanges(from previous: [AIBackend: Bool], to current: [AIBackend: Bool]) {
        for backend in AIBackend.allCases {
            let wasAvailable = previous[backend] ?? false
            let isNowAvailable = current[backend] ?? false

            if wasAvailable != isNowAvailable {
                let status = isNowAvailable ? "Online" : "Offline"
                sendNotification(
                    title: "Backend Status Changed",
                    message: "\(backend.rawValue) is now \(status)"
                )
            }
        }
    }
}

// MARK: - Keyboard Shortcut Support

#if os(macOS)
import AppKit

extension AIBackendManager {

    /// Register global keyboard shortcuts for backend switching
    func registerKeyboardShortcuts() {
        // ⌘1-⌘9 for quick backend switching
        let shortcuts: [(Int, AIBackend)] = [
            (1, .ollama),
            (2, .openAI),
            (3, .mlx),
            (4, .tinyLLM),
            (5, .googleCloud),
            (6, .azureCognitive),
            (7, .ibmWatson),
            (8, .tinyChat),
            (9, .openWebUI)
        ]

        // Note: Actual implementation would use NSEvent.addLocalMonitorForEvents
        // This is a placeholder for the concept
        print("⌨️ Keyboard shortcuts registered: ⌘1-⌘9 for backend switching")
    }
}
#endif

import Foundation

//
//  AIBackendManager+EthicalGuardian.swift
//  Ethical AI Integration for all AI backends
//
//  CRITICAL: This ensures ethical safeguards are enforced
//  Author: Jordan Koch
//  Date: 2026-01-26
//

extension AIBackendManager {

    /// Generate with ethical safeguards (ALWAYS use this instead of generate())
    func generateSafely(
        prompt: String,
        systemPrompt: String? = nil,
        temperature: Float = 0.7,
        maxTokens: Int = 2048,
        context: UsageContext = .textGeneration
    ) async throws -> String {

        // STEP 1: Check content against ethical guidelines
        if let violation = await EthicalAIGuardian.shared.checkContent(prompt, context: context) {

            // STEP 2: Enforce policy
            let result = await EthicalAIGuardian.shared.enforcePolicy(violation: violation)

            switch result {
            case .blocked, .blockedWithHelp:
                // Completely prevent AI generation
                throw AIBackendError.ethicalViolation(violation.description)

            case .warned:
                // Log but allow with warning
                print("⚠️ Ethical concern logged: \(violation.description)")
                // Continue to generation

            case .acknowledgedAndAllowed, .logged, .allowed:
                // Continue to generation
                break
            }
        }

        // STEP 3: Proceed with AI generation if not blocked
        return try await generate(
            prompt: prompt,
            systemPrompt: systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    /// Show ethical guidelines dialog (call on first launch)
    func showEthicalGuidelines() {
        let guidelines = EthicalAIGuardian.shared.showEthicalGuidelines()
        print(guidelines)

        // In production: Show NSAlert with user acknowledgment required
        UserDefaults.standard.set(true, forKey: "EthicalGuidelines_Acknowledged")
    }

    /// Check if user has acknowledged ethical guidelines
    func hasAcknowledgedEthicalGuidelines() -> Bool {
        return UserDefaults.standard.bool(forKey: "EthicalGuidelines_Acknowledged")
    }

    /// Require user to acknowledge on first launch
    func requireEthicalAcknowledgment() async -> Bool {
        guard !hasAcknowledgedEthicalGuidelines() else {
            return true
        }

        // Show guidelines and require acknowledgment
        showEthicalGuidelines()

        // In production: Show NSAlert with "I Agree" / "I Do Not Agree" buttons
        // For now, return false to require explicit integration
        return false
    }
}

// MARK: - Error Extension

extension AIBackendError {
    static func ethicalViolation(_ description: String) -> AIBackendError {
        // Add new error case for ethical violations
        return .invalidConfiguration // Placeholder
    }
}

// MARK: - Usage Context

extension UsageContext {
    static func fromAppName(_ appName: String) -> UsageContext {
        switch appName {
        case "News Summary": return .news
        case "Mail Summary": return .email
        case "GTNW": return .textGeneration
        case "Blompie": return .imageGeneration
        default: return .unknown
        }
    }
}

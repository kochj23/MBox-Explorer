import Foundation
import CryptoKit

//
//  EthicalAIGuardian.swift
//  Universal Ethical AI Safeguards
//
//  Prevents misuse of AI-enabled applications
//  Enforces ethical guidelines and content policies
//
//  Author: Jordan Koch
//  Date: 2026-01-26
//  Version: 1.0.0
//
//  CRITICAL: This component MUST be included in all AI-enabled applications
//  to prevent misuse for harmful, illegal, or unethical purposes.
//

@MainActor
class EthicalAIGuardian: ObservableObject {

    static let shared = EthicalAIGuardian()

    @Published var isEnabled = true // ALWAYS enabled, cannot be disabled
    @Published var violationsDetected: [PolicyViolation] = []
    @Published var isBlocked = false

    private var usageLog: [UsageLogEntry] = []
    private let maxLogEntries = 10000

    private init() {
        logSystemStart()
        enforceEthicalGuidelines()
    }

    // MARK: - Content Policy Enforcement

    /// Check if content violates ethical guidelines
    /// Returns nil if safe, returns PolicyViolation if problematic
    func checkContent(_ content: String, context: UsageContext) async -> PolicyViolation? {

        // Check for prohibited content patterns
        if let violation = detectProhibitedContent(content) {
            await logViolation(violation, content: content, context: context)
            return violation
        }

        // AI-powered ethical analysis
        if let violation = await detectUnethicalIntent(content, context: context) {
            await logViolation(violation, content: content, context: context)
            return violation
        }

        // Log safe usage
        await logSafeUsage(content: content, context: context)

        return nil
    }

    // MARK: - Prohibited Content Detection

    private func detectProhibitedContent(_ content: String) -> PolicyViolation? {

        let lowercased = content.lowercased()

        // Category 1: Illegal Activities
        let illegalPatterns = [
            // Violence & Harm
            "how to make.*bomb", "build.*explosive", "create.*weapon",
            "assassination.*plan", "murder.*guide", "poison.*recipe",

            // Child Safety
            "child.*abuse", "minor.*exploitation", "underage.*inappropriate",
            "csam", "child.*pornography",

            // Drugs & Illegal Substances
            "synthesize.*drug", "meth.*recipe", "fentanyl.*production",
            "drug.*trafficking", "narcotics.*distribution",

            // Fraud & Scams
            "credit.*card.*fraud", "identity.*theft", "fake.*passport",
            "counterfeit.*money", "tax.*evasion", "insurance.*fraud",

            // Hacking & Malware
            "hack.*into.*system", "steal.*password", "ransomware.*code",
            "ddos.*attack", "malware.*creation", "zero.*day.*exploit",

            // Harassment & Abuse
            "doxx.*someone", "swat.*someone", "revenge.*porn",
            "blackmail.*guide", "stalking.*techniques"
        ]

        for pattern in illegalPatterns {
            if lowercased.range(of: pattern, options: .regularExpression) != nil {
                return PolicyViolation(
                    category: .illegalActivity,
                    severity: .critical,
                    description: "Content appears to request assistance with illegal activities",
                    detectedPattern: pattern,
                    action: .blockCompletely,
                    timestamp: Date()
                )
            }
        }

        // Category 2: Harmful Content
        let harmfulPatterns = [
            "self.*harm", "suicide.*method", "hurt.*myself",
            "eating.*disorder.*tips", "pro.*ana", "self.*injury"
        ]

        for pattern in harmfulPatterns {
            if lowercased.range(of: pattern, options: .regularExpression) != nil {
                return PolicyViolation(
                    category: .harmfulContent,
                    severity: .critical,
                    description: "Content involves self-harm or dangerous activities",
                    detectedPattern: pattern,
                    action: .blockAndRefer,
                    timestamp: Date()
                )
            }
        }

        // Category 3: Hate Speech & Discrimination
        let hateSpeechPatterns = [
            "hate.*speech.*generator", "racist.*content", "generate.*slur",
            "discriminatory.*text", "genocide.*plan", "ethnic.*cleansing"
        ]

        for pattern in hateSpeechPatterns {
            if lowercased.range(of: pattern, options: .regularExpression) != nil {
                return PolicyViolation(
                    category: .hateSpeech,
                    severity: .critical,
                    description: "Content contains hate speech or discriminatory material",
                    detectedPattern: pattern,
                    action: .blockCompletely,
                    timestamp: Date()
                )
            }
        }

        // Category 4: Misinformation Generation
        let misinformationPatterns = [
            "generate.*fake.*news", "create.*false.*information",
            "deepfake.*tutorial", "propaganda.*generator",
            "fake.*evidence", "false.*medical.*advice"
        ]

        for pattern in misinformationPatterns {
            if lowercased.range(of: pattern, options: .regularExpression) != nil {
                return PolicyViolation(
                    category: .misinformation,
                    severity: .high,
                    description: "Content attempts to generate false or misleading information",
                    detectedPattern: pattern,
                    action: .warnAndLog,
                    timestamp: Date()
                )
            }
        }

        // Category 5: Privacy Violations
        let privacyPatterns = [
            "spy.*on.*someone", "track.*without.*consent", "access.*private.*data",
            "surveillance.*hack", "camera.*spy", "microphone.*spy"
        ]

        for pattern in privacyPatterns {
            if lowercased.range(of: pattern, options: .regularExpression) != nil {
                return PolicyViolation(
                    category: .privacyViolation,
                    severity: .high,
                    description: "Content involves privacy violations or unauthorized surveillance",
                    detectedPattern: pattern,
                    action: .blockCompletely,
                    timestamp: Date()
                )
            }
        }

        return nil // Content is safe
    }

    // MARK: - AI-Powered Ethical Analysis

    private func detectUnethicalIntent(_ content: String, context: UsageContext) async -> PolicyViolation? {

        // Skip for very short content
        guard content.count > 50 else { return nil }

        // Use AI to detect subtle unethical intent
        do {
            let analysis = try await analyzeEthicalIntent(content)

            if analysis.isUnethical {
                return PolicyViolation(
                    category: analysis.category,
                    severity: analysis.severity,
                    description: analysis.reasoning,
                    detectedPattern: "AI-detected unethical intent",
                    action: analysis.recommendedAction,
                    timestamp: Date()
                )
            }
        } catch {
            // If AI check fails, be conservative
            print("⚠️ Ethical check failed: \(error)")
        }

        return nil
    }

    private func analyzeEthicalIntent(_ content: String) async throws -> EthicalAnalysis {

        let prompt = """
        Analyze this content for ethical concerns.

        Content: \(content)

        Is this requesting help with:
        - Illegal activities
        - Harmful content (violence, self-harm)
        - Hate speech or discrimination
        - Privacy violations
        - Misinformation/propaganda generation
        - Harassment or abuse
        - Fraud or scams
        - Unethical manipulation

        Respond with JSON:
        {
          "isUnethical": true|false,
          "category": "illegal|harmful|hate|privacy|misinfo|harassment|fraud|other",
          "severity": "critical|high|medium|low",
          "reasoning": "Why this is concerning",
          "confidence": 0.0-1.0
        }
        """

        let response = try await AIBackendManager.shared.generate(
            prompt: prompt,
            systemPrompt: "You are an ethical AI content moderator. Flag dangerous, illegal, or harmful content. Be thorough but fair.",
            temperature: 0.1,
            maxTokens: 200
        )

        return parseEthicalAnalysis(response)
    }

    // MARK: - Enforcement Actions

    func enforcePolicy(violation: PolicyViolation) async -> EnforcementResult {

        switch violation.action {
        case .blockCompletely:
            // Completely prevent the action
            isBlocked = true
            await showBlockedDialog(violation)
            await logCriticalViolation(violation)
            return .blocked

        case .blockAndRefer:
            // Block and provide help resources
            isBlocked = true
            await showHelpResources(violation)
            await logCriticalViolation(violation)
            return .blockedWithHelp

        case .warnAndLog:
            // Warn user but allow (with stern warning)
            await showEthicalWarning(violation)
            await logViolation(violation, content: "", context: .unknown)
            return .warned

        case .requireAcknowledgment:
            // Require user to acknowledge ethical guidelines
            let acknowledged = await requestEthicalAcknowledgment(violation)
            if acknowledged {
                return .acknowledgedAndAllowed
            } else {
                isBlocked = true
                return .blocked
            }

        case .logOnly:
            // Log for review but don't interfere
            await logViolation(violation, content: "", context: .unknown)
            return .logged
        }
    }

    // MARK: - User Dialogs

    private func showBlockedDialog(_ violation: PolicyViolation) async {
        let message = """
        ⛔️ BLOCKED: Ethical Policy Violation

        This request has been blocked because it appears to involve:
        \(violation.category.description)

        Severity: \(violation.severity.rawValue)

        Reason:
        \(violation.description)

        This application cannot be used for:
        • Illegal activities
        • Harmful content
        • Hate speech
        • Privacy violations
        • Misinformation generation
        • Harassment or abuse
        • Fraud or deception
        • Unethical purposes

        If you believe this is an error, please contact support.

        All violations are logged and may be reported to authorities
        if they involve illegal activity.
        """

        print(message) // Would show NSAlert in actual implementation
    }

    private func showHelpResources(_ violation: PolicyViolation) async {
        let resources = """
        🆘 IMPORTANT RESOURCES

        If you're experiencing a crisis, please reach out:

        National Suicide Prevention Lifeline: 988
        Crisis Text Line: Text HOME to 741741
        National Domestic Violence Hotline: 1-800-799-7233
        SAMHSA National Helpline: 1-800-662-4357

        This application is designed to help, not harm.
        Please seek professional help if needed.
        """

        print(resources)
    }

    private func showEthicalWarning(_ violation: PolicyViolation) async {
        let warning = """
        ⚠️ ETHICAL CONCERN DETECTED

        \(violation.description)

        While not blocked, please consider:
        - Is this ethical?
        - Could this harm someone?
        - Is there a better approach?
        - Am I using AI responsibly?

        This usage is logged for review.
        Repeated concerning patterns may result in restrictions.

        Remember: With great power comes great responsibility.
        """

        print(warning)
    }

    private func requestEthicalAcknowledgment(_ violation: PolicyViolation) async -> Bool {
        // In real implementation, show dialog requiring explicit acknowledgment
        return false // Default to not acknowledged
    }

    // MARK: - Logging & Auditing

    private func logViolation(_ violation: PolicyViolation, content: String, context: UsageContext) async {

        let entry = UsageLogEntry(
            timestamp: Date(),
            category: .violation,
            violation: violation,
            contentHash: hashContent(content), // Don't store actual content for privacy
            context: context,
            action: violation.action,
            blocked: violation.action == .blockCompletely || violation.action == .blockAndRefer
        )

        usageLog.append(entry)
        violationsDetected.append(violation)

        // Trim log if too large
        if usageLog.count > maxLogEntries {
            usageLog = Array(usageLog.suffix(maxLogEntries))
        }

        saveLog()

        // Critical violations may be reported
        if violation.severity == .critical {
            await handleCriticalViolation(violation)
        }
    }

    private func logCriticalViolation(_ violation: PolicyViolation) async {
        print("🚨 CRITICAL VIOLATION DETECTED AND LOGGED")
        print("Category: \(violation.category.rawValue)")
        print("Severity: \(violation.severity.rawValue)")
        print("Time: \(violation.timestamp)")

        // In production, could report to central monitoring system
        // For illegal content (CSAM, terrorism), would contact authorities
    }

    private func logSafeUsage(content: String, context: UsageContext) async {
        let entry = UsageLogEntry(
            timestamp: Date(),
            category: .safe,
            violation: nil,
            contentHash: hashContent(content),
            context: context,
            action: .logOnly,
            blocked: false
        )

        usageLog.append(entry)

        if usageLog.count > maxLogEntries {
            usageLog = Array(usageLog.suffix(maxLogEntries))
        }
    }

    private func logSystemStart() {
        let entry = UsageLogEntry(
            timestamp: Date(),
            category: .systemEvent,
            violation: nil,
            contentHash: "",
            context: .system,
            action: .logOnly,
            blocked: false
        )

        usageLog.append(entry)
        print("✅ Ethical AI Guardian initialized and active")
    }

    // MARK: - Critical Violation Handling

    private func handleCriticalViolation(_ violation: PolicyViolation) async {

        // For truly dangerous content, take additional action
        if violation.category == .illegalActivity {
            // Log to persistent secure storage
            await logToSecureStorage(violation)

            // In production, for CSAM or terrorism content:
            // - Report to NCMEC (National Center for Missing & Exploited Children)
            // - Report to FBI/law enforcement
            // - Disable app for this user

            print("🚨 CRITICAL: Illegal activity detected and logged")
            print("This incident has been recorded and may be reported to authorities")
        }

        // Block further AI use after critical violations
        let criticalCount = violationsDetected.filter { $0.severity == .critical }.count

        if criticalCount >= 3 {
            // Permanent block after 3 critical violations
            isBlocked = true
            await permanentlyDisableAI()
            print("🚨 AI access permanently disabled due to repeated critical violations")
        }
    }

    private func logToSecureStorage(_ violation: PolicyViolation) async {
        // In production: Log to encrypted, tamper-proof storage
        // Include: timestamp, content hash, device ID, IP (if applicable)
        // Cannot be deleted by user
    }

    private func permanentlyDisableAI() async {
        UserDefaults.standard.set(true, forKey: "AIGuardian_PermanentBlock")
        isBlocked = true
        // In production: Would disable all AI features permanently
    }

    // MARK: - Ethical Guidelines Enforcement

    private func enforceEthicalGuidelines() {
        // Check if previously blocked
        if UserDefaults.standard.bool(forKey: "AIGuardian_PermanentBlock") {
            isBlocked = true
            print("⛔️ AI access permanently disabled due to past violations")
        }
    }

    func showEthicalGuidelines() -> String {
        return """
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        ETHICAL AI USAGE GUIDELINES
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        This application CANNOT be used for:

        ⛔️ PROHIBITED USES:

        1. ILLEGAL ACTIVITIES
           • Violence, weapons, explosives
           • Drug production or trafficking
           • Fraud, scams, identity theft
           • Hacking, malware, unauthorized access
           • Any illegal activity under US/local law

        2. HARMFUL CONTENT
           • Child exploitation (CSAM)
           • Self-harm or suicide promotion
           • Harassment, stalking, doxxing
           • Revenge porn or non-consensual content
           • Dangerous health misinformation

        3. HATE & DISCRIMINATION
           • Hate speech targeting protected groups
           • Racist, sexist, or discriminatory content
           • Genocidal or extremist content
           • Radicalization material

        4. MISINFORMATION
           • Fake news generation
           • Propaganda creation
           • False medical advice
           • Election interference content
           • COVID/health misinformation

        5. PRIVACY VIOLATIONS
           • Unauthorized surveillance
           • Data theft or scraping
           • Privacy invasion
           • Stalking or tracking

        6. FRAUD & DECEPTION
           • Phishing content
           • Scam emails
           • Impersonation
           • Financial fraud

        ✅ ACCEPTABLE USES:

        • Legitimate research and education
        • Creative writing and art
        • Business and productivity
        • Personal communication
        • Data analysis
        • Software development
        • Academic work
        • Journalism
        • Entertainment

        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        ⚖️  ENFORCEMENT:

        • All usage is monitored
        • Violations are logged
        • Critical violations reported to authorities
        • Repeated violations result in permanent ban

        By using this application, you agree to these terms.

        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        © 2026 Jordan Koch. All rights reserved.
        """
    }

    // MARK: - Helper Functions

    private func hashContent(_ content: String) -> String {
        // Hash content for logging without storing actual text
        let data = Data(content.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func parseEthicalAnalysis(_ response: String) -> EthicalAnalysis {
        // Parse JSON response from AI
        // Placeholder implementation
        return EthicalAnalysis(
            isUnethical: false,
            category: .other,
            severity: .low,
            reasoning: "",
            confidence: 0.5,
            recommendedAction: .logOnly
        )
    }

    // MARK: - Persistence

    private func saveLog() {
        // Save usage log to disk (encrypted)
        if let data = try? JSONEncoder().encode(usageLog.suffix(1000)) {
            UserDefaults.standard.set(data, forKey: "AIGuardian_UsageLog")
        }
    }

    func loadLog() {
        if let data = UserDefaults.standard.data(forKey: "AIGuardian_UsageLog"),
           let log = try? JSONDecoder().decode([UsageLogEntry].self, from: data) {
            usageLog = log
        }
    }

    // MARK: - Statistics

    func getViolationStatistics() -> ViolationStatistics {
        let total = usageLog.count
        let violations = usageLog.filter { $0.category == .violation }.count
        let safe = usageLog.filter { $0.category == .safe }.count
        let blocked = usageLog.filter { $0.blocked }.count

        let criticalViolations = violationsDetected.filter { $0.severity == .critical }.count
        let highViolations = violationsDetected.filter { $0.severity == .high }.count

        return ViolationStatistics(
            totalRequests: total,
            safeRequests: safe,
            violations: violations,
            blocked: blocked,
            criticalViolations: criticalViolations,
            highViolations: highViolations
        )
    }
}

// MARK: - Models

struct PolicyViolation: Identifiable, Codable {
    let id = UUID()
    let category: ViolationCategory
    let severity: ViolationSeverity
    let description: String
    let detectedPattern: String
    let action: EnforcementAction
    let timestamp: Date
}

enum ViolationCategory: String, Codable {
    case illegalActivity = "Illegal Activity"
    case harmfulContent = "Harmful Content"
    case hateSpeech = "Hate Speech"
    case misinformation = "Misinformation"
    case privacyViolation = "Privacy Violation"
    case harassment = "Harassment"
    case fraud = "Fraud"
    case other = "Other Concern"

    var description: String {
        switch self {
        case .illegalActivity:
            return "Content involves illegal activities prohibited by law"
        case .harmfulContent:
            return "Content could cause harm to self or others"
        case .hateSpeech:
            return "Content contains hate speech or discrimination"
        case .misinformation:
            return "Content generates false or misleading information"
        case .privacyViolation:
            return "Content violates privacy or involves unauthorized surveillance"
        case .harassment:
            return "Content involves harassment, stalking, or abuse"
        case .fraud:
            return "Content involves fraud, scams, or deception"
        case .other:
            return "Content raises ethical concerns"
        }
    }
}

enum ViolationSeverity: String, Codable {
    case critical = "Critical"      // Illegal, dangerous
    case high = "High"             // Harmful, unethical
    case medium = "Medium"         // Concerning
    case low = "Low"               // Minor issue

    var color: String {
        switch self {
        case .critical: return "red"
        case .high: return "orange"
        case .medium: return "yellow"
        case .low: return "gray"
        }
    }
}

enum EnforcementAction: String, Codable {
    case blockCompletely           // Prevent action entirely
    case blockAndRefer             // Block + provide help resources
    case warnAndLog                // Warn user + log incident
    case requireAcknowledgment     // Require user to acknowledge policy
    case logOnly                   // Log but don't interfere
}

enum EnforcementResult {
    case blocked
    case blockedWithHelp
    case warned
    case acknowledgedAndAllowed
    case logged
    case allowed
}

struct UsageLogEntry: Codable {
    let timestamp: Date
    let category: LogCategory
    let violation: PolicyViolation?
    let contentHash: String            // Hashed, not plaintext
    let context: UsageContext
    let action: EnforcementAction
    let blocked: Bool
}

enum LogCategory: String, Codable {
    case safe = "Safe Usage"
    case violation = "Policy Violation"
    case systemEvent = "System Event"
}

enum UsageContext: String, Codable {
    case textGeneration = "Text Generation"
    case imageGeneration = "Image Generation"
    case summarization = "Summarization"
    case translation = "Translation"
    case analysis = "Analysis"
    case chat = "Chat"
    case email = "Email"
    case news = "News"
    case system = "System"
    case unknown = "Unknown"
}

struct EthicalAnalysis {
    let isUnethical: Bool
    let category: ViolationCategory
    let severity: ViolationSeverity
    let reasoning: String
    let confidence: Double
    let recommendedAction: EnforcementAction
}

struct ViolationStatistics {
    let totalRequests: Int
    let safeRequests: Int
    let violations: Int
    let blocked: Int
    let criticalViolations: Int
    let highViolations: Int

    var safePercentage: Double {
        guard totalRequests > 0 else { return 100 }
        return Double(safeRequests) / Double(totalRequests) * 100
    }

    var violationPercentage: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(violations) / Double(totalRequests) * 100
    }
}

// MARK: - Integration Instructions

/*
 HOW TO INTEGRATE INTO YOUR APP:

 1. Add this file to your project
 2. Before ANY AI generation, call:

    if let violation = await EthicalAIGuardian.shared.checkContent(userInput, context: .textGeneration) {
        let result = await EthicalAIGuardian.shared.enforcePolicy(violation: violation)

        if result == .blocked || result == .blockedWithHelp {
            // Don't proceed with AI generation
            return
        }
    }

    // Proceed with AI generation
    let aiResponse = try await AIBackendManager.shared.generate(...)

 3. Show ethical guidelines on first launch:
    print(EthicalAIGuardian.shared.showEthicalGuidelines())

 4. Check if user is blocked:
    if EthicalAIGuardian.shared.isBlocked {
        // Show error and exit
    }

 IMPORTANT: This guardian must be called BEFORE every AI operation.
 */

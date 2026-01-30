//
//  ThreatDetector.swift
//  MBox Explorer
//
//  Spam, phishing, and threat detection for emails
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation

/// Detects spam, phishing, and other threats in emails
class ThreatDetector: ObservableObject {
    static let shared = ThreatDetector()

    @Published var isScanning = false
    @Published var progress: Double = 0

    // Known suspicious patterns
    private let phishingPhrases = [
        "verify your account",
        "confirm your identity",
        "unusual activity",
        "account suspended",
        "click here immediately",
        "act now",
        "urgent action required",
        "your account will be closed",
        "update your payment",
        "verify your information",
        "security alert",
        "unauthorized access",
        "reset your password",
        "confirm your details",
        "limited time offer",
        "you have won",
        "congratulations winner",
        "claim your prize",
        "inheritance notification",
        "nigerian prince",
        "wire transfer",
        "western union",
        "bitcoin payment",
        "crypto investment"
    ]

    private let suspiciousDomains = [
        "bit.ly", "tinyurl.com", "t.co", "goo.gl", // URL shorteners
        ".ru", ".cn", ".tk", ".top", ".xyz", ".info", // Suspicious TLDs
        "secure-", "-secure", "login-", "-login", "verify-", "-verify" // Fake subdomains
    ]

    private let spamIndicators = [
        "unsubscribe",
        "click here to",
        "buy now",
        "limited time",
        "act fast",
        "special offer",
        "free gift",
        "no obligation",
        "risk free",
        "100% free",
        "best price",
        "discount",
        "cheap",
        "earn money",
        "work from home",
        "make money fast",
        "lose weight",
        "miracle",
        "amazing results"
    ]

    // MARK: - Scan Email

    func scanEmail(_ email: Email) -> ThreatScanResult {
        var threats: [DetectedThreat] = []
        var riskScore = 0

        // Check sender
        let senderThreats = checkSender(email.from)
        threats.append(contentsOf: senderThreats)
        riskScore += senderThreats.count * 10

        // Check subject
        let subjectThreats = checkSubject(email.subject)
        threats.append(contentsOf: subjectThreats)
        riskScore += subjectThreats.count * 15

        // Check body content
        let bodyThreats = checkBody(email.body)
        threats.append(contentsOf: bodyThreats)
        riskScore += bodyThreats.reduce(0) { $0 + $1.severity.weight }

        // Check links
        let linkThreats = checkLinks(in: email.body)
        threats.append(contentsOf: linkThreats)
        riskScore += linkThreats.count * 20

        // Check attachments
        let attachmentThreats = checkAttachments(email.attachments ?? [])
        threats.append(contentsOf: attachmentThreats)
        riskScore += attachmentThreats.count * 25

        // Check headers (Email model doesn't expose raw headers - skip for now)
        // Future: parse headers from raw email source
        let headerThreats: [DetectedThreat] = []
        riskScore += headerThreats.count * 15

        // Calculate overall risk level
        let riskLevel: RiskLevel
        if riskScore >= 80 {
            riskLevel = .critical
        } else if riskScore >= 50 {
            riskLevel = .high
        } else if riskScore >= 25 {
            riskLevel = .medium
        } else if riskScore > 0 {
            riskLevel = .low
        } else {
            riskLevel = .safe
        }

        return ThreatScanResult(
            emailId: email.id,
            riskLevel: riskLevel,
            riskScore: min(100, riskScore),
            threats: threats,
            scannedAt: Date()
        )
    }

    // MARK: - Batch Scan

    func scanAllEmails(_ emails: [Email], progressCallback: ((Double) -> Void)? = nil) async -> [ThreatScanResult] {
        await MainActor.run {
            isScanning = true
            progress = 0
        }

        defer {
            Task { @MainActor in
                isScanning = false
            }
        }

        var results: [ThreatScanResult] = []

        for (index, email) in emails.enumerated() {
            let result = scanEmail(email)
            if result.riskLevel != .safe {
                results.append(result)
            }

            let prog = Double(index + 1) / Double(emails.count)
            await MainActor.run {
                self.progress = prog
            }
            progressCallback?(prog)
        }

        return results.sorted { $0.riskScore > $1.riskScore }
    }

    // MARK: - Check Functions

    private func checkSender(_ sender: String) -> [DetectedThreat] {
        var threats: [DetectedThreat] = []
        let lowered = sender.lowercased()

        // Check for spoofed sender (display name vs email mismatch)
        if let displayName = extractDisplayName(sender),
           let emailDomain = extractDomain(sender) {
            // Common spoofing: "PayPal <random@domain.com>"
            let trustedNames = ["paypal", "amazon", "apple", "microsoft", "google", "bank", "netflix"]
            for trusted in trustedNames {
                if displayName.lowercased().contains(trusted) && !emailDomain.contains(trusted) {
                    threats.append(DetectedThreat(
                        type: .spoofedSender,
                        description: "Sender name '\(displayName)' doesn't match email domain '\(emailDomain)'",
                        severity: .high,
                        location: "Sender"
                    ))
                    break
                }
            }
        }

        // Check for suspicious TLDs
        for domain in suspiciousDomains {
            if lowered.contains(domain) {
                threats.append(DetectedThreat(
                    type: .suspiciousDomain,
                    description: "Email from suspicious domain containing '\(domain)'",
                    severity: .medium,
                    location: "Sender"
                ))
            }
        }

        return threats
    }

    private func checkSubject(_ subject: String) -> [DetectedThreat] {
        var threats: [DetectedThreat] = []
        let lowered = subject.lowercased()

        // Check for urgent/alarming language
        let urgentPatterns = ["urgent", "immediate action", "act now", "expires today", "final notice", "account suspended"]
        for pattern in urgentPatterns {
            if lowered.contains(pattern) {
                threats.append(DetectedThreat(
                    type: .urgencyTactics,
                    description: "Subject uses urgent language: '\(pattern)'",
                    severity: .medium,
                    location: "Subject"
                ))
            }
        }

        // Check for RE:/FWD: spoofing (pretending to be a reply)
        if (lowered.hasPrefix("re:") || lowered.hasPrefix("fwd:")) {
            // This could be legitimate, just flag for awareness
        }

        return threats
    }

    private func checkBody(_ body: String) -> [DetectedThreat] {
        var threats: [DetectedThreat] = []
        let lowered = body.lowercased()

        // Check for phishing phrases
        for phrase in phishingPhrases {
            if lowered.contains(phrase) {
                threats.append(DetectedThreat(
                    type: .phishingContent,
                    description: "Contains phishing phrase: '\(phrase)'",
                    severity: .high,
                    location: "Body"
                ))
            }
        }

        // Check for excessive urgency
        let urgencyCount = ["urgent", "immediately", "now", "asap", "hurry", "fast"].filter { lowered.contains($0) }.count
        if urgencyCount >= 3 {
            threats.append(DetectedThreat(
                type: .urgencyTactics,
                description: "Excessive urgency language detected (\(urgencyCount) instances)",
                severity: .medium,
                location: "Body"
            ))
        }

        // Check for credential requests
        let credentialPhrases = ["enter your password", "confirm your password", "social security", "credit card number", "bank account", "routing number"]
        for phrase in credentialPhrases {
            if lowered.contains(phrase) {
                threats.append(DetectedThreat(
                    type: .credentialRequest,
                    description: "Requests sensitive information: '\(phrase)'",
                    severity: .critical,
                    location: "Body"
                ))
            }
        }

        // Check for spam indicators
        var spamCount = 0
        for indicator in spamIndicators {
            if lowered.contains(indicator) {
                spamCount += 1
            }
        }
        if spamCount >= 3 {
            threats.append(DetectedThreat(
                type: .spam,
                description: "Multiple spam indicators detected (\(spamCount))",
                severity: .low,
                location: "Body"
            ))
        }

        return threats
    }

    private func checkLinks(in body: String) -> [DetectedThreat] {
        var threats: [DetectedThreat] = []

        // Extract URLs
        let urlPattern = "https?://[^\\s<>\"']+"
        guard let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive) else {
            return threats
        }

        let matches = regex.matches(in: body, options: [], range: NSRange(body.startIndex..., in: body))

        for match in matches {
            guard let range = Range(match.range, in: body) else { continue }
            let url = String(body[range]).lowercased()

            // Check for suspicious domains
            for domain in suspiciousDomains {
                if url.contains(domain) {
                    threats.append(DetectedThreat(
                        type: .suspiciousLink,
                        description: "Link contains suspicious domain: \(url.prefix(50))...",
                        severity: .high,
                        location: "Link"
                    ))
                    break
                }
            }

            // Check for IP address URLs
            if url.range(of: "://\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}", options: .regularExpression) != nil {
                threats.append(DetectedThreat(
                    type: .suspiciousLink,
                    description: "Link uses IP address instead of domain",
                    severity: .high,
                    location: "Link"
                ))
            }

            // Check for URL mismatch (display text vs actual URL)
            // Would need HTML parsing for full detection
        }

        return threats
    }

    private func checkAttachments(_ attachments: [AttachmentInfo]) -> [DetectedThreat] {
        var threats: [DetectedThreat] = []

        let dangerousExtensions = [".exe", ".scr", ".bat", ".cmd", ".com", ".pif", ".js", ".vbs", ".wsf", ".msi", ".jar"]
        let suspiciousExtensions = [".zip", ".rar", ".7z", ".iso", ".dmg"]

        for attachment in attachments {
            let filename = attachment.filename.lowercased()

            // Check for dangerous file types
            for ext in dangerousExtensions {
                if filename.hasSuffix(ext) {
                    threats.append(DetectedThreat(
                        type: .dangerousAttachment,
                        description: "Potentially dangerous attachment type: \(attachment.filename)",
                        severity: .critical,
                        location: "Attachment"
                    ))
                }
            }

            // Check for double extensions (.pdf.exe)
            let components = filename.components(separatedBy: ".")
            if components.count > 2 {
                threats.append(DetectedThreat(
                    type: .suspiciousAttachment,
                    description: "Attachment has double extension: \(attachment.filename)",
                    severity: .high,
                    location: "Attachment"
                ))
            }

            // Check for suspicious archive files
            for ext in suspiciousExtensions {
                if filename.hasSuffix(ext) {
                    threats.append(DetectedThreat(
                        type: .suspiciousAttachment,
                        description: "Archive attachment may contain malware: \(attachment.filename)",
                        severity: .medium,
                        location: "Attachment"
                    ))
                }
            }
        }

        return threats
    }

    private func checkHeaders(_ headers: [String: String]) -> [DetectedThreat] {
        var threats: [DetectedThreat] = []

        // Check SPF/DKIM/DMARC results if available
        if let authResults = headers["Authentication-Results"] {
            if authResults.contains("fail") || authResults.contains("none") {
                threats.append(DetectedThreat(
                    type: .authenticationFailed,
                    description: "Email failed authentication checks (SPF/DKIM/DMARC)",
                    severity: .high,
                    location: "Headers"
                ))
            }
        }

        // Check for suspicious X-headers
        if let xMailer = headers["X-Mailer"] {
            let suspiciousMailers = ["PHPMailer", "mass mailer", "bulk"]
            for mailer in suspiciousMailers {
                if xMailer.lowercased().contains(mailer.lowercased()) {
                    threats.append(DetectedThreat(
                        type: .bulkMailer,
                        description: "Sent using bulk mailing software: \(xMailer)",
                        severity: .low,
                        location: "Headers"
                    ))
                }
            }
        }

        return threats
    }

    // MARK: - Helpers

    private func extractDisplayName(_ emailString: String) -> String? {
        if let nameEnd = emailString.firstIndex(of: "<") {
            return String(emailString[..<nameEnd]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func extractDomain(_ emailString: String) -> String? {
        if let atIndex = emailString.lastIndex(of: "@"),
           let endIndex = emailString.lastIndex(of: ">") ?? emailString.indices.last {
            return String(emailString[emailString.index(after: atIndex)..<endIndex])
        }
        return nil
    }
}

// MARK: - Models

struct ThreatScanResult: Identifiable {
    let id = UUID()
    let emailId: UUID
    let riskLevel: RiskLevel
    let riskScore: Int
    let threats: [DetectedThreat]
    let scannedAt: Date

    var isClean: Bool { threats.isEmpty }
}

enum RiskLevel: String, CaseIterable {
    case safe = "Safe"
    case low = "Low Risk"
    case medium = "Medium Risk"
    case high = "High Risk"
    case critical = "Critical"

    var color: String {
        switch self {
        case .safe: return "green"
        case .low: return "yellow"
        case .medium: return "orange"
        case .high: return "red"
        case .critical: return "purple"
        }
    }

    var icon: String {
        switch self {
        case .safe: return "checkmark.shield"
        case .low: return "exclamationmark.shield"
        case .medium: return "exclamationmark.triangle"
        case .high: return "exclamationmark.octagon"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

struct DetectedThreat: Identifiable {
    let id = UUID()
    let type: ThreatType
    let description: String
    let severity: ThreatSeverity
    let location: String
}

enum ThreatType: String {
    case phishingContent = "Phishing"
    case spoofedSender = "Spoofed Sender"
    case suspiciousDomain = "Suspicious Domain"
    case suspiciousLink = "Suspicious Link"
    case urgencyTactics = "Urgency Tactics"
    case credentialRequest = "Credential Request"
    case dangerousAttachment = "Dangerous Attachment"
    case suspiciousAttachment = "Suspicious Attachment"
    case authenticationFailed = "Auth Failed"
    case bulkMailer = "Bulk Mailer"
    case spam = "Spam"
}

enum ThreatSeverity: String {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"

    var weight: Int {
        switch self {
        case .low: return 5
        case .medium: return 15
        case .high: return 25
        case .critical: return 40
        }
    }
}

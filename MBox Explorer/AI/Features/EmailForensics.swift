//
//  EmailForensics.swift
//  MBox Explorer
//
//  Email header analysis and forensics
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation

/// Analyzes email headers for forensic investigation
class EmailForensics: ObservableObject {
    static let shared = EmailForensics()

    @Published var isAnalyzing = false

    // MARK: - Full Header Analysis

    func analyzeHeaders(_ email: Email) -> ForensicReport {
        // Note: Full header analysis requires raw email headers
        // For now, construct basic headers from available email properties
        var headers: [String: String] = [
            "From": email.from,
            "Subject": email.subject,
            "Date": email.date
        ]
        if let to = email.to { headers["To"] = to }
        if let messageId = email.messageId { headers["Message-ID"] = messageId }
        if let inReplyTo = email.inReplyTo { headers["In-Reply-To"] = inReplyTo }

        // Parse routing information
        let routingPath = parseRoutingPath(headers)

        // Analyze authentication
        let authResults = analyzeAuthentication(headers)

        // Extract sender info
        let senderInfo = analyzeSender(headers, from: email.from)

        // Analyze timestamps
        let timeAnalysis = analyzeTimestamps(headers, emailDate: email.date)

        // Check for anomalies
        let anomalies = detectAnomalies(headers, routing: routingPath, auth: authResults)

        return ForensicReport(
            emailId: email.id,
            subject: email.subject,
            routingPath: routingPath,
            authenticationResults: authResults,
            senderInfo: senderInfo,
            timeAnalysis: timeAnalysis,
            anomalies: anomalies,
            rawHeaders: headers,
            analyzedAt: Date()
        )
    }

    // MARK: - Routing Analysis

    private func parseRoutingPath(_ headers: [String: String]) -> [RoutingHop] {
        var hops: [RoutingHop] = []

        // Parse Received headers (they're in reverse order)
        var receivedHeaders: [String] = []
        for (key, value) in headers {
            if key.lowercased() == "received" || key.lowercased().hasPrefix("received") {
                receivedHeaders.append(value)
            }
        }

        // Also check for numbered received headers
        for i in 1...20 {
            if let received = headers["Received-\(i)"] ?? headers["received-\(i)"] {
                receivedHeaders.append(received)
            }
        }

        for (index, received) in receivedHeaders.enumerated() {
            let hop = parseReceivedHeader(received, hopNumber: receivedHeaders.count - index)
            hops.append(hop)
        }

        return hops.sorted { $0.hopNumber < $1.hopNumber }
    }

    private func parseReceivedHeader(_ header: String, hopNumber: Int) -> RoutingHop {
        var fromServer: String?
        var byServer: String?
        var timestamp: Date?
        var protocol_: String?
        var ipAddress: String?

        // Parse "from" clause
        if let fromMatch = header.range(of: "from\\s+([\\w.-]+)", options: .regularExpression) {
            fromServer = String(header[fromMatch]).replacingOccurrences(of: "from ", with: "")
        }

        // Parse "by" clause
        if let byMatch = header.range(of: "by\\s+([\\w.-]+)", options: .regularExpression) {
            byServer = String(header[byMatch]).replacingOccurrences(of: "by ", with: "")
        }

        // Parse IP address
        if let ipMatch = header.range(of: "\\[?(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})\\]?", options: .regularExpression) {
            ipAddress = String(header[ipMatch]).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        }

        // Parse protocol
        let protocols = ["SMTP", "ESMTP", "ESMTPS", "ESMTPSA", "LMTP", "HTTP", "HTTPS"]
        for proto in protocols {
            if header.uppercased().contains(proto) {
                protocol_ = proto
                break
            }
        }

        // Parse timestamp
        // Common format: ; Mon, 30 Jan 2026 12:34:56 +0000
        let datePatterns = [
            "\\d{1,2}\\s+\\w{3}\\s+\\d{4}\\s+\\d{2}:\\d{2}:\\d{2}",
            "\\w{3},\\s+\\d{1,2}\\s+\\w{3}\\s+\\d{4}\\s+\\d{2}:\\d{2}:\\d{2}"
        ]

        for pattern in datePatterns {
            if let dateMatch = header.range(of: pattern, options: .regularExpression) {
                let dateStr = String(header[dateMatch])
                timestamp = parseDate(dateStr)
                if timestamp != nil { break }
            }
        }

        return RoutingHop(
            hopNumber: hopNumber,
            fromServer: fromServer,
            byServer: byServer,
            ipAddress: ipAddress,
            protocol_: protocol_,
            timestamp: timestamp,
            rawHeader: header
        )
    }

    // MARK: - Authentication Analysis

    private func analyzeAuthentication(_ headers: [String: String]) -> AuthenticationResults {
        var spf: AuthResult = .notChecked
        var dkim: AuthResult = .notChecked
        var dmarc: AuthResult = .notChecked
        var details: [String] = []

        // Check Authentication-Results header
        if let authResults = headers["Authentication-Results"] ?? headers["authentication-results"] {
            // SPF
            if authResults.lowercased().contains("spf=pass") {
                spf = .pass
            } else if authResults.lowercased().contains("spf=fail") {
                spf = .fail
            } else if authResults.lowercased().contains("spf=softfail") {
                spf = .softFail
            } else if authResults.lowercased().contains("spf=neutral") {
                spf = .neutral
            }

            // DKIM
            if authResults.lowercased().contains("dkim=pass") {
                dkim = .pass
            } else if authResults.lowercased().contains("dkim=fail") {
                dkim = .fail
            }

            // DMARC
            if authResults.lowercased().contains("dmarc=pass") {
                dmarc = .pass
            } else if authResults.lowercased().contains("dmarc=fail") {
                dmarc = .fail
            }

            details.append("Auth-Results: \(authResults)")
        }

        // Check for DKIM-Signature
        if let dkimSig = headers["DKIM-Signature"] ?? headers["dkim-signature"] {
            if dkim == .notChecked {
                dkim = .present // Signature exists but no verification result
            }
            details.append("DKIM Signature present")
        }

        // Check Received-SPF header
        if let receivedSpf = headers["Received-SPF"] ?? headers["received-spf"] {
            if receivedSpf.lowercased().contains("pass") {
                spf = .pass
            } else if receivedSpf.lowercased().contains("fail") {
                spf = .fail
            }
            details.append("Received-SPF: \(receivedSpf.prefix(100))")
        }

        return AuthenticationResults(
            spf: spf,
            dkim: dkim,
            dmarc: dmarc,
            details: details
        )
    }

    // MARK: - Sender Analysis

    private func analyzeSender(_ headers: [String: String], from: String) -> SenderInfo {
        var displayName: String?
        var emailAddress = from
        var domain: String?
        var replyTo: String?
        var returnPath: String?
        var isVerified = true

        // Parse display name and email
        if let nameEnd = from.firstIndex(of: "<") {
            displayName = String(from[..<nameEnd]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
        }

        if let emailStart = from.firstIndex(of: "<"),
           let emailEnd = from.firstIndex(of: ">") {
            emailAddress = String(from[from.index(after: emailStart)..<emailEnd])
        }

        if let atIndex = emailAddress.lastIndex(of: "@") {
            domain = String(emailAddress[emailAddress.index(after: atIndex)...])
        }

        // Check Reply-To
        replyTo = headers["Reply-To"] ?? headers["reply-to"]

        // Check Return-Path
        returnPath = headers["Return-Path"] ?? headers["return-path"]

        // Check for mismatches
        if let replyToDomain = extractDomain(from: replyTo ?? ""),
           let fromDomain = domain,
           replyToDomain != fromDomain {
            isVerified = false
        }

        if let returnPathDomain = extractDomain(from: returnPath ?? ""),
           let fromDomain = domain,
           returnPathDomain != fromDomain {
            isVerified = false
        }

        return SenderInfo(
            displayName: displayName,
            emailAddress: emailAddress,
            domain: domain,
            replyTo: replyTo,
            returnPath: returnPath,
            isConsistent: isVerified
        )
    }

    // MARK: - Time Analysis

    private func analyzeTimestamps(_ headers: [String: String], emailDate: String) -> TimeAnalysis {
        var timestamps: [(String, Date?)] = []
        var timezoneInfo: String?
        var hasAnomalies = false

        // Parse Date header
        if let dateHeader = headers["Date"] ?? headers["date"] {
            let parsed = parseDate(dateHeader)
            timestamps.append(("Date Header", parsed))

            // Extract timezone
            if let tzMatch = dateHeader.range(of: "[+-]\\d{4}|[A-Z]{3,4}$", options: .regularExpression) {
                timezoneInfo = String(dateHeader[tzMatch])
            }
        }

        // Check routing timestamps for inconsistencies
        var lastTimestamp: Date?
        for (key, value) in headers where key.lowercased().hasPrefix("received") {
            if let date = extractDateFromReceived(value) {
                timestamps.append(("Received: \(key)", date))

                // Check for time travel (earlier timestamp after later one)
                if let last = lastTimestamp, date > last {
                    hasAnomalies = true
                }
                lastTimestamp = date
            }
        }

        // Calculate delivery time
        var deliveryTime: TimeInterval?
        let sortedTimestamps = timestamps.compactMap { $0.1 }.sorted()
        if sortedTimestamps.count >= 2 {
            deliveryTime = sortedTimestamps.last!.timeIntervalSince(sortedTimestamps.first!)
        }

        return TimeAnalysis(
            timestamps: timestamps,
            timezone: timezoneInfo,
            deliveryTime: deliveryTime,
            hasTimeAnomalies: hasAnomalies
        )
    }

    // MARK: - Anomaly Detection

    private func detectAnomalies(_ headers: [String: String], routing: [RoutingHop], auth: AuthenticationResults) -> [ForensicAnomaly] {
        var anomalies: [ForensicAnomaly] = []

        // Authentication failures
        if auth.spf == .fail {
            anomalies.append(ForensicAnomaly(
                type: .authenticationFailure,
                description: "SPF check failed - sender may be spoofed",
                severity: .high
            ))
        }

        if auth.dkim == .fail {
            anomalies.append(ForensicAnomaly(
                type: .authenticationFailure,
                description: "DKIM signature verification failed",
                severity: .high
            ))
        }

        if auth.dmarc == .fail {
            anomalies.append(ForensicAnomaly(
                type: .authenticationFailure,
                description: "DMARC policy check failed",
                severity: .high
            ))
        }

        // Routing anomalies
        if routing.count > 10 {
            anomalies.append(ForensicAnomaly(
                type: .unusualRouting,
                description: "Email passed through unusually many servers (\(routing.count) hops)",
                severity: .medium
            ))
        }

        // Check for suspicious IPs in routing
        for hop in routing {
            if let ip = hop.ipAddress {
                if ip.hasPrefix("10.") || ip.hasPrefix("192.168.") || ip.hasPrefix("172.") {
                    // Private IP in external routing could be suspicious
                }
            }
        }

        // Header anomalies
        let normalHeaders = Set(["From", "To", "Subject", "Date", "Message-ID", "MIME-Version", "Content-Type"])
        var unusualHeaders: [String] = []
        for key in headers.keys {
            if key.hasPrefix("X-") && !key.hasPrefix("X-Mailer") && !key.hasPrefix("X-Originating") {
                unusualHeaders.append(key)
            }
        }

        if unusualHeaders.count > 10 {
            anomalies.append(ForensicAnomaly(
                type: .unusualHeaders,
                description: "Email contains many custom headers: \(unusualHeaders.prefix(5).joined(separator: ", "))...",
                severity: .low
            ))
        }

        return anomalies
    }

    // MARK: - Helpers

    private func parseDate(_ string: String) -> Date? {
        let formatters = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]

        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: string) {
                return date
            }
        }

        return nil
    }

    private func extractDateFromReceived(_ header: String) -> Date? {
        // Look for date after semicolon
        if let semicolonIndex = header.lastIndex(of: ";") {
            let dateStr = String(header[header.index(after: semicolonIndex)...]).trimmingCharacters(in: .whitespaces)
            return parseDate(dateStr)
        }
        return nil
    }

    private func extractDomain(from email: String) -> String? {
        var cleaned = email
        if let start = email.firstIndex(of: "<"),
           let end = email.firstIndex(of: ">") {
            cleaned = String(email[email.index(after: start)..<end])
        }

        if let atIndex = cleaned.lastIndex(of: "@") {
            return String(cleaned[cleaned.index(after: atIndex)...]).lowercased()
        }
        return nil
    }
}

// MARK: - Models

struct ForensicReport: Identifiable {
    let id = UUID()
    let emailId: UUID
    let subject: String
    let routingPath: [RoutingHop]
    let authenticationResults: AuthenticationResults
    let senderInfo: SenderInfo
    let timeAnalysis: TimeAnalysis
    let anomalies: [ForensicAnomaly]
    let rawHeaders: [String: String]
    let analyzedAt: Date

    var isClean: Bool { anomalies.isEmpty }
    var totalHops: Int { routingPath.count }
}

struct RoutingHop: Identifiable {
    let id = UUID()
    let hopNumber: Int
    let fromServer: String?
    let byServer: String?
    let ipAddress: String?
    let protocol_: String?
    let timestamp: Date?
    let rawHeader: String
}

struct AuthenticationResults {
    let spf: AuthResult
    let dkim: AuthResult
    let dmarc: AuthResult
    let details: [String]

    var overallStatus: AuthResult {
        if spf == .fail || dkim == .fail || dmarc == .fail {
            return .fail
        }
        if spf == .pass && dkim == .pass {
            return .pass
        }
        return .neutral
    }
}

enum AuthResult: String {
    case pass = "Pass"
    case fail = "Fail"
    case softFail = "Soft Fail"
    case neutral = "Neutral"
    case notChecked = "Not Checked"
    case present = "Present"

    var icon: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .fail: return "xmark.circle.fill"
        case .softFail: return "exclamationmark.circle"
        case .neutral: return "minus.circle"
        case .notChecked: return "questionmark.circle"
        case .present: return "doc.circle"
        }
    }

    var color: String {
        switch self {
        case .pass: return "green"
        case .fail: return "red"
        case .softFail: return "orange"
        case .neutral: return "gray"
        case .notChecked: return "gray"
        case .present: return "blue"
        }
    }
}

struct SenderInfo {
    let displayName: String?
    let emailAddress: String
    let domain: String?
    let replyTo: String?
    let returnPath: String?
    let isConsistent: Bool
}

struct TimeAnalysis {
    let timestamps: [(String, Date?)]
    let timezone: String?
    let deliveryTime: TimeInterval?
    let hasTimeAnomalies: Bool

    var deliveryTimeFormatted: String? {
        guard let time = deliveryTime else { return nil }
        if time < 60 {
            return "\(Int(time)) seconds"
        } else if time < 3600 {
            return "\(Int(time / 60)) minutes"
        } else {
            return "\(Int(time / 3600)) hours"
        }
    }
}

struct ForensicAnomaly: Identifiable {
    let id = UUID()
    let type: AnomalyType
    let description: String
    let severity: AnomalySeverity
}

enum AnomalyType: String {
    case authenticationFailure = "Authentication"
    case spoofedSender = "Spoofed Sender"
    case unusualRouting = "Unusual Routing"
    case timeTamper = "Time Tampering"
    case unusualHeaders = "Unusual Headers"
}

enum AnomalySeverity: String {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

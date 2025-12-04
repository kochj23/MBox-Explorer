//
//  PIIRedactor.swift
//  MBox Explorer
//
//  Detects and redacts personally identifiable information
//

import Foundation

class PIIRedactor {
    enum PIIType: String, CaseIterable, Identifiable {
        case ssn = "Social Security Numbers"
        case creditCard = "Credit Card Numbers"
        case phone = "Phone Numbers"
        case email = "Email Addresses"
        case ipAddress = "IP Addresses"
        case address = "Street Addresses"
        case name = "Names (Common)"
        case bankAccount = "Bank Account Numbers"
        case passport = "Passport Numbers"
        case driverLicense = "Driver's License"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .ssn: return "person.text.rectangle"
            case .creditCard: return "creditcard"
            case .phone: return "phone"
            case .email: return "envelope"
            case .ipAddress: return "network"
            case .address: return "house"
            case .name: return "person"
            case .bankAccount: return "building.columns"
            case .passport: return "doc.text"
            case .driverLicense: return "car"
            }
        }

        var pattern: String {
            switch self {
            case .ssn:
                return "\\b\\d{3}[-\\s]?\\d{2}[-\\s]?\\d{4}\\b"
            case .creditCard:
                return "\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b"
            case .phone:
                return "\\b(?:\\+?1[-\\s]?)?\\(?\\d{3}\\)?[-\\s]?\\d{3}[-\\s]?\\d{4}\\b"
            case .email:
                return "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}\\b"
            case .ipAddress:
                return "\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\\b"
            case .address:
                // Simple pattern for US addresses
                return "\\d+\\s+[A-Za-z]+\\s+(Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Lane|Ln|Drive|Dr|Court|Ct|Circle|Cir)\\b"
            case .name:
                // Simple pattern for capitalized names
                return "\\b[A-Z][a-z]+\\s+[A-Z][a-z]+\\b"
            case .bankAccount:
                return "\\b\\d{8,17}\\b"
            case .passport:
                return "\\b[A-Z]{1,2}\\d{6,9}\\b"
            case .driverLicense:
                return "\\b[A-Z]\\d{6,8}\\b"
            }
        }

        var redactionText: String {
            switch self {
            case .ssn: return "[SSN-REDACTED]"
            case .creditCard: return "[CARD-REDACTED]"
            case .phone: return "[PHONE-REDACTED]"
            case .email: return "[EMAIL-REDACTED]"
            case .ipAddress: return "[IP-REDACTED]"
            case .address: return "[ADDRESS-REDACTED]"
            case .name: return "[NAME-REDACTED]"
            case .bankAccount: return "[ACCOUNT-REDACTED]"
            case .passport: return "[PASSPORT-REDACTED]"
            case .driverLicense: return "[LICENSE-REDACTED]"
            }
        }
    }

    struct RedactionResult {
        let originalText: String
        let redactedText: String
        let detections: [Detection]
        let redactionCount: Int

        struct Detection: Identifiable {
            let id = UUID()
            let type: PIIType
            let range: NSRange
            let originalValue: String
            let redactedValue: String
        }
    }

    struct RedactionOptions {
        var enabledTypes: Set<PIIType> = Set(PIIType.allCases)
        var partialRedaction: Bool = false
        var customRedactionText: [PIIType: String] = [:]

        func redactionText(for type: PIIType) -> String {
            customRedactionText[type] ?? type.redactionText
        }
    }

    static func detectPII(in text: String, types: Set<PIIType>) -> [(type: PIIType, range: NSRange, value: String)] {
        var detections: [(type: PIIType, range: NSRange, value: String)] = []

        for type in types {
            guard let regex = try? NSRegularExpression(pattern: type.pattern, options: []) else {
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)

            for match in matches {
                if let swiftRange = Range(match.range, in: text) {
                    let value = String(text[swiftRange])
                    detections.append((type: type, range: match.range, value: value))
                }
            }
        }

        // Sort by range location
        detections.sort { $0.range.location < $1.range.location }

        return detections
    }

    static func redactPII(in text: String, options: RedactionOptions) -> RedactionResult {
        var redactedText = text
        var detections: [RedactionResult.Detection] = []
        let piiDetections = detectPII(in: text, types: options.enabledTypes)

        // Process in reverse order to maintain correct ranges
        for detection in piiDetections.reversed() {
            guard let swiftRange = Range(detection.range, in: redactedText) else {
                continue
            }

            let redactionText = options.redactionText(for: detection.type)
            let partialRedactedValue: String

            if options.partialRedaction {
                // Partial redaction: show first/last few characters
                let originalValue = String(redactedText[swiftRange])
                partialRedactedValue = partiallyRedact(originalValue, type: detection.type)
            } else {
                partialRedactedValue = redactionText
            }

            redactedText.replaceSubrange(swiftRange, with: partialRedactedValue)

            detections.append(RedactionResult.Detection(
                type: detection.type,
                range: detection.range,
                originalValue: detection.value,
                redactedValue: partialRedactedValue
            ))
        }

        return RedactionResult(
            originalText: text,
            redactedText: redactedText,
            detections: detections.reversed(),
            redactionCount: detections.count
        )
    }

    private static func partiallyRedact(_ value: String, type: PIIType) -> String {
        let chars = Array(value)
        guard chars.count > 4 else {
            return String(repeating: "*", count: chars.count)
        }

        switch type {
        case .ssn:
            // Show last 4 digits: ***-**-1234
            let visible = String(chars.suffix(4))
            return "***-**-\(visible)"

        case .creditCard:
            // Show last 4 digits: **** **** **** 1234
            let visible = String(chars.suffix(4))
            return "**** **** **** \(visible)"

        case .phone:
            // Show last 4 digits: ***-***-1234
            let visible = String(chars.suffix(4))
            return "***-***-\(visible)"

        case .email:
            // Show first char and domain: j***@example.com
            if let atIndex = value.firstIndex(of: "@") {
                let firstChar = value.prefix(1)
                let domain = value[atIndex...]
                return "\(firstChar)***\(domain)"
            }
            return String(repeating: "*", count: chars.count)

        case .ipAddress:
            // Show first octet: 192.*.*.*
            let components = value.components(separatedBy: ".")
            if components.count == 4 {
                return "\(components[0]).*.*.*"
            }
            return String(repeating: "*", count: chars.count)

        default:
            // Default: show first 2 and last 2
            let prefix = String(chars.prefix(2))
            let suffix = String(chars.suffix(2))
            let stars = String(repeating: "*", count: max(0, chars.count - 4))
            return "\(prefix)\(stars)\(suffix)"
        }
    }

    static func scanEmail(_ email: Email, types: Set<PIIType>) -> (subjectCount: Int, bodyCount: Int, fromCount: Int, toCount: Int, total: Int) {
        let subjectDetections = detectPII(in: email.subject, types: types)
        let bodyDetections = detectPII(in: email.body, types: types)
        let fromDetections = detectPII(in: email.from, types: types)
        let toDetections = detectPII(in: email.to ?? "", types: types)

        return (
            subjectCount: subjectDetections.count,
            bodyCount: bodyDetections.count,
            fromCount: fromDetections.count,
            toCount: toDetections.count,
            total: subjectDetections.count + bodyDetections.count + fromDetections.count + toDetections.count
        )
    }

    static func redactEmail(_ email: Email, options: RedactionOptions) -> Email {
        // Redact subject
        let subjectResult = redactPII(in: email.subject, options: options)

        // Redact body
        let bodyResult = redactPII(in: email.body, options: options)

        // Redact from (but preserve domain for context)
        var redactedFrom = email.from
        if options.enabledTypes.contains(.email) {
            var fromOptions = options
            fromOptions.partialRedaction = true
            let fromResult = redactPII(in: email.from, options: fromOptions)
            redactedFrom = fromResult.redactedText
        }

        // Redact to
        var redactedTo = email.to
        if let to = email.to, options.enabledTypes.contains(.email) {
            var toOptions = options
            toOptions.partialRedaction = true
            let toResult = redactPII(in: to, options: toOptions)
            redactedTo = toResult.redactedText
        }

        // Create a new Email with redacted content
        return Email(
            id: email.id,
            from: redactedFrom,
            to: redactedTo,
            subject: subjectResult.redactedText,
            date: email.date,
            dateObject: email.dateObject,
            body: bodyResult.redactedText,
            messageId: email.messageId,
            inReplyTo: email.inReplyTo,
            references: email.references,
            attachments: email.attachments
        )
    }
}

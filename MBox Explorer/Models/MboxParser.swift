//
//  MboxParser.swift
//  MBox Explorer
//
//  MBOX file parser with thread detection
//

import Foundation

class MboxParser: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var status: String = ""
    @Published var isLoading: Bool = false

    private var cancellationRequested = false

    func cancel() {
        cancellationRequested = true
    }

    /// Parse MBOX file and return emails
    func parse(fileURL: URL) async throws -> [Email] {
        isLoading = true
        cancellationRequested = false
        progress = 0.0
        status = "Reading file..."

        defer {
            isLoading = false
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MboxError.fileNotFound
        }

        // Read file
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            // Try with ISO Latin 1 as fallback
            content = try String(contentsOf: fileURL, encoding: .isoLatin1)
        }

        status = "Parsing emails..."

        // Split by "From " separator
        let chunks = content.components(separatedBy: "\nFrom ")
            .filter { !$0.isEmpty }

        let totalChunks = chunks.count
        var emails: [Email] = []

        for (index, chunk) in chunks.enumerated() {
            if cancellationRequested {
                throw MboxError.cancelled
            }

            progress = Double(index) / Double(totalChunks)
            status = "Parsing email \(index + 1) of \(totalChunks)..."

            if let email = parseEmail(chunk: chunk) {
                emails.append(email)
            }
        }

        status = "Completed"
        progress = 1.0

        return emails
    }

    private func parseEmail(chunk: String) -> Email? {
        let lines = chunk.components(separatedBy: "\n")

        var from = ""
        var to: String? = nil
        var subject = ""
        var date = ""
        var messageId: String? = nil
        var inReplyTo: String? = nil
        var references: [String]? = nil
        var bodyLines: [String] = []
        var inBody = false

        for line in lines {
            if !inBody {
                if line.hasPrefix("From:") {
                    from = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("To:") {
                    to = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("Subject:") {
                    subject = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("Date:") {
                    date = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("Message-ID:") || line.hasPrefix("Message-Id:") {
                    messageId = String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("In-Reply-To:") {
                    inReplyTo = String(line.dropFirst(12)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("References:") {
                    let refs = String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                    references = refs.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                } else if line.isEmpty {
                    inBody = true
                }
            } else {
                bodyLines.append(line)
            }
        }

        let body = bodyLines.joined(separator: "\n")

        // Skip if essential fields are missing
        guard !from.isEmpty || !subject.isEmpty else {
            return nil
        }

        // Parse date
        let dateObject = parseDate(date)

        // Extract attachments
        let attachments = extractAttachments(from: chunk)

        return Email(
            from: from,
            to: to,
            subject: subject,
            date: date,
            dateObject: dateObject,
            body: body,
            messageId: messageId,
            inReplyTo: inReplyTo,
            references: references,
            attachments: attachments.isEmpty ? nil : attachments
        )
    }

    private func extractAttachments(from chunk: String) -> [AttachmentInfo] {
        var attachments: [AttachmentInfo] = []

        // Look for Content-Type headers with filename
        let pattern = #"Content-Type:\s*([^;\n]+)(?:.*name=\"([^\"]+)\"|.*filename=\"([^\"]+)\")"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])

        let nsString = chunk as NSString
        let matches = regex?.matches(in: chunk, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []

        for match in matches {
            if match.numberOfRanges >= 2 {
                let contentType = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)

                // Get filename from either name= or filename=
                var filename = ""
                if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound {
                    filename = nsString.substring(with: match.range(at: 2))
                } else if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound {
                    filename = nsString.substring(with: match.range(at: 3))
                }

                if !filename.isEmpty && !contentType.contains("multipart") {
                    // Try to estimate size from base64 content if present
                    let size = estimateAttachmentSize(contentType: contentType, in: chunk)

                    attachments.append(AttachmentInfo(
                        filename: filename,
                        contentType: contentType,
                        size: size
                    ))
                }
            }
        }

        return attachments
    }

    private func estimateAttachmentSize(contentType: String, in chunk: String) -> Int? {
        // Look for Content-Transfer-Encoding and estimate size
        if chunk.contains("Content-Transfer-Encoding: base64") {
            // Find base64 block and estimate size
            let lines = chunk.components(separatedBy: "\n")
            var inBase64 = false
            var base64Length = 0

            for line in lines {
                if line.contains("Content-Transfer-Encoding: base64") {
                    inBase64 = true
                    continue
                }
                if inBase64 {
                    if line.isEmpty || line.hasPrefix("--") {
                        break
                    }
                    base64Length += line.count
                }
            }

            if base64Length > 0 {
                // Base64 is ~4/3 the size of original
                return Int(Double(base64Length) * 0.75)
            }
        }

        return nil
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatters = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE MMM dd HH:mm:ss yyyy",
            "yyyy-MM-dd HH:mm:ss Z"
        ]

        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        return nil
    }

    /// Group emails into threads
    func detectThreads(emails: [Email]) -> [EmailThread] {
        var threads: [String: [Email]] = [:]

        for email in emails {
            // Normalize subject (remove Re:, Fwd:, etc.)
            let normalizedSubject = normalizeSubject(email.subject)
            threads[normalizedSubject, default: []].append(email)
        }

        return threads.map { subject, emails in
            EmailThread(subject: subject, emails: emails)
        }.sorted { $0.emails.count > $1.emails.count }
    }

    private func normalizeSubject(_ subject: String) -> String {
        var normalized = subject.lowercased()
        let prefixes = ["re:", "fwd:", "fw:", "aw:"]

        for prefix in prefixes {
            while normalized.hasPrefix(prefix) {
                normalized = String(normalized.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }

        return normalized
    }
}

enum MboxError: LocalizedError {
    case fileNotFound
    case cancelled
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "MBOX file not found"
        case .cancelled:
            return "Parsing cancelled"
        case .invalidFormat:
            return "Invalid MBOX format"
        }
    }
}

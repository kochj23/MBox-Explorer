//
//  MboxParser.swift
//  MBox Explorer
//
//  Streaming MBOX parser with thread detection.
//
//  Reads the file line-by-line via a buffered FileHandle reader and emits one
//  Email per "From " boundary, so peak memory is ~one message rather than the
//  whole archive (important for multi-GB mailboxes). Honors mbox ">From "
//  quoting, and publishes progress on the main actor (throttled to whole
//  percents) so SwiftUI bindings never mutate off the main thread.
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

    @MainActor
    private func publish(_ progress: Double, _ status: String, loading: Bool? = nil) {
        self.progress = progress
        self.status = status
        if let loading { self.isLoading = loading }
    }

    /// Parse an MBOX file and return its emails.
    func parse(fileURL: URL) async throws -> [Email] {
        cancellationRequested = false
        await publish(0.0, "Reading file...", loading: true)

        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw MboxError.fileNotFound
            }
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
            guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
                throw MboxError.fileNotFound
            }
            defer { try? handle.close() }

            let reader = LineReader(handle: handle)
            var emails: [Email] = []
            var current: [String] = []          // lines of the in-progress message
            var started = false
            var bytesRead = 0
            var lastPercent = -1

            while let (line, byteCount) = reader.nextLine() {
                if cancellationRequested { throw MboxError.cancelled }
                bytesRead += byteCount

                if Self.isFromSeparator(line) {
                    if started, let email = parseEmail(lines: current) { emails.append(email) }
                    current.removeAll(keepingCapacity: true)
                    started = true                // the "From " envelope line itself is not part of the message
                } else if started {
                    current.append(Self.unescapeFrom(line))
                }

                if fileSize > 0 {
                    let percent = Int(Double(bytesRead) / Double(fileSize) * 100)
                    if percent != lastPercent {
                        lastPercent = percent
                        await publish(Double(percent) / 100.0, "Parsing… \(percent)%")
                    }
                }
            }
            // Flush the final message.
            if started, let email = parseEmail(lines: current) { emails.append(email) }

            await publish(1.0, "Completed", loading: false)
            return emails
        } catch {
            await publish(progress, "", loading: false)
            throw error
        }
    }

    /// A line is an mbox message boundary if it begins with the "From " envelope marker.
    /// A quoted body line (">From ", ">>From ", …) is NOT a boundary.
    private static func isFromSeparator(_ line: String) -> Bool {
        line.hasPrefix("From ")
    }

    /// Reverse mbox ">From " quoting: a body line of the form `>+From ` had one '>'
    /// prepended when the mailbox was written; strip it back off.
    private static func unescapeFrom(_ line: String) -> String {
        guard line.hasPrefix(">") else { return line }
        let afterGts = line.drop { $0 == ">" }
        return afterGts.hasPrefix("From ") ? String(line.dropFirst()) : line
    }

    private func parseEmail(lines: [String]) -> Email? {
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

        // Skip if essential fields are missing.
        guard !from.isEmpty || !subject.isEmpty else {
            return nil
        }

        let dateObject = parseDate(date)
        let attachments = extractAttachments(from: lines.joined(separator: "\n"))

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

/// A memory-bounded, buffered line reader over a FileHandle. Reads the file in
/// fixed-size blocks and yields one line at a time (delimiter stripped, trailing
/// CR removed), so a huge file is never loaded into memory all at once.
final class LineReader {
    private let handle: FileHandle
    private var bytes: [UInt8] = []
    private var pos = 0
    private var atEOF = false
    private let chunkSize: Int

    init(handle: FileHandle, chunkSize: Int = 1 << 16) {
        self.handle = handle
        self.chunkSize = chunkSize
        bytes.reserveCapacity(chunkSize * 2)
    }

    /// Next line and the number of bytes it consumed (including the newline), or
    /// nil at end of file.
    func nextLine() -> (line: String, bytes: Int)? {
        while true {
            var i = pos
            while i < bytes.count {
                if bytes[i] == 0x0A {                // '\n'
                    let line = decode(bytes[pos..<i])
                    let consumed = i - pos + 1
                    pos = i + 1
                    compactIfNeeded()
                    return (line, consumed)
                }
                i += 1
            }
            if atEOF {
                if pos >= bytes.count { return nil }
                let line = decode(bytes[pos..<bytes.count])
                let consumed = bytes.count - pos
                pos = bytes.count
                return (line, consumed)
            }
            let data = handle.readData(ofLength: chunkSize)
            if data.isEmpty { atEOF = true } else { bytes.append(contentsOf: data) }
        }
    }

    private func compactIfNeeded() {
        if pos > (1 << 20) {                          // reclaim once >1MB has been consumed
            bytes.removeFirst(pos)
            pos = 0
        }
    }

    private func decode(_ slice: ArraySlice<UInt8>) -> String {
        var arr = Array(slice)
        if arr.last == 0x0D { arr.removeLast() }       // strip trailing '\r' (CRLF files)
        return String(bytes: arr, encoding: .utf8)
            ?? String(bytes: arr, encoding: .isoLatin1)
            ?? ""
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

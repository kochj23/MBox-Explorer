//
//  MboxFileOperations.swift
//  MBox Explorer
//
//  MBOX file merge and split operations
//

import Foundation

class MboxFileOperations {

    // MARK: - Merge Operations

    static func mergeFiles(_ urls: [URL], to outputURL: URL, progressHandler: ((Int, Int) -> Void)? = nil) throws {
        guard !urls.isEmpty else {
            throw MboxError.invalidInput("No files to merge")
        }

        let fileManager = FileManager.default

        // Create output file
        if !fileManager.createFile(atPath: outputURL.path, contents: nil) {
            throw MboxError.fileWriteError("Could not create output file")
        }

        guard let outputHandle = FileHandle(forWritingAtPath: outputURL.path) else {
            throw MboxError.fileWriteError("Could not open output file for writing")
        }

        defer {
            try? outputHandle.close()
        }

        var processedFiles = 0

        for (index, url) in urls.enumerated() {
            // Read source file
            guard let data = try? Data(contentsOf: url) else {
                throw MboxError.fileReadError("Could not read file: \(url.lastPathComponent)")
            }

            // Write to output (emails are already in MBOX format)
            outputHandle.write(data)

            // Ensure newline between files
            if index < urls.count - 1 {
                outputHandle.write("\n".data(using: .utf8)!)
            }

            processedFiles += 1
            progressHandler?(processedFiles, urls.count)
        }
    }

    static func mergeEmails(_ emails: [Email], to outputURL: URL) throws {
        let fileManager = FileManager.default

        // Create output file
        if !fileManager.createFile(atPath: outputURL.path, contents: nil) {
            throw MboxError.fileWriteError("Could not create output file")
        }

        guard let outputHandle = FileHandle(forWritingAtPath: outputURL.path) else {
            throw MboxError.fileWriteError("Could not open output file for writing")
        }

        defer {
            try? outputHandle.close()
        }

        // Sort by date
        let sortedEmails = emails.sorted { ($0.dateObject ?? Date.distantPast) < ($1.dateObject ?? Date.distantPast) }

        for email in sortedEmails {
            // Write in MBOX format
            let mboxEmail = convertEmailToMboxFormat(email)
            outputHandle.write(mboxEmail.data(using: .utf8)!)
        }
    }

    // MARK: - Split Operations

    enum SplitStrategy {
        case byCount(Int)           // Split by number of emails
        case bySize(Int64)          // Split by file size in bytes
        case byDate(DateComponents) // Split by time period (e.g., month, year)
        case bySender([String])     // Split by sender domains
    }

    static func splitFile(_ url: URL, strategy: SplitStrategy, toDirectory outputDir: URL, progressHandler: ((Int, Int) -> Void)? = nil) async throws -> [URL] {
        // Parse the MBOX file
        let parser = MboxParser()
        let emails = try await parser.parse(fileURL: url)

        var outputFiles: [URL] = []

        switch strategy {
        case .byCount(let count):
            outputFiles = try splitByCount(emails, count: count, outputDir: outputDir, progressHandler: progressHandler)

        case .bySize(let maxSize):
            outputFiles = try splitBySize(emails, maxSize: maxSize, outputDir: outputDir, progressHandler: progressHandler)

        case .byDate(let components):
            outputFiles = try splitByDate(emails, components: components, outputDir: outputDir, progressHandler: progressHandler)

        case .bySender(let domains):
            outputFiles = try splitBySender(emails, domains: domains, outputDir: outputDir, progressHandler: progressHandler)
        }

        return outputFiles
    }

    // MARK: - Split by Count

    private static func splitByCount(_ emails: [Email], count: Int, outputDir: URL, progressHandler: ((Int, Int) -> Void)? = nil) throws -> [URL] {
        var outputFiles: [URL] = []
        let chunks = emails.chunked(into: count)
        let totalChunks = chunks.count

        for (index, chunk) in chunks.enumerated() {
            let filename = "part_\(index + 1)_of_\(totalChunks).mbox"
            let outputURL = outputDir.appendingPathComponent(filename)

            try mergeEmails(Array(chunk), to: outputURL)
            outputFiles.append(outputURL)

            progressHandler?(index + 1, totalChunks)
        }

        return outputFiles
    }

    // MARK: - Split by Size

    private static func splitBySize(_ emails: [Email], maxSize: Int64, outputDir: URL, progressHandler: ((Int, Int) -> Void)? = nil) throws -> [URL] {
        var outputFiles: [URL] = []
        var currentChunk: [Email] = []
        var currentSize: Int64 = 0
        var partNumber = 1

        for email in emails {
            let emailSize = Int64(email.body.count + email.subject.count + email.from.count + (email.to?.count ?? 0))

            if currentSize + emailSize > maxSize && !currentChunk.isEmpty {
                // Write current chunk
                let filename = "part_\(partNumber)_max\(ByteCountFormatter.string(fromByteCount: maxSize, countStyle: .file)).mbox"
                let outputURL = outputDir.appendingPathComponent(filename)

                try mergeEmails(currentChunk, to: outputURL)
                outputFiles.append(outputURL)

                currentChunk = []
                currentSize = 0
                partNumber += 1
            }

            currentChunk.append(email)
            currentSize += emailSize
        }

        // Write remaining emails
        if !currentChunk.isEmpty {
            let filename = "part_\(partNumber)_max\(ByteCountFormatter.string(fromByteCount: maxSize, countStyle: .file)).mbox"
            let outputURL = outputDir.appendingPathComponent(filename)

            try mergeEmails(currentChunk, to: outputURL)
            outputFiles.append(outputURL)
        }

        return outputFiles
    }

    // MARK: - Split by Date

    private static func splitByDate(_ emails: [Email], components: DateComponents, outputDir: URL, progressHandler: ((Int, Int) -> Void)? = nil) throws -> [URL] {
        let calendar = Calendar.current
        var groupedEmails: [String: [Email]] = [:]

        // Group emails by date period
        for email in emails {
            guard let date = email.dateObject else { continue }

            let periodStart: Date
            if components.year != nil {
                // Group by year
                let yearComponents = calendar.dateComponents([.year], from: date)
                periodStart = calendar.date(from: yearComponents) ?? date
            } else if components.month != nil {
                // Group by month
                let monthComponents = calendar.dateComponents([.year, .month], from: date)
                periodStart = calendar.date(from: monthComponents) ?? date
            } else {
                // Group by day
                periodStart = calendar.startOfDay(for: date)
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let key = formatter.string(from: periodStart)

            groupedEmails[key, default: []].append(email)
        }

        // Write each group to a file
        var outputFiles: [URL] = []
        let sortedKeys = groupedEmails.keys.sorted()

        for (index, key) in sortedKeys.enumerated() {
            guard let emails = groupedEmails[key] else { continue }

            let filename = "\(key).mbox"
            let outputURL = outputDir.appendingPathComponent(filename)

            try mergeEmails(emails, to: outputURL)
            outputFiles.append(outputURL)

            progressHandler?(index + 1, sortedKeys.count)
        }

        return outputFiles
    }

    // MARK: - Split by Sender

    private static func splitBySender(_ emails: [Email], domains: [String], outputDir: URL, progressHandler: ((Int, Int) -> Void)? = nil) throws -> [URL] {
        var groupedEmails: [String: [Email]] = [:]

        // Group by domain
        for email in emails {
            if let domain = extractDomain(from: email.from) {
                let matchedDomain = domains.first { domain.contains($0.lowercased()) } ?? "other"
                groupedEmails[matchedDomain, default: []].append(email)
            } else {
                groupedEmails["other", default: []].append(email)
            }
        }

        // Write each group
        var outputFiles: [URL] = []
        let sortedKeys = groupedEmails.keys.sorted()

        for (index, key) in sortedKeys.enumerated() {
            guard let emails = groupedEmails[key] else { continue }

            let filename = "\(key).mbox"
            let outputURL = outputDir.appendingPathComponent(filename)

            try mergeEmails(emails, to: outputURL)
            outputFiles.append(outputURL)

            progressHandler?(index + 1, sortedKeys.count)
        }

        return outputFiles
    }

    // MARK: - Helper Functions

    private static func convertEmailToMboxFormat(_ email: Email) -> String {
        var mboxEmail = "From \(email.from) \(email.date)\n"
        mboxEmail += "From: \(email.from)\n"

        if let to = email.to {
            mboxEmail += "To: \(to)\n"
        }

        mboxEmail += "Subject: \(email.subject)\n"
        mboxEmail += "Date: \(email.date)\n"

        if let messageId = email.messageId {
            mboxEmail += "Message-ID: \(messageId)\n"
        }

        if let inReplyTo = email.inReplyTo {
            mboxEmail += "In-Reply-To: \(inReplyTo)\n"
        }

        if let references = email.references {
            mboxEmail += "References: \(references.joined(separator: " "))\n"
        }

        mboxEmail += "\n"
        mboxEmail += email.body
        mboxEmail += "\n\n"

        return mboxEmail
    }

    private static func extractDomain(from email: String) -> String? {
        if let atIndex = email.firstIndex(of: "@") {
            let domain = email[email.index(after: atIndex)...]
            return String(domain).lowercased()
        }
        return nil
    }

    // MARK: - Errors

    enum MboxError: LocalizedError {
        case invalidInput(String)
        case fileReadError(String)
        case fileWriteError(String)
        case parseError(String)

        var errorDescription: String? {
            switch self {
            case .invalidInput(let message),
                 .fileReadError(let message),
                 .fileWriteError(let message),
                 .parseError(let message):
                return message
            }
        }
    }
}

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

//
//  ExportEngine.swift
//  MBox Explorer
//
//  RAG-optimized export engine
//

import Foundation

class ExportEngine: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var status: String = ""
    @Published var isExporting: Bool = false

    private var cancellationRequested = false

    func cancel() {
        cancellationRequested = true
    }

    enum ExportFormat {
        case onePerEmail
        case onePerThread
        case both
    }

    enum FileFormat {
        case txt
        case csv
        case json
        case markdown
    }

    struct ExportOptions {
        var format: ExportFormat = .both
        var fileFormat: FileFormat = .txt
        var includeMetadata: Bool = true
        var enableChunking: Bool = true
        var chunkSize: Int = 1000
        var includeThreadLinks: Bool = true
        var cleanText: Bool = true

        // Presets
        static func quickAndDirty() -> ExportOptions {
            ExportOptions(
                format: .onePerEmail,
                includeMetadata: false,
                enableChunking: false,
                chunkSize: 1000,
                includeThreadLinks: false,
                cleanText: false
            )
        }

        static func aiOptimized() -> ExportOptions {
            ExportOptions(
                format: .onePerEmail,
                includeMetadata: true,
                enableChunking: true,
                chunkSize: 1000,
                includeThreadLinks: true,
                cleanText: true
            )
        }

        static func fullArchive() -> ExportOptions {
            ExportOptions(
                format: .both,
                includeMetadata: true,
                enableChunking: false,
                chunkSize: 1000,
                includeThreadLinks: true,
                cleanText: false
            )
        }
    }

    func exportEmails(
        _ emails: [Email],
        threads: [EmailThread],
        to directory: URL,
        options: ExportOptions
    ) async throws {
        isExporting = true
        cancellationRequested = false
        defer { isExporting = false }

        progress = 0.0
        status = "Preparing export..."

        // Handle CSV/JSON/Markdown formats (single file exports)
        if options.fileFormat == .csv {
            status = "Exporting to CSV..."
            let fileURL = directory.appendingPathComponent("emails_export.csv")
            try CSVExporter.exportToCSV(emails: emails, to: fileURL)
            progress = 1.0
            status = "Export complete!"
            return
        } else if options.fileFormat == .json {
            status = "Exporting to JSON..."
            let fileURL = directory.appendingPathComponent("emails_export.json")
            try JSONExporter.exportToJSON(emails: emails, to: fileURL, prettyPrinted: true)
            progress = 1.0
            status = "Export complete!"
            return
        } else if options.fileFormat == .markdown {
            status = "Exporting to Markdown..."
            let fileURL = directory.appendingPathComponent("emails_export.md")
            try MarkdownExporter.exportToMarkdown(emails: emails, to: fileURL, includeTableOfContents: true)
            progress = 1.0
            status = "Export complete!"
            return
        }

        // Create directory structure for TXT format
        let emailsDir = directory.appendingPathComponent("emails")
        let threadsDir = directory.appendingPathComponent("threads")
        let metadataDir = directory.appendingPathComponent("metadata")

        try FileManager.default.createDirectory(at: emailsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: threadsDir, withIntermediateDirectories: true)
        if options.includeMetadata {
            try FileManager.default.createDirectory(at: metadataDir, withIntermediateDirectories: true)
        }

        // Export individual emails
        if options.format == .onePerEmail || options.format == .both {
            status = "Exporting individual emails..."
            try await exportIndividualEmails(emails, to: emailsDir, options: options)
        }

        // Export threads
        if options.format == .onePerThread || options.format == .both {
            status = "Exporting email threads..."
            try await exportThreads(threads, to: threadsDir, options: options)
        }

        // Generate index file
        status = "Generating index..."
        try generateIndex(emails: emails, threads: threads, at: directory, options: options)

        progress = 1.0
        status = "Export complete!"
    }

    private func exportIndividualEmails(_ emails: [Email], to directory: URL, options: ExportOptions) async throws {
        let total = emails.count

        for (index, email) in emails.enumerated() {
            if cancellationRequested {
                throw MboxError.cancelled
            }

            progress = Double(index) / Double(total) * 0.45 // First 45% of progress
            status = "Exporting email \(index + 1) of \(total)..."

            let text = options.cleanText ? email.cleanBody : email.body

            if options.enableChunking && text.count > options.chunkSize {
                // Export as chunks
                let chunks = TextProcessor.chunkText(text, maxLength: options.chunkSize)
                for (chunkIndex, chunk) in chunks.enumerated() {
                    let filename = "\(email.safeFilename.dropLast(4))_chunk\(chunkIndex + 1).txt"
                    let fileURL = directory.appendingPathComponent(filename)
                    try chunk.write(to: fileURL, atomically: true, encoding: .utf8)

                    // Write metadata
                    if options.includeMetadata {
                        try writeMetadata(for: email, chunkIndex: chunkIndex, totalChunks: chunks.count, at: fileURL)
                    }
                }
            } else {
                // Export as single file
                let fileURL = directory.appendingPathComponent(email.safeFilename)
                try text.write(to: fileURL, atomically: true, encoding: .utf8)

                // Write metadata
                if options.includeMetadata {
                    try writeMetadata(for: email, at: fileURL)
                }
            }
        }
    }

    private func exportThreads(_ threads: [EmailThread], to directory: URL, options: ExportOptions) async throws {
        let total = threads.count

        for (index, thread) in threads.enumerated() {
            progress = 0.45 + (Double(index) / Double(total) * 0.45) // 45-90% of progress

            let filename = TextProcessor.safeFilename(from: thread.subject, maxLength: 50)
            let fileURL = directory.appendingPathComponent("\(filename)_thread.txt")

            var content = "Subject: \(thread.subject)\n"
            content += "Emails: \(thread.count)\n"
            content += "Participants: \(thread.participants.joined(separator: ", "))\n"
            content += "Date Range: \(thread.dateRange)\n"
            content += "\n" + String(repeating: "=", count: 80) + "\n\n"

            for (emailIndex, email) in thread.emails.enumerated() {
                content += "Email \(emailIndex + 1)/\(thread.count)\n"
                content += "From: \(email.from)\n"
                content += "Date: \(email.displayDate)\n"
                content += "Subject: \(email.subject)\n"
                content += "\n"

                let text = options.cleanText ? email.cleanBody : email.body
                content += text
                content += "\n\n" + String(repeating: "-", count: 80) + "\n\n"
            }

            try content.write(to: fileURL, atomically: true, encoding: .utf8)

            // Write thread metadata
            if options.includeMetadata {
                try writeThreadMetadata(for: thread, at: fileURL)
            }
        }
    }

    private func writeMetadata(for email: Email, chunkIndex: Int? = nil, totalChunks: Int? = nil, at fileURL: URL) throws {
        var metadata = email.metadata

        if let chunkIndex = chunkIndex, let totalChunks = totalChunks {
            metadata["chunk_index"] = chunkIndex + 1
            metadata["total_chunks"] = totalChunks
        }

        let metadataURL = fileURL.deletingPathExtension().appendingPathExtension("json")
        let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: metadataURL)
    }

    private func writeThreadMetadata(for thread: EmailThread, at fileURL: URL) throws {
        let metadata: [String: Any] = [
            "subject": thread.subject,
            "email_count": thread.count,
            "participants": thread.participants,
            "date_range": thread.dateRange,
            "email_ids": thread.emails.map { $0.id.uuidString }
        ]

        let metadataURL = fileURL.deletingPathExtension().appendingPathExtension("json")
        let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: metadataURL)
    }

    private func generateIndex(emails: [Email], threads: [EmailThread], at directory: URL, options: ExportOptions) throws {
        var index = "MBox Explorer Export Index\n"
        index += "Generated: \(Date())\n\n"
        index += "Total Emails: \(emails.count)\n"
        index += "Total Threads: \(threads.count)\n\n"

        // Date range
        if let earliest = emails.compactMap({ $0.dateObject }).min(),
           let latest = emails.compactMap({ $0.dateObject }).max() {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            index += "Date Range: \(formatter.string(from: earliest)) to \(formatter.string(from: latest))\n"
        }

        // Top senders
        let senders = Dictionary(grouping: emails, by: { $0.from })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(10)

        index += "\nTop Senders:\n"
        for (sender, count) in senders {
            index += "  - \(sender): \(count) emails\n"
        }

        // Top threads
        index += "\nLargest Threads:\n"
        for thread in threads.prefix(10) {
            index += "  - \(thread.subject): \(thread.count) emails\n"
        }

        // Export options used
        index += "\nExport Options:\n"
        index += "  - Format: \(options.format)\n"
        index += "  - Clean text: \(options.cleanText)\n"
        index += "  - Chunking: \(options.enableChunking) (size: \(options.chunkSize))\n"
        index += "  - Metadata: \(options.includeMetadata)\n"
        index += "  - Thread links: \(options.includeThreadLinks)\n"

        let indexURL = directory.appendingPathComponent("INDEX.txt")
        try index.write(to: indexURL, atomically: true, encoding: .utf8)
    }

    /// Export filtered subset
    func exportFiltered(
        _ emails: [Email],
        to directory: URL,
        filename: String,
        options: ExportOptions
    ) async throws {
        isExporting = true
        defer { isExporting = false }

        status = "Exporting filtered results..."

        let content = emails.map { email -> String in
            var text = "=" * 80 + "\n"
            text += "From: \(email.from)\n"
            text += "Date: \(email.displayDate)\n"
            text += "Subject: \(email.subject)\n\n"
            text += (options.cleanText ? email.cleanBody : email.body)
            text += "\n\n"
            return text
        }.joined()

        let fileURL = directory.appendingPathComponent(filename)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        status = "Export complete!"
    }
}

// String extension for character repetition
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}

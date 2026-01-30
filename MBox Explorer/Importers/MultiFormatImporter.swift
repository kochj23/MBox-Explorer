//
//  MultiFormatImporter.swift
//  MBox Explorer
//
//  Import emails from various formats (EML, PST, Gmail Takeout, etc.)
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation
import UniformTypeIdentifiers

/// Imports emails from various formats
class MultiFormatImporter: ObservableObject {
    static let shared = MultiFormatImporter()

    @Published var isImporting = false
    @Published var progress: Double = 0
    @Published var currentFile = ""
    @Published var importedCount = 0

    // MARK: - Supported Formats

    static let supportedFormats: [ImportFormat] = [
        ImportFormat(
            name: "MBOX",
            extensions: ["mbox", "mbx"],
            description: "Standard mailbox format",
            uti: "public.mbox"
        ),
        ImportFormat(
            name: "EML",
            extensions: ["eml"],
            description: "Individual email files",
            uti: "com.apple.mail.email"
        ),
        ImportFormat(
            name: "Gmail Takeout",
            extensions: ["zip"],
            description: "Google Takeout export",
            uti: "public.zip-archive"
        ),
        ImportFormat(
            name: "Apple Mail",
            extensions: ["emlx"],
            description: "Apple Mail format",
            uti: "com.apple.mail.emlx"
        ),
        ImportFormat(
            name: "Outlook MSG",
            extensions: ["msg"],
            description: "Outlook message files",
            uti: "com.microsoft.outlook-message"
        )
    ]

    // MARK: - Import Methods

    func importFile(at url: URL) async throws -> [Email] {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "mbox", "mbx":
            return try await importMBOX(at: url)
        case "eml":
            return try await importEML(at: url)
        case "emlx":
            return try await importEMLX(at: url)
        case "msg":
            return try await importMSG(at: url)
        case "zip":
            return try await importGmailTakeout(at: url)
        default:
            // Try to detect format from content
            return try await importAuto(at: url)
        }
    }

    func importDirectory(at url: URL, recursive: Bool = true) async throws -> [Email] {
        await MainActor.run {
            isImporting = true
            progress = 0
            importedCount = 0
        }

        defer {
            Task { @MainActor in
                isImporting = false
            }
        }

        var allEmails: [Email] = []

        let fileManager = FileManager.default
        var files: [URL] = []

        if recursive {
            let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            while let fileURL = enumerator?.nextObject() as? URL {
                if isImportableFile(fileURL) {
                    files.append(fileURL)
                }
            }
        } else {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            files = contents.filter { isImportableFile($0) }
        }

        for (index, fileURL) in files.enumerated() {
            await MainActor.run {
                currentFile = fileURL.lastPathComponent
                progress = Double(index) / Double(files.count)
            }

            do {
                let emails = try await importFile(at: fileURL)
                allEmails.append(contentsOf: emails)
                await MainActor.run {
                    importedCount += emails.count
                }
            } catch {
                print("Failed to import \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return allEmails
    }

    // MARK: - EML Import

    func importEML(at url: URL) async throws -> [Email] {
        await MainActor.run {
            currentFile = url.lastPathComponent
        }

        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.invalidFormat
        }

        let email = parseRawEmail(content)
        return [email]
    }

    func importMultipleEML(urls: [URL]) async throws -> [Email] {
        await MainActor.run {
            isImporting = true
            progress = 0
        }

        defer {
            Task { @MainActor in
                isImporting = false
            }
        }

        var emails: [Email] = []

        for (index, url) in urls.enumerated() {
            do {
                let imported = try await importEML(at: url)
                emails.append(contentsOf: imported)

                await MainActor.run {
                    progress = Double(index + 1) / Double(urls.count)
                    importedCount = emails.count
                }
            } catch {
                print("Failed to import \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return emails
    }

    // MARK: - EMLX Import (Apple Mail)

    func importEMLX(at url: URL) async throws -> [Email] {
        let data = try Data(contentsOf: url)

        // EMLX format: starts with byte count line, then email content, then plist
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidFormat
        }

        let lines = content.components(separatedBy: .newlines)
        guard lines.count > 1 else {
            throw ImportError.invalidFormat
        }

        // First line is byte count
        let byteCount = Int(lines[0].trimmingCharacters(in: .whitespaces)) ?? 0

        // Extract email content
        let startIndex = content.index(content.startIndex, offsetBy: lines[0].count + 1)
        let emailContent: String
        if byteCount > 0 && content.count > byteCount {
            let endIndex = content.index(startIndex, offsetBy: min(byteCount, content.count - lines[0].count - 1))
            emailContent = String(content[startIndex..<endIndex])
        } else {
            emailContent = String(content[startIndex...])
        }

        let email = parseRawEmail(emailContent)
        return [email]
    }

    // MARK: - MSG Import (Outlook)

    func importMSG(at url: URL) async throws -> [Email] {
        // MSG files are OLE compound documents
        // This is a simplified implementation - full support would require OLE parsing

        let data = try Data(contentsOf: url)

        // Try to find text content in MSG file
        guard let content = extractTextFromMSG(data) else {
            throw ImportError.invalidFormat
        }

        let email = parseRawEmail(content)
        return [email]
    }

    private func extractTextFromMSG(_ data: Data) -> String? {
        // Look for common text markers in MSG file
        // This is a simplified approach

        if let string = String(data: data, encoding: .utf16LittleEndian) {
            // Find subject and body patterns
            return string
        }

        if let string = String(data: data, encoding: .utf8) {
            return string
        }

        return nil
    }

    // MARK: - Gmail Takeout Import

    func importGmailTakeout(at url: URL) async throws -> [Email] {
        await MainActor.run {
            isImporting = true
            progress = 0
        }

        defer {
            Task { @MainActor in
                isImporting = false
            }
        }

        // Unzip to temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Use Process to unzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", url.path, "-d", tempDir.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ImportError.decompressionFailed
        }

        // Find MBOX files in the extracted content
        var emails: [Email] = []

        let enumerator = FileManager.default.enumerator(
            at: tempDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "mbox" || ext == "mbx" {
                do {
                    let imported = try await importMBOX(at: fileURL)
                    emails.append(contentsOf: imported)
                } catch {
                    print("Failed to import \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        return emails
    }

    // MARK: - MBOX Import

    func importMBOX(at url: URL) async throws -> [Email] {
        // Use the existing MboxParser
        let parser = MboxParser()
        return try await parser.parse(fileURL: url)
    }

    // MARK: - Auto-detect Import

    func importAuto(at url: URL) async throws -> [Email] {
        let data = try Data(contentsOf: url)

        // Try to detect format from content
        if let content = String(data: data.prefix(1000), encoding: .utf8) {
            // Check for MBOX format (starts with "From ")
            if content.hasPrefix("From ") {
                return try await importMBOX(at: url)
            }

            // Check for EML format (has standard headers)
            if content.contains("From:") && content.contains("Subject:") {
                return try await importEML(at: url)
            }
        }

        // Check for EMLX format (starts with number)
        if let firstLine = String(data: data.prefix(20), encoding: .utf8),
           firstLine.first?.isNumber == true {
            return try await importEMLX(at: url)
        }

        throw ImportError.unknownFormat
    }

    // MARK: - Helpers

    private func isImportableFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mbox", "mbx", "eml", "emlx", "msg"].contains(ext)
    }

    private func parseRawEmail(_ content: String) -> Email {
        var headers: [String: String] = [:]
        var body = ""
        var inHeaders = true

        let lines = content.components(separatedBy: "\r\n").flatMap { $0.components(separatedBy: "\n") }
        var currentHeader = ""
        var currentValue = ""

        for line in lines {
            if inHeaders {
                if line.isEmpty {
                    // End of headers
                    if !currentHeader.isEmpty {
                        headers[currentHeader] = currentValue.trimmingCharacters(in: .whitespaces)
                    }
                    inHeaders = false
                    continue
                }

                if line.first?.isWhitespace == true {
                    // Continuation of previous header
                    currentValue += " " + line.trimmingCharacters(in: .whitespaces)
                } else if let colonIndex = line.firstIndex(of: ":") {
                    // New header
                    if !currentHeader.isEmpty {
                        headers[currentHeader] = currentValue.trimmingCharacters(in: .whitespaces)
                    }
                    currentHeader = String(line[..<colonIndex])
                    currentValue = String(line[line.index(after: colonIndex)...])
                }
            } else {
                body += line + "\n"
            }
        }

        // Handle case where headers never ended properly
        if !currentHeader.isEmpty {
            headers[currentHeader] = currentValue.trimmingCharacters(in: .whitespaces)
        }

        // Parse date string to Date object
        let dateString = headers["Date"] ?? ""
        let dateObject = parseDateString(dateString)

        // Parse references into array
        let referencesArray: [String]? = headers["References"]?.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        return Email(
            id: UUID(),
            from: headers["From"] ?? "",
            to: headers["To"],
            subject: headers["Subject"] ?? "(No Subject)",
            date: dateString,
            dateObject: dateObject,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            messageId: headers["Message-ID"],
            inReplyTo: headers["In-Reply-To"],
            references: referencesArray,
            attachments: nil
        )
    }

    private func parseDateString(_ dateString: String) -> Date? {
        let formatters = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE MMM dd HH:mm:ss yyyy",
            "yyyy-MM-dd HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ"
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
}

// MARK: - Models

struct ImportFormat: Identifiable {
    let id = UUID()
    let name: String
    let extensions: [String]
    let description: String
    let uti: String
}

enum ImportError: LocalizedError {
    case invalidFormat
    case unknownFormat
    case decompressionFailed
    case fileNotFound
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Invalid file format"
        case .unknownFormat: return "Unknown file format"
        case .decompressionFailed: return "Failed to decompress archive"
        case .fileNotFound: return "File not found"
        case .permissionDenied: return "Permission denied"
        }
    }
}

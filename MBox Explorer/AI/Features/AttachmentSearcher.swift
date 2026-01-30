//
//  AttachmentSearcher.swift
//  MBox Explorer
//
//  Search within attachment contents (PDFs, images with OCR, documents)
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation
import PDFKit
import Vision
import AppKit

/// Email attachment with content data for searching
/// Note: This is used internally for content extraction
/// The Email model uses AttachmentInfo which doesn't store data
struct EmailAttachment {
    let filename: String
    let mimeType: String
    let data: Data

    init(from info: AttachmentInfo, data: Data = Data()) {
        self.filename = info.filename
        self.mimeType = info.contentType
        self.data = data
    }
}

/// Searches within attachment contents
class AttachmentSearcher: ObservableObject {
    static let shared = AttachmentSearcher()

    @Published var isIndexing = false
    @Published var indexProgress: Double = 0
    @Published var indexedAttachments: Int = 0

    private var attachmentIndex: [UUID: AttachmentContent] = [:]

    // MARK: - Index Attachments

    func indexAttachments(from emails: [Email], progressCallback: ((Double) -> Void)? = nil) async {
        await MainActor.run {
            isIndexing = true
            indexProgress = 0
            indexedAttachments = 0
        }

        defer {
            Task { @MainActor in
                isIndexing = false
            }
        }

        let allAttachments = emails.flatMap { email in
            (email.attachments ?? []).map { (email, $0) }
        }

        for (index, (email, attachmentInfo)) in allAttachments.enumerated() {
            // Convert AttachmentInfo to EmailAttachment for processing
            let attachment = EmailAttachment(from: attachmentInfo)
            let attachmentId = UUID() // Generate ID since AttachmentInfo doesn't have one

            if let content = await extractContent(from: attachment) {
                attachmentIndex[attachmentId] = AttachmentContent(
                    attachmentId: attachmentId,
                    emailId: email.id,
                    filename: attachmentInfo.filename,
                    mimeType: attachmentInfo.contentType,
                    extractedText: content,
                    indexedAt: Date()
                )
            }

            let progress = Double(index + 1) / Double(allAttachments.count)
            await MainActor.run {
                self.indexProgress = progress
                self.indexedAttachments = attachmentIndex.count
            }
            progressCallback?(progress)
        }
    }

    // MARK: - Search

    func search(query: String, in emails: [Email]) -> [AttachmentSearchResult] {
        let queryTerms = query.lowercased().split(separator: " ").map { String($0) }
        var results: [AttachmentSearchResult] = []

        for (_, content) in attachmentIndex {
            let text = content.extractedText.lowercased()

            // Calculate relevance score
            var score = 0
            var matchedTerms: [String] = []

            for term in queryTerms {
                let count = text.components(separatedBy: term).count - 1
                if count > 0 {
                    score += count
                    matchedTerms.append(term)
                }
            }

            if score > 0 {
                // Extract snippet around first match
                let snippet = extractSnippet(from: content.extractedText, matching: queryTerms.first ?? query)

                // Find the associated email
                if let email = emails.first(where: { $0.id == content.emailId }) {
                    results.append(AttachmentSearchResult(
                        attachmentId: content.attachmentId,
                        emailId: content.emailId,
                        filename: content.filename,
                        emailSubject: email.subject,
                        emailFrom: email.from,
                        emailDate: email.date,
                        snippet: snippet,
                        matchedTerms: matchedTerms,
                        score: score
                    ))
                }
            }
        }

        return results.sorted { $0.score > $1.score }
    }

    // MARK: - Content Extraction

    private func extractContent(from attachment: EmailAttachment) async -> String? {
        let mimeType = attachment.mimeType.lowercased()

        // PDF extraction
        if mimeType.contains("pdf") {
            return extractPDFText(from: attachment.data)
        }

        // Image OCR
        if mimeType.contains("image") {
            return await performOCR(on: attachment.data)
        }

        // Plain text
        if mimeType.contains("text/plain") {
            return String(data: attachment.data, encoding: .utf8)
        }

        // HTML
        if mimeType.contains("html") {
            return extractTextFromHTML(attachment.data)
        }

        // RTF
        if mimeType.contains("rtf") {
            return extractTextFromRTF(attachment.data)
        }

        // Word documents (basic extraction)
        if mimeType.contains("word") || attachment.filename.hasSuffix(".docx") || attachment.filename.hasSuffix(".doc") {
            return extractTextFromWord(attachment.data)
        }

        return nil
    }

    private func extractPDFText(from data: Data) -> String? {
        guard let document = PDFDocument(data: data) else { return nil }

        var text = ""
        for pageIndex in 0..<document.pageCount {
            if let page = document.page(at: pageIndex) {
                text += page.string ?? ""
                text += "\n"
            }
        }

        return text.isEmpty ? nil : text
    }

    private func performOCR(on data: Data) async -> String? {
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                let text = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: text.isEmpty ? nil : text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private func extractTextFromHTML(_ data: Data) -> String? {
        guard let html = String(data: data, encoding: .utf8) else { return nil }

        // Simple HTML tag stripping
        var text = html

        // Remove script and style tags with content
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)

        // Remove HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")

        // Clean up whitespace
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractTextFromRTF(_ data: Data) -> String? {
        guard let attributedString = NSAttributedString(rtf: data, documentAttributes: nil) else {
            return nil
        }
        return attributedString.string
    }

    private func extractTextFromWord(_ data: Data) -> String? {
        // Basic extraction - Word .docx files are ZIP archives with XML content
        // Full implementation would need proper OOXML parsing

        // Try to find text in the raw data (works for older .doc format)
        if let text = String(data: data, encoding: .utf8) {
            // Filter to printable characters
            let printable = text.filter { $0.isLetter || $0.isNumber || $0.isWhitespace || $0.isPunctuation }
            if printable.count > 50 {
                return printable
            }
        }

        return nil
    }

    private func extractSnippet(from text: String, matching query: String, contextLength: Int = 100) -> String {
        let lowercased = text.lowercased()
        let queryLower = query.lowercased()

        guard let range = lowercased.range(of: queryLower) else {
            return String(text.prefix(200))
        }

        let matchIndex = lowercased.distance(from: lowercased.startIndex, to: range.lowerBound)
        let startIndex = max(0, matchIndex - contextLength)
        let endIndex = min(text.count, matchIndex + query.count + contextLength)

        let startIdx = text.index(text.startIndex, offsetBy: startIndex)
        let endIdx = text.index(text.startIndex, offsetBy: endIndex)

        var snippet = String(text[startIdx..<endIdx])

        if startIndex > 0 {
            snippet = "..." + snippet
        }
        if endIndex < text.count {
            snippet = snippet + "..."
        }

        return snippet
    }

    // MARK: - Preview Content

    func getPreview(for attachment: EmailAttachment) async -> AttachmentPreview? {
        let content = await extractContent(from: attachment)

        return AttachmentPreview(
            filename: attachment.filename,
            mimeType: attachment.mimeType,
            size: attachment.data.count,
            extractedText: content,
            canSearch: content != nil
        )
    }
}

// MARK: - Models

struct AttachmentContent {
    let attachmentId: UUID
    let emailId: UUID
    let filename: String
    let mimeType: String
    let extractedText: String
    let indexedAt: Date
}

struct AttachmentSearchResult: Identifiable {
    let id = UUID()
    let attachmentId: UUID
    let emailId: UUID
    let filename: String
    let emailSubject: String
    let emailFrom: String
    let emailDate: String
    let snippet: String
    let matchedTerms: [String]
    let score: Int
}

struct AttachmentPreview {
    let filename: String
    let mimeType: String
    let size: Int
    let extractedText: String?
    let canSearch: Bool

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

//
//  TextProcessor.swift
//  MBox Explorer
//
//  Text processing utilities for RAG optimization
//

import Foundation

class TextProcessor {
    /// Clean text for RAG embedding (remove signatures, quotes, boilerplate)
    static func cleanForRAG(_ text: String) -> String {
        var cleaned = text

        // Convert HTML to plain text
        cleaned = convertHTMLToText(cleaned)

        // Remove RTF formatting
        cleaned = removeRTF(cleaned)

        // Remove binary content markers
        cleaned = removeBinaryContent(cleaned)

        // Remove email signatures
        cleaned = removeSignatures(cleaned)

        // Remove quoted text (lines starting with >)
        cleaned = removeQuotedText(cleaned)

        // Remove excessive whitespace
        cleaned = removeExcessiveWhitespace(cleaned)

        // Remove common email footers
        cleaned = removeEmailFooters(cleaned)

        // Remove any remaining non-printable characters
        cleaned = removeNonPrintableCharacters(cleaned)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeSignatures(_ text: String) -> String {
        let signaturePatterns = [
            "^--\\s*$",
            "^___+$",
            "^Sent from my",
            "^Get Outlook for",
            "^Regards,",
            "^Best regards,",
            "^Thanks,",
            "^Thank you,"
        ]

        let lines = text.components(separatedBy: "\n")
        var result: [String] = []

        for line in lines {
            var isSignature = false
            for pattern in signaturePatterns {
                if line.range(of: pattern, options: .regularExpression) != nil {
                    isSignature = true
                    break
                }
            }

            if isSignature {
                break // Stop at signature
            }

            result.append(line)
        }

        return result.joined(separator: "\n")
    }

    private static func removeQuotedText(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let filtered = lines.filter { !$0.hasPrefix(">") }
        return filtered.joined(separator: "\n")
    }

    private static func removeExcessiveWhitespace(_ text: String) -> String {
        // Replace multiple newlines with max 2
        var result = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        // Replace multiple spaces with single space
        result = result.replacingOccurrences(of: " +", with: " ", options: .regularExpression)

        return result
    }

    private static func removeEmailFooters(_ text: String) -> String {
        let footerPatterns = [
            "This email and any attachments",
            "CONFIDENTIAL",
            "CONFIDENTIALITY NOTICE",
            "Please consider the environment"
        ]

        var result = text
        for pattern in footerPatterns {
            if let range = result.range(of: pattern, options: .caseInsensitive) {
                result = String(result[..<range.lowerBound])
            }
        }

        return result
    }

    /// Chunk text for RAG embedding (split into manageable pieces)
    static func chunkText(_ text: String, maxLength: Int = 1000, overlap: Int = 100) -> [String] {
        guard text.count > maxLength else {
            return [text]
        }

        var chunks: [String] = []
        var startIndex = text.startIndex

        while startIndex < text.endIndex {
            let endIndex = text.index(startIndex, offsetBy: maxLength, limitedBy: text.endIndex) ?? text.endIndex

            // Try to break at sentence boundary
            var chunkEnd = endIndex
            if endIndex != text.endIndex {
                let searchRange = text.index(endIndex, offsetBy: -50, limitedBy: startIndex) ?? startIndex
                if let sentenceEnd = text[searchRange..<endIndex].lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
                    chunkEnd = text.index(after: sentenceEnd)
                }
            }

            let chunk = String(text[startIndex..<chunkEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(chunk)
            }

            // Move start index with overlap
            startIndex = text.index(chunkEnd, offsetBy: -overlap, limitedBy: text.endIndex) ?? chunkEnd
            if startIndex >= chunkEnd {
                break
            }
        }

        return chunks
    }

    /// Generate safe filename from string
    static func safeFilename(from string: String, maxLength: Int = 50) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let safe = string.components(separatedBy: allowed.inverted).joined(separator: "_")
        let trimmed = String(safe.prefix(maxLength))
        return trimmed.isEmpty ? "untitled" : trimmed
    }

    // MARK: - HTML/RTF/Binary Cleaning

    /// Convert HTML to plain text
    private static func convertHTMLToText(_ text: String) -> String {
        // Check if text contains HTML
        guard text.contains("<") && text.contains(">") else {
            return text
        }

        var result = text

        // Remove script and style tags with their content
        result = result.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)

        // Convert common HTML entities
        let entities: [String: String] = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&mdash;": "—",
            "&ndash;": "–",
            "&hellip;": "...",
            "<br>": "\n",
            "<br/>": "\n",
            "<br />": "\n",
            "</p>": "\n\n",
            "</div>": "\n",
            "</li>": "\n"
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        // Remove all remaining HTML tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode numeric HTML entities (&#123;)
        result = result.replacingOccurrences(of: "&#(\\d+);", with: "", options: .regularExpression)

        return result
    }

    /// Remove RTF formatting
    private static func removeRTF(_ text: String) -> String {
        // Check if text is RTF
        guard text.hasPrefix("{\\rtf") else {
            return text
        }

        var result = text

        // Remove RTF control words and groups
        // Remove font table
        result = result.replacingOccurrences(of: "\\{\\\\fonttbl[^}]*\\}", with: "", options: .regularExpression)

        // Remove color table
        result = result.replacingOccurrences(of: "\\{\\\\colortbl[^}]*\\}", with: "", options: .regularExpression)

        // Remove stylesheet
        result = result.replacingOccurrences(of: "\\{\\\\stylesheet[^}]*\\}", with: "", options: .regularExpression)

        // Remove RTF control words (e.g., \par, \b, \i, \fs24)
        result = result.replacingOccurrences(of: "\\\\[a-z]+(-?\\d+)?[ ]?", with: "", options: .regularExpression)

        // Remove RTF special characters
        result = result.replacingOccurrences(of: "\\\\['\\{\\}\\\\]", with: "", options: .regularExpression)

        // Remove curly braces
        result = result.replacingOccurrences(of: "[{}]", with: "", options: .regularExpression)

        // Remove any remaining backslash sequences
        result = result.replacingOccurrences(of: "\\\\[^\\s]+", with: "", options: .regularExpression)

        return result
    }

    /// Remove binary content and base64 encoded data
    private static func removeBinaryContent(_ text: String) -> String {
        var result = text

        // Remove MIME base64 encoded content
        result = result.replacingOccurrences(of: "Content-Transfer-Encoding: base64[\\s\\S]*?(?=\\n\\n|\\Z)", with: "[Binary content removed]", options: .regularExpression)

        // Remove long base64-looking strings (40+ characters of base64)
        result = result.replacingOccurrences(of: "[A-Za-z0-9+/]{40,}={0,2}", with: "[Binary data removed]", options: .regularExpression)

        // Remove attachment markers
        result = result.replacingOccurrences(of: "Content-Type: application/[^\\n]*\\n[\\s\\S]*?(?=\\n\\n|Content-Type:|\\Z)", with: "[Attachment removed]\n", options: .regularExpression)

        // Remove image data
        result = result.replacingOccurrences(of: "Content-Type: image/[^\\n]*\\n[\\s\\S]*?(?=\\n\\n|Content-Type:|\\Z)", with: "[Image removed]\n", options: .regularExpression)

        // Remove other binary content types
        result = result.replacingOccurrences(of: "Content-Type: (audio|video|application)/[^\\n]*\\n[\\s\\S]*?(?=\\n\\n|Content-Type:|\\Z)", with: "[Binary attachment removed]\n", options: .regularExpression)

        return result
    }

    /// Remove non-printable characters
    private static func removeNonPrintableCharacters(_ text: String) -> String {
        // Allow: letters, numbers, punctuation, spaces, newlines, tabs
        let allowed = CharacterSet.alphanumerics
            .union(.punctuationCharacters)
            .union(.whitespaces)
            .union(.newlines)
            .union(CharacterSet(charactersIn: "\t\n\r"))

        var result = ""
        for char in text.unicodeScalars {
            if allowed.contains(char) || char.value > 127 { // Keep unicode characters
                result.append(String(char))
            }
        }

        return result
    }
}

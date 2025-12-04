//
//  MarkdownExporter.swift
//  MBox Explorer
//
//  Markdown export functionality
//

import Foundation

class MarkdownExporter {
    static func exportToMarkdown(emails: [Email], to url: URL, includeTableOfContents: Bool = true) throws {
        var markdown = "# Email Archive Export\n\n"
        markdown += "**Export Date:** \(Date().formatted())\n\n"
        markdown += "**Total Emails:** \(emails.count)\n\n"

        if includeTableOfContents {
            markdown += "## Table of Contents\n\n"
            for (index, email) in emails.enumerated() {
                let anchor = email.subject.lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                    .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
                markdown += "\(index + 1). [\(email.subject)](#\(anchor))\n"
            }
            markdown += "\n---\n\n"
        }

        for email in emails {
            markdown += "## \(email.subject)\n\n"
            markdown += "**From:** \(email.from)\n\n"
            if let to = email.to {
                markdown += "**To:** \(to)\n\n"
            }
            markdown += "**Date:** \(email.displayDate)\n\n"

            if email.hasAttachments {
                markdown += "**Attachments:** \(email.attachmentCount)\n"
                if let attachments = email.attachments {
                    for attachment in attachments {
                        markdown += "- 📎 `\(attachment.filename)` (\(attachment.contentType)"
                        if attachment.size != nil {
                            markdown += ", \(attachment.displaySize)"
                        }
                        markdown += ")\n"
                    }
                }
                markdown += "\n"
            }

            markdown += "### Message\n\n"
            markdown += "```\n\(email.cleanBody)\n```\n\n"

            if let messageId = email.messageId {
                markdown += "<details>\n<summary>Message ID</summary>\n\n"
                markdown += "`\(messageId)`\n\n"
                markdown += "</details>\n\n"
            }

            markdown += "---\n\n"
        }

        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    static func exportThreadToMarkdown(thread: EmailThread, to url: URL) throws {
        var markdown = "# Email Thread: \(thread.subject)\n\n"
        markdown += "**Participants:** \(thread.participants.joined(separator: ", "))\n\n"
        markdown += "**Messages:** \(thread.count)\n\n"
        markdown += "**Date Range:** \(thread.dateRange)\n\n"
        markdown += "---\n\n"

        for (index, email) in thread.emails.enumerated() {
            markdown += "## Message \(index + 1)\n\n"
            markdown += "**From:** \(email.from)\n\n"
            markdown += "**Date:** \(email.displayDate)\n\n"
            markdown += "```\n\(email.cleanBody)\n```\n\n"
            markdown += "---\n\n"
        }

        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }
}

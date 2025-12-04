//
//  CSVExporter.swift
//  MBox Explorer
//
//  CSV export functionality
//

import Foundation

class CSVExporter {
    static func exportToCSV(emails: [Email], to url: URL) throws {
        var csvContent = "From,To,Subject,Date,Body Length,Has Attachments,Attachment Count,Message ID\n"

        for email in emails {
            let from = escapeCSV(email.from)
            let to = escapeCSV(email.to ?? "")
            let subject = escapeCSV(email.subject)
            let date = escapeCSV(email.date)
            let bodyLength = "\(email.body.count)"
            let hasAttachments = email.hasAttachments ? "Yes" : "No"
            let attachmentCount = "\(email.attachmentCount)"
            let messageId = escapeCSV(email.messageId ?? "")

            csvContent += "\(from),\(to),\(subject),\(date),\(bodyLength),\(hasAttachments),\(attachmentCount),\(messageId)\n"
        }

        try csvContent.write(to: url, atomically: true, encoding: .utf8)
    }

    static func exportDetailedCSV(emails: [Email], to url: URL) throws {
        var csvContent = "From,To,Subject,Date,Body,Message ID,In Reply To,Has Attachments,Attachments\n"

        for email in emails {
            let from = escapeCSV(email.from)
            let to = escapeCSV(email.to ?? "")
            let subject = escapeCSV(email.subject)
            let date = escapeCSV(email.date)
            let body = escapeCSV(email.cleanBody.prefix(500).description)
            let messageId = escapeCSV(email.messageId ?? "")
            let inReplyTo = escapeCSV(email.inReplyTo ?? "")
            let hasAttachments = email.hasAttachments ? "Yes" : "No"
            let attachments = email.attachments?.map { $0.filename }.joined(separator: "; ") ?? ""

            csvContent += "\(from),\(to),\(subject),\(date),\(body),\(messageId),\(inReplyTo),\(hasAttachments),\(escapeCSV(attachments))\n"
        }

        try csvContent.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func escapeCSV(_ text: String) -> String {
        let needsEscape = text.contains(",") || text.contains("\"") || text.contains("\n")
        if needsEscape {
            let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return text
    }
}

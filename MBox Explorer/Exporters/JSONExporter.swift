//
//  JSONExporter.swift
//  MBox Explorer
//
//  JSON export functionality
//

import Foundation

class JSONExporter {
    struct EmailJSON: Codable {
        let id: String
        let from: String
        let to: String?
        let subject: String
        let date: String
        let body: String
        let cleanBody: String
        let messageId: String?
        let inReplyTo: String?
        let references: [String]?
        let attachments: [AttachmentJSON]?
        let hasAttachments: Bool
        let attachmentCount: Int
    }

    struct AttachmentJSON: Codable {
        let filename: String
        let contentType: String
        let size: Int?
    }

    struct ExportJSON: Codable {
        let exportDate: String
        let totalEmails: Int
        let emails: [EmailJSON]
    }

    static func exportToJSON(emails: [Email], to url: URL, prettyPrinted: Bool = true) throws {
        let emailsJSON = emails.map { email in
            EmailJSON(
                id: email.id.uuidString,
                from: email.from,
                to: email.to,
                subject: email.subject,
                date: email.date,
                body: email.body,
                cleanBody: email.cleanBody,
                messageId: email.messageId,
                inReplyTo: email.inReplyTo,
                references: email.references,
                attachments: email.attachments?.map { AttachmentJSON(filename: $0.filename, contentType: $0.contentType, size: $0.size) },
                hasAttachments: email.hasAttachments,
                attachmentCount: email.attachmentCount
            )
        }

        let exportData = ExportJSON(
            exportDate: ISO8601DateFormatter().string(from: Date()),
            totalEmails: emails.count,
            emails: emailsJSON
        )

        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(exportData)
        try data.write(to: url)
    }
}

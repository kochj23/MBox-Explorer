//
//  Email.swift
//  MBox Explorer
//
//  Email data model for RAG-optimized email exploration
//

import Foundation

/// Represents a single email message from an MBOX file
struct Email: Identifiable, Hashable, Codable {
    let id: UUID
    let from: String
    let to: String?
    let subject: String
    let date: String
    let dateObject: Date?
    let body: String
    let messageId: String?
    let inReplyTo: String?
    let references: [String]?
    let attachments: [AttachmentInfo]?

    /// For RAG: Clean body text without quotes, signatures
    var cleanBody: String {
        TextProcessor.cleanForRAG(body)
    }

    /// For RAG: Metadata dictionary
    var metadata: [String: Any] {
        var meta: [String: Any] = [
            "from": from,
            "subject": subject,
            "date": date,
            "message_id": messageId ?? "",
            "body_length": body.count
        ]

        if let to = to {
            meta["to"] = to
        }

        if let inReplyTo = inReplyTo {
            meta["in_reply_to"] = inReplyTo
        }

        if let references = references {
            meta["references"] = references
        }

        if let attachments = attachments {
            meta["attachments"] = attachments.map { ["filename": $0.filename, "type": $0.contentType, "size": $0.size as Any] }
            meta["attachment_count"] = attachments.count
        }

        return meta
    }

    var hasAttachments: Bool {
        return attachments?.isEmpty == false
    }

    var attachmentCount: Int {
        return attachments?.count ?? 0
    }

    init(id: UUID = UUID(),
         from: String,
         to: String? = nil,
         subject: String,
         date: String,
         dateObject: Date? = nil,
         body: String,
         messageId: String? = nil,
         inReplyTo: String? = nil,
         references: [String]? = nil,
         attachments: [AttachmentInfo]? = nil) {
        self.id = id
        self.from = from
        self.to = to
        self.subject = subject
        self.date = date
        self.dateObject = dateObject
        self.body = body
        self.messageId = messageId
        self.inReplyTo = inReplyTo
        self.references = references
        self.attachments = attachments
    }

    /// For display in UI
    var displayDate: String {
        if let dateObj = dateObject {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: dateObj)
        }
        return date
    }

    /// For RAG filename generation
    var safeFilename: String {
        let timestamp = dateObject?.timeIntervalSince1970 ?? 0
        let fromSafe = from.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "_", options: .regularExpression)
        let subjectSafe = subject.prefix(30).replacingOccurrences(of: "[^a-zA-Z0-9]", with: "_", options: .regularExpression)
        return "\(Int(timestamp))_\(fromSafe)_\(subjectSafe).txt"
    }
}

/// Email thread grouping
struct EmailThread: Identifiable, Hashable {
    let id: UUID
    let subject: String
    let emails: [Email]

    var count: Int { emails.count }

    var dateRange: String {
        guard let first = emails.first?.dateObject,
              let last = emails.last?.dateObject else {
            return "Unknown date range"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short

        if Calendar.current.isDate(first, inSameDayAs: last) {
            return formatter.string(from: first)
        }

        return "\(formatter.string(from: first)) - \(formatter.string(from: last))"
    }

    var participants: [String] {
        Array(Set(emails.map { $0.from })).sorted()
    }

    init(id: UUID = UUID(), subject: String, emails: [Email]) {
        self.id = id
        self.subject = subject
        self.emails = emails.sorted { ($0.dateObject ?? Date.distantPast) < ($1.dateObject ?? Date.distantPast) }
    }
}

/// Attachment information extracted from email
struct AttachmentInfo: Hashable, Codable {
    let filename: String
    let contentType: String
    let size: Int?

    var displaySize: String {
        guard let size = size else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var icon: String {
        if contentType.hasPrefix("image/") { return "photo" }
        if contentType.hasPrefix("video/") { return "film" }
        if contentType.hasPrefix("audio/") { return "music.note" }
        if contentType.contains("pdf") { return "doc.text" }
        if contentType.contains("zip") || contentType.contains("compressed") { return "archivebox" }
        if contentType.contains("text") { return "doc.plaintext" }
        return "paperclip"
    }
}

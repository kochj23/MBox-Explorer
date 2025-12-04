//
//  AttachmentManager.swift
//  MBox Explorer
//
//  Manages attachment extraction and filtering
//

import Foundation

class AttachmentManager {
    struct ExtendedAttachmentInfo: Identifiable, Hashable {
        let id: UUID
        let attachment: AttachmentInfo
        let email: Email
        let emailSubject: String
        let emailFrom: String
        let emailDate: Date?

        init(attachment: AttachmentInfo, email: Email, emailSubject: String, emailFrom: String, emailDate: Date?) {
            self.id = UUID()
            self.attachment = attachment
            self.email = email
            self.emailSubject = emailSubject
            self.emailFrom = emailFrom
            self.emailDate = emailDate
        }

        var filename: String { attachment.filename }
        var contentType: String { attachment.contentType }
        var size: Int? { attachment.size }
        var displaySize: String { attachment.displaySize }

        static func == (lhs: ExtendedAttachmentInfo, rhs: ExtendedAttachmentInfo) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        var fileExtension: String {
            (filename as NSString).pathExtension.lowercased()
        }

        var categoryIcon: String {
            switch fileExtension {
            case "pdf": return "doc.fill"
            case "jpg", "jpeg", "png", "gif", "heic", "bmp", "tiff": return "photo.fill"
            case "doc", "docx", "txt", "rtf": return "doc.text.fill"
            case "xls", "xlsx", "csv": return "tablecells.fill"
            case "ppt", "pptx": return "presentation.fill"
            case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
            case "mp3", "wav", "m4a", "aac": return "music.note"
            case "mp4", "mov", "avi", "mkv": return "video.fill"
            default: return "doc"
            }
        }

        var category: AttachmentCategory {
            switch fileExtension {
            case "pdf": return .pdf
            case "jpg", "jpeg", "png", "gif", "heic", "bmp", "tiff": return .image
            case "doc", "docx", "txt", "rtf": return .document
            case "xls", "xlsx", "csv": return .spreadsheet
            case "ppt", "pptx": return .presentation
            case "zip", "rar", "7z", "tar", "gz": return .archive
            case "mp3", "wav", "m4a", "aac": return .audio
            case "mp4", "mov", "avi", "mkv": return .video
            default: return .other
            }
        }
    }

    enum AttachmentCategory: String, CaseIterable {
        case all = "All"
        case pdf = "PDFs"
        case image = "Images"
        case document = "Documents"
        case spreadsheet = "Spreadsheets"
        case presentation = "Presentations"
        case archive = "Archives"
        case audio = "Audio"
        case video = "Video"
        case other = "Other"
    }

    enum SortField {
        case filename
        case size
        case date
        case type
    }

    enum SortOrder {
        case ascending
        case descending
    }

    static func extractAllAttachments(from emails: [Email]) -> [ExtendedAttachmentInfo] {
        var result: [ExtendedAttachmentInfo] = []

        for email in emails {
            if let attachments = email.attachments {
                for attachment in attachments {
                    let info = ExtendedAttachmentInfo(
                        attachment: attachment,
                        email: email,
                        emailSubject: email.subject,
                        emailFrom: email.from,
                        emailDate: email.dateObject
                    )
                    result.append(info)
                }
            }
        }

        return result
    }

    static func filter(_ attachments: [ExtendedAttachmentInfo],
                      by category: AttachmentCategory,
                      searchText: String) -> [ExtendedAttachmentInfo] {
        var filtered = attachments

        // Category filter
        if category != .all {
            filtered = filtered.filter { $0.category == category }
        }

        // Search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { info in
                info.filename.localizedCaseInsensitiveContains(searchText) ||
                info.emailSubject.localizedCaseInsensitiveContains(searchText) ||
                info.emailFrom.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    static func sort(_ attachments: [ExtendedAttachmentInfo],
                    by field: SortField,
                    order: SortOrder) -> [ExtendedAttachmentInfo] {
        let sorted: [ExtendedAttachmentInfo]

        switch field {
        case .filename:
            sorted = attachments.sorted { order == .ascending ? $0.filename < $1.filename : $0.filename > $1.filename }
        case .size:
            sorted = attachments.sorted {
                let size1 = $0.size ?? 0
                let size2 = $1.size ?? 0
                return order == .ascending ? size1 < size2 : size1 > size2
            }
        case .date:
            sorted = attachments.sorted {
                let date1 = $0.emailDate ?? .distantPast
                let date2 = $1.emailDate ?? .distantPast
                return order == .ascending ? date1 < date2 : date1 > date2
            }
        case .type:
            sorted = attachments.sorted {
                order == .ascending ? $0.fileExtension < $1.fileExtension : $0.fileExtension > $1.fileExtension
            }
        }

        return sorted
    }

    static func exportAttachments(_ attachments: [ExtendedAttachmentInfo], to directory: URL) throws {
        // Create a manifest file listing all attachments
        var manifest = "Attachment Export Manifest\n"
        manifest += "Exported: \(Date())\n"
        manifest += "Total Attachments: \(attachments.count)\n\n"

        for (index, info) in attachments.enumerated() {
            manifest += "[\(index + 1)] \(info.filename)\n"
            manifest += "    Type: \(info.contentType)\n"
            manifest += "    Size: \(info.displaySize)\n"
            manifest += "    From Email: \(info.emailSubject)\n"
            manifest += "    Sender: \(info.emailFrom)\n"
            if let date = info.emailDate {
                manifest += "    Date: \(date.formatted())\n"
            }
            manifest += "\n"
        }

        let manifestURL = directory.appendingPathComponent("attachments_manifest.txt")
        try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
    }

    static func getStatistics(from attachments: [ExtendedAttachmentInfo]) -> AttachmentStatistics {
        let totalCount = attachments.count
        let totalSize = attachments.compactMap { $0.size }.reduce(0, +)

        let categoryCounts = Dictionary(grouping: attachments, by: { $0.category })
            .mapValues { $0.count }

        let topFileTypes = Dictionary(grouping: attachments, by: { $0.fileExtension })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ($0.key, $0.value) }

        return AttachmentStatistics(
            totalCount: totalCount,
            totalSize: totalSize,
            categoryCounts: categoryCounts,
            topFileTypes: topFileTypes
        )
    }

    struct AttachmentStatistics {
        let totalCount: Int
        let totalSize: Int
        let categoryCounts: [AttachmentCategory: Int]
        let topFileTypes: [(String, Int)]

        var totalSizeFormatted: String {
            ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
        }
    }
}

//
//  MailboxMerger.swift
//  MBox Explorer
//
//  Merge multiple mailboxes with deduplication
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation

/// Merges multiple mailboxes with deduplication
class MailboxMerger: ObservableObject {
    static let shared = MailboxMerger()

    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var currentStep = ""

    // MARK: - Merge

    func mergeMailboxes(_ mailboxes: [[Email]], options: MergeOptions = MergeOptions()) async -> MergeResult {
        await MainActor.run {
            isProcessing = true
            progress = 0
            currentStep = "Combining emails..."
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        // Step 1: Combine all emails
        var allEmails: [Email] = []
        var sourceInfo: [UUID: String] = [:] // emailId -> source name

        for (index, mailbox) in mailboxes.enumerated() {
            let sourceName = "Mailbox \(index + 1)"
            for email in mailbox {
                allEmails.append(email)
                sourceInfo[email.id] = sourceName
            }
        }

        let totalBefore = allEmails.count

        await MainActor.run {
            progress = 0.2
            currentStep = "Identifying duplicates..."
        }

        // Step 2: Identify duplicates
        var duplicateGroups: [[Email]] = []

        if options.removeDuplicates {
            duplicateGroups = identifyDuplicates(allEmails, threshold: options.duplicateThreshold)

            await MainActor.run {
                progress = 0.5
                currentStep = "Removing duplicates..."
            }

            // Remove duplicates, keeping the best version
            var idsToRemove = Set<UUID>()
            for group in duplicateGroups {
                let sorted = sortByQuality(group)
                // Keep the first (best), remove the rest
                for email in sorted.dropFirst() {
                    idsToRemove.insert(email.id)
                }
            }

            allEmails = allEmails.filter { !idsToRemove.contains($0.id) }
        }

        await MainActor.run {
            progress = 0.7
            currentStep = "Sorting results..."
        }

        // Step 3: Sort
        switch options.sortOrder {
        case .dateAscending:
            allEmails.sort { ($0.dateObject ?? .distantPast) < ($1.dateObject ?? .distantPast) }
        case .dateDescending:
            allEmails.sort { ($0.dateObject ?? .distantPast) > ($1.dateObject ?? .distantPast) }
        case .sender:
            allEmails.sort { $0.from.lowercased() < $1.from.lowercased() }
        case .subject:
            allEmails.sort { $0.subject.lowercased() < $1.subject.lowercased() }
        case .none:
            break
        }

        await MainActor.run {
            progress = 1.0
            currentStep = "Complete"
        }

        return MergeResult(
            mergedEmails: allEmails,
            totalBefore: totalBefore,
            totalAfter: allEmails.count,
            duplicatesRemoved: totalBefore - allEmails.count,
            duplicateGroups: duplicateGroups,
            sourceInfo: sourceInfo
        )
    }

    // MARK: - Incremental Import

    func incrementalImport(existing: [Email], new: [Email], options: MergeOptions = MergeOptions()) async -> IncrementalResult {
        await MainActor.run {
            isProcessing = true
            progress = 0
            currentStep = "Finding new emails..."
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        // Build a set of existing email signatures
        let existingSignatures = Set(existing.map { emailSignature($0) })

        // Find truly new emails
        var newEmails: [Email] = []
        var duplicates: [Email] = []

        for (index, email) in new.enumerated() {
            let signature = emailSignature(email)

            if existingSignatures.contains(signature) {
                duplicates.append(email)
            } else {
                newEmails.append(email)
            }

            await MainActor.run {
                progress = Double(index + 1) / Double(new.count)
            }
        }

        // Combine
        var combined = existing + newEmails

        // Sort if requested
        if options.sortOrder != .none {
            combined.sort { ($0.dateObject ?? .distantPast) < ($1.dateObject ?? .distantPast) }
        }

        return IncrementalResult(
            combinedEmails: combined,
            newEmailsAdded: newEmails.count,
            duplicatesSkipped: duplicates.count,
            newEmails: newEmails,
            skippedEmails: duplicates
        )
    }

    // MARK: - Duplicate Detection

    private func identifyDuplicates(_ emails: [Email], threshold: Double) -> [[Email]] {
        var groups: [[Email]] = []
        var processed = Set<UUID>()

        for email in emails {
            guard !processed.contains(email.id) else { continue }

            var group: [Email] = [email]
            processed.insert(email.id)

            for candidate in emails where !processed.contains(candidate.id) {
                let similarity = calculateSimilarity(email, candidate)
                if similarity >= threshold {
                    group.append(candidate)
                    processed.insert(candidate.id)
                }
            }

            if group.count > 1 {
                groups.append(group)
            }
        }

        return groups
    }

    private func calculateSimilarity(_ email1: Email, _ email2: Email) -> Double {
        // Quick check - same Message-ID
        if let id1 = email1.messageId, let id2 = email2.messageId, id1 == id2 {
            return 1.0
        }

        // Check subject similarity
        let subjectSim = stringSimilarity(email1.subject, email2.subject)

        // Check sender
        let senderSim = email1.from.lowercased() == email2.from.lowercased() ? 1.0 : 0.0

        // Check date (within 1 minute = likely duplicate)
        var dateSim = 0.0
        if let date1 = email1.dateObject, let date2 = email2.dateObject {
            let diff = abs(date1.timeIntervalSince(date2))
            if diff < 60 {
                dateSim = 1.0
            } else if diff < 3600 {
                dateSim = 0.5
            }
        }

        // Check body similarity (sample)
        let bodySim = stringSimilarity(
            String(email1.body.prefix(500)),
            String(email2.body.prefix(500))
        )

        // Weighted combination
        return (subjectSim * 0.3) + (senderSim * 0.2) + (dateSim * 0.2) + (bodySim * 0.3)
    }

    private func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        let str1 = s1.lowercased()
        let str2 = s2.lowercased()

        if str1 == str2 { return 1.0 }
        if str1.isEmpty || str2.isEmpty { return 0.0 }

        let words1 = Set(str1.components(separatedBy: .whitespaces))
        let words2 = Set(str2.components(separatedBy: .whitespaces))

        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count

        return union > 0 ? Double(intersection) / Double(union) : 0
    }

    private func emailSignature(_ email: Email) -> String {
        // Create a signature for quick duplicate detection
        if let messageId = email.messageId {
            return messageId
        }

        let components = [
            email.from.lowercased(),
            email.subject.lowercased().trimmingCharacters(in: .whitespaces),
            email.date,
            String(email.body.prefix(100)).lowercased()
        ]

        return components.joined(separator: "|")
    }

    private func sortByQuality(_ emails: [Email]) -> [Email] {
        // Sort emails by "quality" - prefer ones with more complete data
        return emails.sorted { email1, email2 in
            var score1 = 0
            var score2 = 0

            // Has message ID
            if email1.messageId != nil { score1 += 10 }
            if email2.messageId != nil { score2 += 10 }

            // Has attachments
            if email1.attachments?.isEmpty == false { score1 += 5 }
            if email2.attachments?.isEmpty == false { score2 += 5 }

            // Body length
            score1 += min(email1.body.count / 100, 20)
            score2 += min(email2.body.count / 100, 20)

            // Has references (indicates threading info)
            if email1.references?.isEmpty == false { score1 += 5 }
            if email2.references?.isEmpty == false { score2 += 5 }

            return score1 > score2
        }
    }

    // MARK: - Export Merged

    func exportMerged(_ emails: [Email], to url: URL, format: ExportMergeFormat) throws {
        switch format {
        case .mbox:
            try exportToMBOX(emails, to: url)
        case .eml:
            try exportToEMLFolder(emails, to: url)
        }
    }

    private func exportToMBOX(_ emails: [Email], to url: URL) throws {
        var mboxContent = ""

        for email in emails {
            // MBOX format: each email starts with "From " line
            let fromLine = "From \(email.from) \(email.date)\n"
            mboxContent += fromLine

            // Construct headers from available properties
            mboxContent += "From: \(email.from)\n"
            if let to = email.to { mboxContent += "To: \(to)\n" }
            mboxContent += "Subject: \(email.subject)\n"
            mboxContent += "Date: \(email.date)\n"
            if let messageId = email.messageId { mboxContent += "Message-ID: \(messageId)\n" }
            if let inReplyTo = email.inReplyTo { mboxContent += "In-Reply-To: \(inReplyTo)\n" }

            mboxContent += "\n"
            mboxContent += email.body
            mboxContent += "\n\n"
        }

        try mboxContent.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportToEMLFolder(_ emails: [Email], to folderURL: URL) throws {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        for (index, email) in emails.enumerated() {
            let filename = "\(index + 1)_\(sanitizeFilename(email.subject)).eml"
            let fileURL = folderURL.appendingPathComponent(filename)

            var emlContent = ""

            // Construct headers from available properties
            emlContent += "From: \(email.from)\r\n"
            if let to = email.to { emlContent += "To: \(to)\r\n" }
            emlContent += "Subject: \(email.subject)\r\n"
            emlContent += "Date: \(email.date)\r\n"
            if let messageId = email.messageId { emlContent += "Message-ID: \(messageId)\r\n" }
            if let inReplyTo = email.inReplyTo { emlContent += "In-Reply-To: \(inReplyTo)\r\n" }

            emlContent += "\r\n"
            emlContent += email.body

            try emlContent.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private func sanitizeFilename(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name
            .components(separatedBy: illegal)
            .joined(separator: "_")
            .prefix(50)
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Models

struct MergeOptions {
    var removeDuplicates: Bool = true
    var duplicateThreshold: Double = 0.85
    var sortOrder: MergeSortOrder = .dateDescending
    var preserveSourceInfo: Bool = true
}

enum MergeSortOrder {
    case dateAscending
    case dateDescending
    case sender
    case subject
    case none
}

struct MergeResult {
    let mergedEmails: [Email]
    let totalBefore: Int
    let totalAfter: Int
    let duplicatesRemoved: Int
    let duplicateGroups: [[Email]]
    let sourceInfo: [UUID: String]
}

struct IncrementalResult {
    let combinedEmails: [Email]
    let newEmailsAdded: Int
    let duplicatesSkipped: Int
    let newEmails: [Email]
    let skippedEmails: [Email]
}

enum ExportMergeFormat {
    case mbox
    case eml
}

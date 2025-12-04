//
//  AnalyticsEngine.swift
//  MBox Explorer
//
//  Analytics engine for email statistics and insights
//

import Foundation

class AnalyticsEngine {

    // MARK: - Data Structures

    struct EmailAnalytics {
        let totalCount: Int
        let totalSize: Int
        let dateRange: DateRange
        let topSenders: [(email: String, count: Int)]
        let topRecipients: [(email: String, count: Int)]
        let emailsByHour: [Int: Int]
        let emailsByDay: [Int: Int]
        let emailsByMonth: [(month: String, count: Int)]
        let averageEmailSize: Int
        let largestEmail: Email?
        let attachmentStats: AttachmentStatistics
        let threadStats: ThreadStatistics
        let domainStats: DomainStatistics
    }

    struct DateRange {
        let start: Date?
        let end: Date?

        var description: String {
            guard let start = start, let end = end else {
                return "Unknown date range"
            }

            let formatter = DateFormatter()
            formatter.dateStyle = .medium

            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        }

        var days: Int {
            guard let start = start, let end = end else { return 0 }
            return Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        }
    }

    struct AttachmentStatistics {
        let totalAttachments: Int
        let totalAttachmentSize: Int
        let emailsWithAttachments: Int
        let mostCommonTypes: [(type: String, count: Int)]
        let averageAttachmentsPerEmail: Double
    }

    struct ThreadStatistics {
        let totalThreads: Int
        let longestThread: Int
        let averageThreadLength: Double
        let singleEmailCount: Int
    }

    struct DomainStatistics {
        let topDomains: [(domain: String, count: Int)]
        let uniqueDomains: Int
        let internalVsExternal: (internal: Int, external: Int)
    }

    struct TimeSeriesData {
        let dates: [Date]
        let counts: [Int]

        var maxCount: Int {
            counts.max() ?? 0
        }

        var total: Int {
            counts.reduce(0, +)
        }
    }

    // MARK: - Main Analytics

    static func analyze(_ emails: [Email]) -> EmailAnalytics {
        let totalCount = emails.count
        let totalSize = emails.reduce(0) { $0 + $1.body.count }

        let dateRange = calculateDateRange(emails)
        let topSenders = calculateTopSenders(emails, limit: 10)
        let topRecipients = calculateTopRecipients(emails, limit: 10)
        let emailsByHour = calculateEmailsByHour(emails)
        let emailsByDay = calculateEmailsByDay(emails)
        let emailsByMonth = calculateEmailsByMonth(emails)
        let averageEmailSize = totalCount > 0 ? totalSize / totalCount : 0
        let largestEmail = emails.max { ($0.body.count) < ($1.body.count) }
        let attachmentStats = calculateAttachmentStatistics(emails)
        let threadStats = calculateThreadStatistics(emails)
        let domainStats = calculateDomainStatistics(emails)

        return EmailAnalytics(
            totalCount: totalCount,
            totalSize: totalSize,
            dateRange: dateRange,
            topSenders: topSenders,
            topRecipients: topRecipients,
            emailsByHour: emailsByHour,
            emailsByDay: emailsByDay,
            emailsByMonth: emailsByMonth,
            averageEmailSize: averageEmailSize,
            largestEmail: largestEmail,
            attachmentStats: attachmentStats,
            threadStats: threadStats,
            domainStats: domainStats
        )
    }

    // MARK: - Date Range

    private static func calculateDateRange(_ emails: [Email]) -> DateRange {
        let dates = emails.compactMap { $0.dateObject }
        return DateRange(
            start: dates.min(),
            end: dates.max()
        )
    }

    // MARK: - Top Senders/Recipients

    private static func calculateTopSenders(_ emails: [Email], limit: Int) -> [(email: String, count: Int)] {
        let senderCounts = Dictionary(grouping: emails, by: { $0.from })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(limit)

        return senderCounts.map { ($0.key, $0.value) }
    }

    private static func calculateTopRecipients(_ emails: [Email], limit: Int) -> [(email: String, count: Int)] {
        let recipients = emails.compactMap { $0.to }
        let recipientCounts = Dictionary(grouping: recipients, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(limit)

        return recipientCounts.map { ($0.key, $0.value) }
    }

    // MARK: - Time-based Analytics

    private static func calculateEmailsByHour(_ emails: [Email]) -> [Int: Int] {
        var hourCounts: [Int: Int] = [:]

        for email in emails {
            guard let date = email.dateObject else { continue }
            let hour = Calendar.current.component(.hour, from: date)
            hourCounts[hour, default: 0] += 1
        }

        return hourCounts
    }

    private static func calculateEmailsByDay(_ emails: [Email]) -> [Int: Int] {
        var dayCounts: [Int: Int] = [:]

        for email in emails {
            guard let date = email.dateObject else { continue }
            let weekday = Calendar.current.component(.weekday, from: date)
            dayCounts[weekday, default: 0] += 1
        }

        return dayCounts
    }

    private static func calculateEmailsByMonth(_ emails: [Email]) -> [(month: String, count: Int)] {
        var monthCounts: [String: Int] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"

        for email in emails {
            guard let date = email.dateObject else { continue }
            let monthKey = formatter.string(from: date)
            monthCounts[monthKey, default: 0] += 1
        }

        return monthCounts.sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    // MARK: - Attachment Analytics

    private static func calculateAttachmentStatistics(_ emails: [Email]) -> AttachmentStatistics {
        let emailsWithAttachments = emails.filter { $0.hasAttachments }.count
        let allAttachments = emails.flatMap { $0.attachments ?? [] }
        let totalSize = allAttachments.compactMap { $0.size }.reduce(0, +)

        let typeCounts = Dictionary(grouping: allAttachments, by: { $0.contentType })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { ($0.key, $0.value) }

        let averageAttachments = emailsWithAttachments > 0
            ? Double(allAttachments.count) / Double(emailsWithAttachments)
            : 0.0

        return AttachmentStatistics(
            totalAttachments: allAttachments.count,
            totalAttachmentSize: totalSize,
            emailsWithAttachments: emailsWithAttachments,
            mostCommonTypes: typeCounts,
            averageAttachmentsPerEmail: averageAttachments
        )
    }

    // MARK: - Thread Analytics

    private static func calculateThreadStatistics(_ emails: [Email]) -> ThreadStatistics {
        // Group by subject (simplified threading)
        let threads = Dictionary(grouping: emails) { email -> String in
            // Remove common prefixes
            var subject = email.subject
            subject = subject.replacingOccurrences(of: "^(Re:|Fwd?:|AW:|WG:)\\s*", with: "", options: .regularExpression, range: nil)
            return subject.lowercased().trimmingCharacters(in: .whitespaces)
        }

        let threadLengths = threads.values.map { $0.count }
        let longestThread = threadLengths.max() ?? 0
        let averageLength = threadLengths.isEmpty ? 0.0 : Double(threadLengths.reduce(0, +)) / Double(threadLengths.count)
        let singleEmailCount = threadLengths.filter { $0 == 1 }.count

        return ThreadStatistics(
            totalThreads: threads.count,
            longestThread: longestThread,
            averageThreadLength: averageLength,
            singleEmailCount: singleEmailCount
        )
    }

    // MARK: - Domain Analytics

    private static func calculateDomainStatistics(_ emails: [Email]) -> DomainStatistics {
        var domainCounts: [String: Int] = [:]

        for email in emails {
            if let domain = extractDomain(from: email.from) {
                domainCounts[domain, default: 0] += 1
            }
        }

        let topDomains = domainCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ($0.key, $0.value) }

        // Assume most common domain is "internal"
        let internalDomain = topDomains.first?.0 ?? ""
        let internalCount = domainCounts[internalDomain] ?? 0
        let externalCount = emails.count - internalCount

        return DomainStatistics(
            topDomains: topDomains,
            uniqueDomains: domainCounts.count,
            internalVsExternal: (internal: internalCount, external: externalCount)
        )
    }

    private static func extractDomain(from email: String) -> String? {
        if let atIndex = email.firstIndex(of: "@") {
            let domain = email[email.index(after: atIndex)...]
            return String(domain).lowercased()
        }
        return nil
    }

    // MARK: - Time Series

    static func generateTimeSeries(_ emails: [Email], groupBy: TimeSeriesGrouping) -> TimeSeriesData {
        var dateCounts: [Date: Int] = [:]
        let calendar = Calendar.current

        for email in emails {
            guard let date = email.dateObject else { continue }

            let groupedDate: Date
            switch groupBy {
            case .hour:
                groupedDate = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
            case .day:
                groupedDate = calendar.startOfDay(for: date)
            case .week:
                let weekStart = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                groupedDate = calendar.date(from: weekStart) ?? date
            case .month:
                let monthStart = calendar.dateComponents([.year, .month], from: date)
                groupedDate = calendar.date(from: monthStart) ?? date
            }

            dateCounts[groupedDate, default: 0] += 1
        }

        let sortedData = dateCounts.sorted { $0.key < $1.key }
        return TimeSeriesData(
            dates: sortedData.map { $0.key },
            counts: sortedData.map { $0.value }
        )
    }

    enum TimeSeriesGrouping {
        case hour
        case day
        case week
        case month
    }

    // MARK: - Export Analytics

    static func exportAnalyticsReport(_ analytics: EmailAnalytics, to url: URL) throws {
        var report = "Email Analytics Report\n"
        report += "=====================\n\n"

        report += "Overview:\n"
        report += "  Total Emails: \(analytics.totalCount)\n"
        report += "  Date Range: \(analytics.dateRange.description)\n"
        report += "  Total Size: \(ByteCountFormatter.string(fromByteCount: Int64(analytics.totalSize), countStyle: .file))\n"
        report += "  Average Email Size: \(ByteCountFormatter.string(fromByteCount: Int64(analytics.averageEmailSize), countStyle: .file))\n\n"

        report += "Top 10 Senders:\n"
        for (index, sender) in analytics.topSenders.enumerated() {
            report += "  \(index + 1). \(sender.email): \(sender.count) emails\n"
        }
        report += "\n"

        report += "Email Activity by Hour:\n"
        for hour in 0...23 {
            let count = analytics.emailsByHour[hour] ?? 0
            let bar = String(repeating: "█", count: count / 10)
            report += "  \(String(format: "%02d", hour)):00 | \(bar) \(count)\n"
        }
        report += "\n"

        report += "Attachment Statistics:\n"
        report += "  Total Attachments: \(analytics.attachmentStats.totalAttachments)\n"
        report += "  Emails with Attachments: \(analytics.attachmentStats.emailsWithAttachments)\n"
        report += "  Total Attachment Size: \(ByteCountFormatter.string(fromByteCount: Int64(analytics.attachmentStats.totalAttachmentSize), countStyle: .file))\n"
        report += "  Average Attachments per Email: \(String(format: "%.2f", analytics.attachmentStats.averageAttachmentsPerEmail))\n\n"

        report += "Thread Statistics:\n"
        report += "  Total Threads: \(analytics.threadStats.totalThreads)\n"
        report += "  Longest Thread: \(analytics.threadStats.longestThread) emails\n"
        report += "  Average Thread Length: \(String(format: "%.2f", analytics.threadStats.averageThreadLength))\n"
        report += "  Single Email Threads: \(analytics.threadStats.singleEmailCount)\n\n"

        report += "Domain Statistics:\n"
        report += "  Unique Domains: \(analytics.domainStats.uniqueDomains)\n"
        report += "  Internal Emails: \(analytics.domainStats.internalVsExternal.internal)\n"
        report += "  External Emails: \(analytics.domainStats.internalVsExternal.external)\n\n"

        report += "Top 10 Domains:\n"
        for (index, domain) in analytics.domainStats.topDomains.enumerated() {
            report += "  \(index + 1). \(domain.domain): \(domain.count) emails\n"
        }

        try report.write(to: url, atomically: true, encoding: .utf8)
    }
}

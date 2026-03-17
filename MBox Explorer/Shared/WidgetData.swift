//
//  WidgetData.swift
//  MBox Explorer
//
//  Shared data models for widget display - used by both main app and widget extension
//
//  Author: Jordan Koch
//

import Foundation

/// Data structure for widget display
struct WidgetData: Codable {
    let totalEmails: Int
    let totalThreads: Int
    let dateRange: String
    let topSenders: [WidgetSenderInfo]
    let recentQueries: [QueryInfo]
    let lastUpdated: Date
    let loadedFileName: String?

    init(
        totalEmails: Int = 0,
        totalThreads: Int = 0,
        dateRange: String = "No data",
        topSenders: [WidgetSenderInfo] = [],
        recentQueries: [QueryInfo] = [],
        lastUpdated: Date = Date(),
        loadedFileName: String? = nil
    ) {
        self.totalEmails = totalEmails
        self.totalThreads = totalThreads
        self.dateRange = dateRange
        self.topSenders = topSenders
        self.recentQueries = recentQueries
        self.lastUpdated = lastUpdated
        self.loadedFileName = loadedFileName
    }

    /// Placeholder data for widget preview
    static var placeholder: WidgetData {
        WidgetData(
            totalEmails: 1234,
            totalThreads: 456,
            dateRange: "Jan 2024 - Dec 2024",
            topSenders: [
                WidgetSenderInfo(name: "John Doe", email: "john@example.com", count: 150),
                WidgetSenderInfo(name: "Jane Smith", email: "jane@example.com", count: 98),
                WidgetSenderInfo(name: "Support Team", email: "support@company.com", count: 75)
            ],
            recentQueries: [
                QueryInfo(query: "project updates", timestamp: Date().addingTimeInterval(-3600)),
                QueryInfo(query: "meeting notes", timestamp: Date().addingTimeInterval(-7200)),
                QueryInfo(query: "invoice", timestamp: Date().addingTimeInterval(-86400))
            ],
            lastUpdated: Date(),
            loadedFileName: "work_emails.mbox"
        )
    }

    /// Empty state for when no data is available
    static var empty: WidgetData {
        WidgetData()
    }

    var isEmpty: Bool {
        totalEmails == 0
    }

    var formattedEmailCount: String {
        if totalEmails >= 1_000_000 {
            return String(format: "%.1fM", Double(totalEmails) / 1_000_000)
        } else if totalEmails >= 1_000 {
            return String(format: "%.1fK", Double(totalEmails) / 1_000)
        }
        return "\(totalEmails)"
    }

    var lastUpdatedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUpdated, relativeTo: Date())
    }
}

/// Sender information for top senders display
struct WidgetSenderInfo: Codable, Identifiable, Hashable {
    let name: String
    let email: String
    let count: Int

    var id: String { email }

    var displayName: String {
        if name.isEmpty || name == email {
            // Extract name from email if no name provided
            return email.components(separatedBy: "@").first ?? email
        }
        return name
    }

    var initials: String {
        let parts = displayName.components(separatedBy: " ")
        if parts.count >= 2 {
            let first = parts[0].prefix(1)
            let last = parts[1].prefix(1)
            return "\(first)\(last)".uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }
}

/// Query information for recent searches display
struct QueryInfo: Codable, Identifiable, Hashable {
    let query: String
    let timestamp: Date

    var id: String { "\(query)_\(timestamp.timeIntervalSince1970)" }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

/// Widget configuration intent
enum WidgetDisplayMode: String, Codable, CaseIterable {
    case stats = "Statistics"
    case senders = "Top Senders"
    case queries = "Recent Queries"
    case combined = "Combined"
}

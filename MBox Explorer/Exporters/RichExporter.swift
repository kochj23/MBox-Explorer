//
//  RichExporter.swift
//  MBox Explorer
//
//  Rich export options: PDF, HTML, Reports
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation
import AppKit
import PDFKit

/// Rich export functionality for emails
class RichExporter: ObservableObject {
    static let shared = RichExporter()

    @Published var isExporting = false
    @Published var progress: Double = 0

    // MARK: - PDF Export

    func exportToPDF(_ emails: [Email], to url: URL, options: PDFExportOptions = PDFExportOptions()) throws {
        let pdfDocument = PDFDocument()

        for (index, email) in emails.enumerated() {
            let pageContent = createPDFPage(for: email, options: options)

            if let pdfPage = PDFPage(image: pageContent) {
                pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
            }

            progress = Double(index + 1) / Double(emails.count)
        }

        pdfDocument.write(to: url)
    }

    func exportThreadToPDF(_ emails: [Email], to url: URL, options: PDFExportOptions = PDFExportOptions()) throws {
        // Sort by date for thread order
        let sortedEmails = emails.sorted { ($0.dateObject ?? .distantPast) < ($1.dateObject ?? .distantPast) }

        let pdfDocument = PDFDocument()

        // Create thread overview page
        if let overviewImage = createThreadOverview(sortedEmails) {
            if let pdfPage = PDFPage(image: overviewImage) {
                pdfDocument.insert(pdfPage, at: 0)
            }
        }

        // Add individual emails
        for email in sortedEmails {
            let pageContent = createPDFPage(for: email, options: options)
            if let pdfPage = PDFPage(image: pageContent) {
                pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
            }
        }

        pdfDocument.write(to: url)
    }

    private func createPDFPage(for email: Email, options: PDFExportOptions) -> NSImage {
        let pageSize = NSSize(width: 612, height: 792) // Letter size
        let margin: CGFloat = 50

        let image = NSImage(size: pageSize)
        image.lockFocus()

        // White background
        NSColor.white.setFill()
        NSRect(origin: .zero, size: pageSize).fill()

        var yOffset = pageSize.height - margin

        // Header
        let headerFont = NSFont.boldSystemFont(ofSize: 14)
        let bodyFont = NSFont.systemFont(ofSize: 11)
        let metaFont = NSFont.systemFont(ofSize: 10)

        // Subject
        let subjectAttr: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: NSColor.black
        ]
        let subjectStr = NSAttributedString(string: email.subject, attributes: subjectAttr)
        subjectStr.draw(at: NSPoint(x: margin, y: yOffset - 20))
        yOffset -= 40

        // Metadata
        let metaAttr: [NSAttributedString.Key: Any] = [
            .font: metaFont,
            .foregroundColor: NSColor.darkGray
        ]

        let fromStr = NSAttributedString(string: "From: \(email.from)", attributes: metaAttr)
        fromStr.draw(at: NSPoint(x: margin, y: yOffset))
        yOffset -= 18

        let toStr = NSAttributedString(string: "To: \(email.to ?? "")", attributes: metaAttr)
        toStr.draw(at: NSPoint(x: margin, y: yOffset))
        yOffset -= 18

        let dateStr = NSAttributedString(string: "Date: \(email.date)", attributes: metaAttr)
        dateStr.draw(at: NSPoint(x: margin, y: yOffset))
        yOffset -= 30

        // Separator line
        NSColor.lightGray.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: margin, y: yOffset))
        path.line(to: NSPoint(x: pageSize.width - margin, y: yOffset))
        path.stroke()
        yOffset -= 20

        // Body
        let bodyAttr: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor.black
        ]

        let bodyRect = NSRect(
            x: margin,
            y: margin,
            width: pageSize.width - (margin * 2),
            height: yOffset - margin
        )

        let bodyText = options.stripHtml ? stripHTML(email.body) : email.body
        let bodyStr = NSAttributedString(string: bodyText, attributes: bodyAttr)
        bodyStr.draw(in: bodyRect)

        image.unlockFocus()
        return image
    }

    private func createThreadOverview(_ emails: [Email]) -> NSImage? {
        let pageSize = NSSize(width: 612, height: 792)
        let margin: CGFloat = 50

        let image = NSImage(size: pageSize)
        image.lockFocus()

        NSColor.white.setFill()
        NSRect(origin: .zero, size: pageSize).fill()

        var yOffset = pageSize.height - margin

        // Title
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.black
        ]
        let titleStr = NSAttributedString(string: "Email Thread Summary", attributes: titleAttr)
        titleStr.draw(at: NSPoint(x: margin, y: yOffset - 25))
        yOffset -= 50

        // Thread info
        let infoAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.darkGray
        ]

        let subject = emails.first?.subject ?? "Unknown"
        let participants = Set(emails.flatMap { [$0.from] + ([$0.to].compactMap { $0 }) }).joined(separator: ", ")
        let dateRange = formatDateRange(emails)

        NSAttributedString(string: "Subject: \(subject)", attributes: infoAttr)
            .draw(at: NSPoint(x: margin, y: yOffset))
        yOffset -= 18

        NSAttributedString(string: "Participants: \(participants.prefix(100))", attributes: infoAttr)
            .draw(at: NSPoint(x: margin, y: yOffset))
        yOffset -= 18

        NSAttributedString(string: "Messages: \(emails.count)", attributes: infoAttr)
            .draw(at: NSPoint(x: margin, y: yOffset))
        yOffset -= 18

        NSAttributedString(string: "Date Range: \(dateRange)", attributes: infoAttr)
            .draw(at: NSPoint(x: margin, y: yOffset))
        yOffset -= 40

        // Email list
        let listAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.black
        ]

        for (index, email) in emails.prefix(20).enumerated() {
            let line = "\(index + 1). \(email.from.prefix(30)) - \(email.date)"
            NSAttributedString(string: line, attributes: listAttr)
                .draw(at: NSPoint(x: margin, y: yOffset))
            yOffset -= 15
        }

        image.unlockFocus()
        return image
    }

    // MARK: - HTML Export

    func exportToHTML(_ emails: [Email], to url: URL, options: HTMLExportOptions = HTMLExportOptions()) throws {
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>\(options.title)</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    max-width: 900px;
                    margin: 0 auto;
                    padding: 20px;
                    background: \(options.darkMode ? "#1a1a1a" : "#ffffff");
                    color: \(options.darkMode ? "#ffffff" : "#000000");
                }
                .email {
                    border: 1px solid \(options.darkMode ? "#333" : "#ddd");
                    border-radius: 8px;
                    margin-bottom: 20px;
                    overflow: hidden;
                }
                .email-header {
                    background: \(options.darkMode ? "#2a2a2a" : "#f5f5f5");
                    padding: 15px;
                    border-bottom: 1px solid \(options.darkMode ? "#333" : "#ddd");
                }
                .email-subject {
                    font-size: 18px;
                    font-weight: bold;
                    margin-bottom: 10px;
                }
                .email-meta {
                    font-size: 12px;
                    color: \(options.darkMode ? "#aaa" : "#666");
                }
                .email-body {
                    padding: 15px;
                    white-space: pre-wrap;
                    font-size: 14px;
                    line-height: 1.5;
                }
                .email-attachments {
                    padding: 10px 15px;
                    background: \(options.darkMode ? "#2a2a2a" : "#f9f9f9");
                    border-top: 1px solid \(options.darkMode ? "#333" : "#ddd");
                }
                .toc {
                    background: \(options.darkMode ? "#2a2a2a" : "#f5f5f5");
                    padding: 20px;
                    border-radius: 8px;
                    margin-bottom: 30px;
                }
                .toc h2 {
                    margin-top: 0;
                }
                .toc-item {
                    padding: 5px 0;
                }
                .toc-item a {
                    color: \(options.darkMode ? "#6eb5ff" : "#0066cc");
                    text-decoration: none;
                }
            </style>
        </head>
        <body>
            <h1>\(options.title)</h1>
        """

        // Table of contents
        if options.includeTableOfContents {
            html += """
            <div class="toc">
                <h2>Table of Contents</h2>
            """
            for (index, email) in emails.enumerated() {
                html += """
                <div class="toc-item">
                    <a href="#email-\(index)">\(escapeHTML(email.subject))</a>
                    <span class="email-meta"> - \(escapeHTML(email.from))</span>
                </div>
                """
            }
            html += "</div>"
        }

        // Emails
        for (index, email) in emails.enumerated() {
            html += """
            <div class="email" id="email-\(index)">
                <div class="email-header">
                    <div class="email-subject">\(escapeHTML(email.subject))</div>
                    <div class="email-meta">
                        <strong>From:</strong> \(escapeHTML(email.from))<br>
                        <strong>To:</strong> \(escapeHTML(email.to ?? ""))<br>
                        <strong>Date:</strong> \(escapeHTML(email.date))
                    </div>
                </div>
                <div class="email-body">\(options.preserveHtml ? email.body : escapeHTML(stripHTML(email.body)))</div>
            """

            if let attachments = email.attachments, !attachments.isEmpty, options.listAttachments {
                html += """
                <div class="email-attachments">
                    <strong>Attachments:</strong>
                    \(attachments.map { escapeHTML($0.filename) }.joined(separator: ", "))
                </div>
                """
            }

            html += "</div>"

            progress = Double(index + 1) / Double(emails.count)
        }

        html += """
            <footer style="text-align: center; margin-top: 40px; color: #888;">
                Generated by MBox Explorer on \(formatDate(Date()))
            </footer>
        </body>
        </html>
        """

        try html.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Report Generation

    func generateReport(_ emails: [Email], type: ReportType, to url: URL) async throws {
        await MainActor.run {
            isExporting = true
            progress = 0
        }

        defer {
            Task { @MainActor in
                isExporting = false
            }
        }

        switch type {
        case .summary:
            try await generateSummaryReport(emails, to: url)
        case .statistics:
            try generateStatisticsReport(emails, to: url)
        case .timeline:
            try generateTimelineReport(emails, to: url)
        case .contacts:
            try generateContactsReport(emails, to: url)
        }
    }

    private func generateSummaryReport(_ emails: [Email], to url: URL) async throws {
        let summarizer = ThreadSummarizer.shared
        let summary = try await summarizer.generateExecutiveSummary(emails: emails)

        let report = """
        # Email Archive Summary Report

        **Generated:** \(formatDate(Date()))
        **Total Emails:** \(summary.totalEmails)
        **Date Range:** \(formatDate(summary.dateRange.start)) - \(formatDate(summary.dateRange.end))
        **Unique Correspondents:** \(summary.uniqueCorrespondents)

        ## Executive Summary

        \(summary.summary)

        ## Top Correspondents

        \(summary.topCorrespondents.map { "- \($0.0): \($0.1) emails" }.joined(separator: "\n"))

        ---
        *Generated by MBox Explorer*
        """

        try report.write(to: url, atomically: true, encoding: .utf8)
    }

    private func generateStatisticsReport(_ emails: [Email], to url: URL) throws {
        let bySender = Dictionary(grouping: emails, by: { $0.from })
        let byDate = Dictionary(grouping: emails) { email -> String in
            guard let date = email.dateObject else { return "Unknown" }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM"
            return formatter.string(from: date)
        }

        let report = """
        # Email Statistics Report

        **Generated:** \(formatDate(Date()))

        ## Overview

        - **Total Emails:** \(emails.count)
        - **Unique Senders:** \(bySender.count)
        - **With Attachments:** \(emails.filter { $0.attachments?.isEmpty == false }.count)

        ## Emails by Month

        \(byDate.sorted { $0.key < $1.key }.map { "- \($0.key): \($0.value.count)" }.joined(separator: "\n"))

        ## Top Senders

        \(bySender.sorted { $0.value.count > $1.value.count }.prefix(20).map { "- \($0.key): \($0.value.count)" }.joined(separator: "\n"))

        ---
        *Generated by MBox Explorer*
        """

        try report.write(to: url, atomically: true, encoding: .utf8)
    }

    private func generateTimelineReport(_ emails: [Email], to url: URL) throws {
        let sorted = emails.sorted { ($0.dateObject ?? .distantPast) < ($1.dateObject ?? .distantPast) }

        var report = "# Email Timeline Report\n\n"
        report += "**Generated:** \(formatDate(Date()))\n\n"

        var currentDate = ""
        for email in sorted {
            let dateStr = email.dateObject.map { formatDate($0) } ?? "Unknown"
            if dateStr != currentDate {
                currentDate = dateStr
                report += "\n## \(dateStr)\n\n"
            }

            report += "- **\(email.from)**: \(email.subject)\n"
        }

        try report.write(to: url, atomically: true, encoding: .utf8)
    }

    private func generateContactsReport(_ emails: [Email], to url: URL) throws {
        let bySender = Dictionary(grouping: emails, by: { $0.from })

        var report = "# Contacts Report\n\n"
        report += "**Generated:** \(formatDate(Date()))\n"
        report += "**Total Contacts:** \(bySender.count)\n\n"

        for (sender, senderEmails) in bySender.sorted(by: { $0.value.count > $1.value.count }) {
            let dates = senderEmails.compactMap { $0.dateObject }.sorted()

            report += "## \(sender)\n\n"
            report += "- **Email Count:** \(senderEmails.count)\n"
            report += "- **First Contact:** \(dates.first.map { formatDate($0) } ?? "Unknown")\n"
            report += "- **Last Contact:** \(dates.last.map { formatDate($0) } ?? "Unknown")\n\n"
        }

        try report.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private func stripHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDateRange(_ emails: [Email]) -> String {
        let dates = emails.compactMap { $0.dateObject }.sorted()
        guard let first = dates.first, let last = dates.last else { return "Unknown" }
        return "\(formatDate(first)) - \(formatDate(last))"
    }
}

// MARK: - Models

struct PDFExportOptions {
    var stripHtml = true
    var includeAttachments = false
    var pageSize: NSSize = NSSize(width: 612, height: 792)
}

struct HTMLExportOptions {
    var title = "Email Export"
    var darkMode = false
    var includeTableOfContents = true
    var preserveHtml = false
    var listAttachments = true
}

enum ReportType: String, CaseIterable {
    case summary = "Summary Report"
    case statistics = "Statistics Report"
    case timeline = "Timeline Report"
    case contacts = "Contacts Report"
}

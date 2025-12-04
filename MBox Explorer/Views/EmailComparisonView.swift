//
//  EmailComparisonView.swift
//  MBox Explorer
//
//  Side-by-side email comparison with diff highlighting
//

import SwiftUI

struct EmailComparisonView: View {
    let email1: Email
    let email2: Email
    @Binding var isPresented: Bool
    @State private var showHeaders = true
    @State private var showBody = true
    @State private var highlightDifferences = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Compare Emails")
                    .font(.title2)
                    .bold()

                Spacer()

                // Options
                HStack(spacing: 16) {
                    Toggle("Headers", isOn: $showHeaders)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    Toggle("Body", isOn: $showBody)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    Toggle("Highlight Differences", isOn: $highlightDifferences)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Comparison view
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Left email
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Subject
                            ComparisonSection(
                                title: "Subject",
                                content: email1.subject,
                                otherContent: email2.subject,
                                highlightDifferences: highlightDifferences,
                                color: .blue
                            )

                            if showHeaders {
                                // From
                                ComparisonSection(
                                    title: "From",
                                    content: email1.from,
                                    otherContent: email2.from,
                                    highlightDifferences: highlightDifferences,
                                    color: .blue
                                )

                                // To
                                if let to1 = email1.to {
                                    ComparisonSection(
                                        title: "To",
                                        content: to1,
                                        otherContent: email2.to ?? "",
                                        highlightDifferences: highlightDifferences,
                                        color: .blue
                                    )
                                }

                                // Date
                                ComparisonSection(
                                    title: "Date",
                                    content: email1.displayDate,
                                    otherContent: email2.displayDate,
                                    highlightDifferences: highlightDifferences,
                                    color: .blue
                                )

                                // Message ID
                                if let messageId = email1.messageId {
                                    ComparisonSection(
                                        title: "Message ID",
                                        content: messageId,
                                        otherContent: email2.messageId ?? "",
                                        highlightDifferences: highlightDifferences,
                                        color: .blue
                                    )
                                }
                            }

                            if showBody {
                                // Body
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Body")
                                        .font(.headline)
                                        .foregroundColor(.blue)

                                    Text(email1.body)
                                        .font(.body)
                                        .textSelection(.enabled)
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(getDifferenceColor(email1.body, email2.body))
                                        .cornerRadius(8)
                                }
                            }

                            // Attachments
                            if email1.hasAttachments || email2.hasAttachments {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Attachments")
                                        .font(.headline)
                                        .foregroundColor(.blue)

                                    if let attachments = email1.attachments {
                                        ForEach(attachments, id: \.filename) { attachment in
                                            HStack {
                                                Image(systemName: "paperclip")
                                                Text(attachment.filename)
                                                    .font(.caption)
                                            }
                                        }
                                    } else {
                                        Text("No attachments")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                    }
                    .frame(width: geometry.size.width / 2)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    // Right email
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Subject
                            ComparisonSection(
                                title: "Subject",
                                content: email2.subject,
                                otherContent: email1.subject,
                                highlightDifferences: highlightDifferences,
                                color: .orange
                            )

                            if showHeaders {
                                // From
                                ComparisonSection(
                                    title: "From",
                                    content: email2.from,
                                    otherContent: email1.from,
                                    highlightDifferences: highlightDifferences,
                                    color: .orange
                                )

                                // To
                                if let to2 = email2.to {
                                    ComparisonSection(
                                        title: "To",
                                        content: to2,
                                        otherContent: email1.to ?? "",
                                        highlightDifferences: highlightDifferences,
                                        color: .orange
                                    )
                                }

                                // Date
                                ComparisonSection(
                                    title: "Date",
                                    content: email2.displayDate,
                                    otherContent: email1.displayDate,
                                    highlightDifferences: highlightDifferences,
                                    color: .orange
                                )

                                // Message ID
                                if let messageId = email2.messageId {
                                    ComparisonSection(
                                        title: "Message ID",
                                        content: messageId,
                                        otherContent: email1.messageId ?? "",
                                        highlightDifferences: highlightDifferences,
                                        color: .orange
                                    )
                                }
                            }

                            if showBody {
                                // Body
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Body")
                                        .font(.headline)
                                        .foregroundColor(.orange)

                                    Text(email2.body)
                                        .font(.body)
                                        .textSelection(.enabled)
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(getDifferenceColor(email2.body, email1.body))
                                        .cornerRadius(8)
                                }
                            }

                            // Attachments
                            if email1.hasAttachments || email2.hasAttachments {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Attachments")
                                        .font(.headline)
                                        .foregroundColor(.orange)

                                    if let attachments = email2.attachments {
                                        ForEach(attachments, id: \.filename) { attachment in
                                            HStack {
                                                Image(systemName: "paperclip")
                                                Text(attachment.filename)
                                                    .font(.caption)
                                            }
                                        }
                                    } else {
                                        Text("No attachments")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                    }
                    .frame(width: geometry.size.width / 2)
                    .background(Color(NSColor.windowBackgroundColor))
                }
            }

            Divider()

            // Statistics
            HStack(spacing: 20) {
                Label("Similarity: \(calculateSimilarity())%", systemImage: "chart.bar")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()
                    .frame(height: 16)

                Label("\(countDifferences()) differences", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    private func getDifferenceColor(_ text1: String, _ text2: String) -> Color {
        if !highlightDifferences {
            return Color(NSColor.controlBackgroundColor)
        }

        if text1 == text2 {
            return Color(NSColor.controlBackgroundColor)
        } else {
            return Color.yellow.opacity(0.2)
        }
    }

    private func calculateSimilarity() -> Int {
        let text1 = "\(email1.subject) \(email1.from) \(email1.body)"
        let text2 = "\(email2.subject) \(email2.from) \(email2.body)"

        let len1 = text1.count
        let len2 = text2.count
        let maxLen = max(len1, len2)

        guard maxLen > 0 else { return 100 }

        let distance = levenshteinDistance(text1, text2)
        let similarity = Double(maxLen - distance) / Double(maxLen) * 100

        return Int(similarity)
    }

    private func countDifferences() -> Int {
        var count = 0

        if email1.subject != email2.subject { count += 1 }
        if email1.from != email2.from { count += 1 }
        if email1.to != email2.to { count += 1 }
        if email1.body != email2.body { count += 1 }
        if email1.attachmentCount != email2.attachmentCount { count += 1 }

        return count
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let empty = [Int](repeating: 0, count: s2.count + 1)
        var last = [Int](0...s2.count)

        for (i, char1) in s1.enumerated() {
            var cur = [i + 1] + empty
            for (j, char2) in s2.enumerated() {
                cur[j + 1] = char1 == char2 ? last[j] : min(last[j], last[j + 1], cur[j]) + 1
            }
            last = cur
        }

        return last.last ?? 0
    }
}

// MARK: - Comparison Section

struct ComparisonSection: View {
    let title: String
    let content: String
    let otherContent: String
    let highlightDifferences: Bool
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .bold()
                .foregroundColor(color)

            Text(content)
                .font(.body)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(backgroundColor)
                .cornerRadius(6)
        }
    }

    private var backgroundColor: Color {
        if !highlightDifferences {
            return Color(NSColor.controlBackgroundColor)
        }

        if content == otherContent {
            return Color(NSColor.controlBackgroundColor)
        } else {
            return Color.yellow.opacity(0.2)
        }
    }
}

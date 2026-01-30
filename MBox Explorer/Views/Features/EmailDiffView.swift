//
//  EmailDiffView.swift
//  MBox Explorer
//
//  Compare two emails side by side with diff highlighting
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import SwiftUI

struct EmailDiffView: View {
    let email1: Email
    let email2: Email

    @State private var diffMode: DiffMode = .sideBySide
    @State private var showOnlyDifferences = false
    @State private var diffResult: DiffResult?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Compare Emails")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Picker("Mode", selection: $diffMode) {
                    Text("Side by Side").tag(DiffMode.sideBySide)
                    Text("Unified").tag(DiffMode.unified)
                    Text("Inline").tag(DiffMode.inline)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Toggle("Only Differences", isOn: $showOnlyDifferences)
                    .toggleStyle(.checkbox)
            }
            .padding()

            Divider()

            // Metadata comparison
            metadataComparison

            Divider()

            // Content comparison
            switch diffMode {
            case .sideBySide:
                sideBySideView
            case .unified:
                unifiedView
            case .inline:
                inlineView
            }
        }
        .onAppear {
            computeDiff()
        }
    }

    // MARK: - Metadata Comparison

    private var metadataComparison: some View {
        HStack(spacing: 0) {
            // Email 1 metadata
            VStack(alignment: .leading, spacing: 4) {
                metadataRow("Subject", email1.subject, email2.subject, isFirst: true)
                metadataRow("From", email1.from, email2.from, isFirst: true)
                metadataRow("To", email1.to ?? "", email2.to ?? "", isFirst: true)
                metadataRow("Date", email1.date, email2.date, isFirst: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.windowBackgroundColor))

            Divider()

            // Email 2 metadata
            VStack(alignment: .leading, spacing: 4) {
                metadataRow("Subject", email1.subject, email2.subject, isFirst: false)
                metadataRow("From", email1.from, email2.from, isFirst: false)
                metadataRow("To", email1.to ?? "", email2.to ?? "", isFirst: false)
                metadataRow("Date", email1.date, email2.date, isFirst: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.windowBackgroundColor))
        }
    }

    private func metadataRow(_ label: String, _ value1: String, _ value2: String, isFirst: Bool) -> some View {
        let currentValue = isFirst ? value1 : value2
        let isDifferent = value1 != value2

        return HStack {
            Text(label + ":")
                .fontWeight(.medium)
                .frame(width: 60, alignment: .trailing)

            Text(currentValue)
                .lineLimit(1)
                .foregroundColor(isDifferent ? .orange : .primary)
                .background(isDifferent ? Color.orange.opacity(0.1) : Color.clear)
        }
        .font(.caption)
    }

    // MARK: - Side by Side View

    private var sideBySideView: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let diff = diffResult {
                        ForEach(Array(diff.lines1.enumerated()), id: \.offset) { index, line in
                            if !showOnlyDifferences || line.status != .unchanged {
                                DiffLineView(line: line, lineNumber: index + 1)
                            }
                        }
                    }
                }
                .padding()
            }
            .frame(minWidth: 300)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let diff = diffResult {
                        ForEach(Array(diff.lines2.enumerated()), id: \.offset) { index, line in
                            if !showOnlyDifferences || line.status != .unchanged {
                                DiffLineView(line: line, lineNumber: index + 1)
                            }
                        }
                    }
                }
                .padding()
            }
            .frame(minWidth: 300)
        }
    }

    // MARK: - Unified View

    private var unifiedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let diff = diffResult {
                    ForEach(Array(diff.unifiedLines.enumerated()), id: \.offset) { index, line in
                        if !showOnlyDifferences || line.status != .unchanged {
                            UnifiedDiffLineView(line: line)
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Inline View

    private var inlineView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let diff = diffResult {
                    ForEach(Array(diff.inlineSegments.enumerated()), id: \.offset) { _, segment in
                        InlineSegmentView(segment: segment)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Diff Computation

    private func computeDiff() {
        let lines1 = email1.body.components(separatedBy: .newlines)
        let lines2 = email2.body.components(separatedBy: .newlines)

        // Simple LCS-based diff
        let lcs = longestCommonSubsequence(lines1, lines2)

        var diffLines1: [DiffLine] = []
        var diffLines2: [DiffLine] = []
        var unifiedLines: [UnifiedDiffLine] = []

        var i = 0, j = 0, k = 0

        while i < lines1.count || j < lines2.count {
            if k < lcs.count && i < lines1.count && j < lines2.count &&
               lines1[i] == lcs[k] && lines2[j] == lcs[k] {
                // Common line
                diffLines1.append(DiffLine(text: lines1[i], status: .unchanged))
                diffLines2.append(DiffLine(text: lines2[j], status: .unchanged))
                unifiedLines.append(UnifiedDiffLine(text: lines1[i], status: .unchanged))
                i += 1
                j += 1
                k += 1
            } else if i < lines1.count && (k >= lcs.count || lines1[i] != lcs[k]) {
                // Removed from first
                diffLines1.append(DiffLine(text: lines1[i], status: .removed))
                unifiedLines.append(UnifiedDiffLine(text: "- " + lines1[i], status: .removed))
                i += 1
            } else if j < lines2.count && (k >= lcs.count || lines2[j] != lcs[k]) {
                // Added in second
                diffLines2.append(DiffLine(text: lines2[j], status: .added))
                unifiedLines.append(UnifiedDiffLine(text: "+ " + lines2[j], status: .added))
                j += 1
            }
        }

        // Compute inline segments
        let inlineSegments = computeInlineSegments(lines1, lines2, lcs)

        diffResult = DiffResult(
            lines1: diffLines1,
            lines2: diffLines2,
            unifiedLines: unifiedLines,
            inlineSegments: inlineSegments
        )
    }

    private func longestCommonSubsequence(_ arr1: [String], _ arr2: [String]) -> [String] {
        let m = arr1.count
        let n = arr2.count

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if arr1[i - 1] == arr2[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find LCS
        var lcs: [String] = []
        var i = m, j = n

        while i > 0 && j > 0 {
            if arr1[i - 1] == arr2[j - 1] {
                lcs.insert(arr1[i - 1], at: 0)
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return lcs
    }

    private func computeInlineSegments(_ lines1: [String], _ lines2: [String], _ lcs: [String]) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        var i = 0, j = 0, k = 0

        while i < lines1.count || j < lines2.count {
            if k < lcs.count && i < lines1.count && lines1[i] == lcs[k] {
                if j < lines2.count && lines2[j] == lcs[k] {
                    // Common
                    segments.append(InlineSegment(text: lines1[i], status: .unchanged))
                    i += 1
                    j += 1
                    k += 1
                } else {
                    // Added in second
                    segments.append(InlineSegment(text: lines2[j], status: .added))
                    j += 1
                }
            } else if i < lines1.count {
                // Removed from first
                segments.append(InlineSegment(text: lines1[i], status: .removed))
                i += 1
            } else if j < lines2.count {
                // Added in second
                segments.append(InlineSegment(text: lines2[j], status: .added))
                j += 1
            }
        }

        return segments
    }
}

// MARK: - Supporting Views

struct DiffLineView: View {
    let line: DiffLine
    let lineNumber: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("\(lineNumber)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)

            Text(line.text)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(line.status.foregroundColor)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(line.status.backgroundColor)
    }
}

struct UnifiedDiffLineView: View {
    let line: UnifiedDiffLine

    var body: some View {
        HStack(spacing: 8) {
            Text(line.status.prefix)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(line.status.foregroundColor)
                .frame(width: 15, alignment: .leading)

            Text(line.text.hasPrefix("+ ") || line.text.hasPrefix("- ") ? String(line.text.dropFirst(2)) : line.text)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(line.status.foregroundColor)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(line.status.backgroundColor)
    }
}

struct InlineSegmentView: View {
    let segment: InlineSegment

    var body: some View {
        Text(segment.text)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(segment.status.foregroundColor)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(segment.status.backgroundColor)
            .strikethrough(segment.status == .removed, color: .red)
    }
}

// MARK: - Models

enum DiffMode {
    case sideBySide
    case unified
    case inline
}

enum LineStatus {
    case unchanged
    case added
    case removed
    case modified

    var backgroundColor: Color {
        switch self {
        case .unchanged: return .clear
        case .added: return .green.opacity(0.2)
        case .removed: return .red.opacity(0.2)
        case .modified: return .yellow.opacity(0.2)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .unchanged: return .primary
        case .added: return .green
        case .removed: return .red
        case .modified: return .orange
        }
    }

    var prefix: String {
        switch self {
        case .unchanged: return " "
        case .added: return "+"
        case .removed: return "-"
        case .modified: return "~"
        }
    }
}

struct DiffLine {
    let text: String
    let status: LineStatus
}

struct UnifiedDiffLine {
    let text: String
    let status: LineStatus
}

struct InlineSegment {
    let text: String
    let status: LineStatus
}

struct DiffResult {
    let lines1: [DiffLine]
    let lines2: [DiffLine]
    let unifiedLines: [UnifiedDiffLine]
    let inlineSegments: [InlineSegment]
}

// MARK: - Email Comparison Selector

struct EmailComparisonSelector: View {
    @ObservedObject var viewModel: MboxViewModel
    @State private var email1Index: Int = 0
    @State private var email2Index: Int = 1
    @State private var showComparison = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Select Emails to Compare")
                .font(.headline)

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("First Email")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Email 1", selection: $email1Index) {
                        ForEach(0..<viewModel.emails.count, id: \.self) { index in
                            Text(viewModel.emails[index].subject)
                                .lineLimit(1)
                                .tag(index)
                        }
                    }
                    .frame(width: 250)
                }

                VStack(alignment: .leading) {
                    Text("Second Email")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Email 2", selection: $email2Index) {
                        ForEach(0..<viewModel.emails.count, id: \.self) { index in
                            Text(viewModel.emails[index].subject)
                                .lineLimit(1)
                                .tag(index)
                        }
                    }
                    .frame(width: 250)
                }
            }

            Button("Compare") {
                showComparison = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(email1Index == email2Index || viewModel.emails.count < 2)
        }
        .padding()
        .sheet(isPresented: $showComparison) {
            if viewModel.emails.count > max(email1Index, email2Index) {
                EmailDiffView(
                    email1: viewModel.emails[email1Index],
                    email2: viewModel.emails[email2Index]
                )
                .frame(minWidth: 800, minHeight: 600)
            }
        }
    }
}

#Preview {
    EmailComparisonSelector(viewModel: MboxViewModel())
}

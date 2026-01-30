//
//  WordCloudView.swift
//  MBox Explorer
//
//  Word cloud visualization of email topics
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import SwiftUI

struct WordCloudView: View {
    @ObservedObject var viewModel: MboxViewModel
    @State private var wordData: [WordData] = []
    @State private var selectedWord: WordData?
    @State private var sourceType: WordCloudSource = .subjects
    @State private var dateFilter: DateFilterOption = .all
    @State private var isGenerating = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            cloudHeader

            Divider()

            if viewModel.emails.isEmpty {
                emptyState
            } else if isGenerating {
                generatingState
            } else if wordData.isEmpty {
                generatePrompt
            } else {
                HSplitView {
                    // Word cloud
                    cloudContent
                        .frame(minWidth: 400)

                    // Word details
                    wordDetails
                        .frame(width: 300)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            generateWordCloud()
        }
    }

    // MARK: - Header

    private var cloudHeader: some View {
        HStack {
            Text("Word Cloud")
                .font(.headline)

            Spacer()

            // Source picker
            Picker("Source", selection: $sourceType) {
                ForEach(WordCloudSource.allCases, id: \.self) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .frame(width: 150)
            .onChange(of: sourceType) { _ in
                generateWordCloud()
            }

            // Date filter
            Picker("Period", selection: $dateFilter) {
                ForEach(DateFilterOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .frame(width: 120)
            .onChange(of: dateFilter) { _ in
                generateWordCloud()
            }

            Button(action: generateWordCloud) {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isGenerating)
        }
        .padding()
    }

    // MARK: - Cloud Content

    private var cloudContent: some View {
        GeometryReader { geometry in
            ScrollView {
                FlowLayout(spacing: 8) {
                    ForEach(wordData.prefix(100)) { word in
                        wordBubble(word)
                    }
                }
                .padding()
            }
        }
    }

    private func wordBubble(_ word: WordData) -> some View {
        let isSelected = selectedWord?.word == word.word
        let fontSize = calculateFontSize(for: word)

        return Text(word.word)
            .font(.system(size: fontSize, weight: word.count > 20 ? .bold : .regular))
            .foregroundColor(isSelected ? .white : wordColor(for: word))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .onTapGesture {
                selectedWord = selectedWord?.word == word.word ? nil : word
            }
            .onHover { hovering in
                if hovering && selectedWord == nil {
                    // Visual feedback
                }
            }
    }

    private func calculateFontSize(for word: WordData) -> CGFloat {
        let maxCount = wordData.first?.count ?? 1
        let minSize: CGFloat = 12
        let maxSize: CGFloat = 36

        let ratio = Double(word.count) / Double(maxCount)
        return minSize + CGFloat(ratio) * (maxSize - minSize)
    }

    private func wordColor(for word: WordData) -> Color {
        let colors: [Color] = [.blue, .purple, .green, .orange, .pink, .cyan]
        let index = abs(word.word.hashValue) % colors.count
        return colors[index]
    }

    // MARK: - Word Details

    private var wordDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let word = selectedWord {
                // Selected word details
                VStack(alignment: .leading, spacing: 8) {
                    Text(word.word)
                        .font(.title2)
                        .fontWeight(.bold)

                    HStack {
                        Label("\(word.count) occurrences", systemImage: "number")
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Emails containing this word
                Text("Related Emails")
                    .font(.headline)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(emailsContaining(word.word).prefix(20)) { email in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(email.subject)
                                    .font(.subheadline)
                                    .lineLimit(1)

                                Text(email.from)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            .onTapGesture {
                                viewModel.selectedEmail = email
                            }
                        }
                    }
                }
            } else {
                // No selection
                VStack(spacing: 12) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)

                    Text("Select a word")
                        .font(.headline)

                    Text("Click on any word to see related emails")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()

            // Statistics
            VStack(alignment: .leading, spacing: 4) {
                Text("Statistics")
                    .font(.headline)

                Text("Total unique words: \(wordData.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Emails analyzed: \(filteredEmails.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
        }
        .padding()
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No emails to analyze")
                .font(.headline)
            Text("Open an MBOX file to generate a word cloud")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var generatingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Generating word cloud...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var generatePrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Ready to generate")
                .font(.headline)
            Button("Generate Word Cloud") {
                generateWordCloud()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Generation

    private var filteredEmails: [Email] {
        let calendar = Calendar.current
        let now = Date()

        switch dateFilter {
        case .all:
            return viewModel.emails
        case .lastWeek:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            return viewModel.emails.filter { ($0.dateObject ?? .distantPast) >= weekAgo }
        case .lastMonth:
            let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)!
            return viewModel.emails.filter { ($0.dateObject ?? .distantPast) >= monthAgo }
        case .lastYear:
            let yearAgo = calendar.date(byAdding: .year, value: -1, to: now)!
            return viewModel.emails.filter { ($0.dateObject ?? .distantPast) >= yearAgo }
        }
    }

    private func generateWordCloud() {
        isGenerating = true
        selectedWord = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let words = extractWords()

            DispatchQueue.main.async {
                self.wordData = words
                self.isGenerating = false
            }
        }
    }

    private func extractWords() -> [WordData] {
        var wordCounts: [String: Int] = [:]

        let stopWords = Set([
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "must", "shall", "can", "need", "to", "of",
            "in", "for", "on", "with", "at", "by", "from", "as", "into", "through",
            "during", "before", "after", "above", "below", "between", "under",
            "again", "further", "then", "once", "here", "there", "when", "where",
            "why", "how", "all", "each", "few", "more", "most", "other", "some",
            "such", "no", "nor", "not", "only", "own", "same", "so", "than", "too",
            "very", "just", "and", "but", "if", "or", "because", "until", "while",
            "re", "fwd", "fw", "subject", "sent", "from", "date", "mailto", "http",
            "https", "www", "com", "org", "net", "this", "that", "these", "those",
            "what", "which", "who", "whom", "your", "yours", "you", "i", "me", "my",
            "we", "us", "our", "they", "them", "their", "it", "its", "am", "pm",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "january", "february", "march", "april", "june", "july", "august",
            "september", "october", "november", "december"
        ])

        for email in filteredEmails {
            let text: String
            switch sourceType {
            case .subjects:
                text = email.subject
            case .body:
                text = String(email.body.prefix(500))
            case .both:
                text = "\(email.subject) \(email.body.prefix(300))"
            }

            let words = text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !stopWords.contains($0) && !$0.allSatisfy { $0.isNumber } }

            for word in words {
                wordCounts[word, default: 0] += 1
            }
        }

        return wordCounts
            .filter { $0.value >= 3 } // Minimum occurrences
            .map { WordData(word: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private func emailsContaining(_ word: String) -> [Email] {
        let lowered = word.lowercased()
        return filteredEmails.filter { email in
            let text: String
            switch sourceType {
            case .subjects:
                text = email.subject.lowercased()
            case .body:
                text = email.body.lowercased()
            case .both:
                text = "\(email.subject) \(email.body)".lowercased()
            }
            return text.contains(lowered)
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)

        for (index, subview) in subviews.enumerated() {
            let point = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var positions: [CGPoint] = []
        var height: CGFloat = 0

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > width && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            height = y + rowHeight
        }
    }
}

// MARK: - Models

struct WordData: Identifiable {
    let id = UUID()
    let word: String
    let count: Int
}

enum WordCloudSource: String, CaseIterable {
    case subjects = "Subjects"
    case body = "Body"
    case both = "Both"
}

enum DateFilterOption: String, CaseIterable {
    case all = "All Time"
    case lastWeek = "Last Week"
    case lastMonth = "Last Month"
    case lastYear = "Last Year"
}

#Preview {
    WordCloudView(viewModel: MboxViewModel())
}

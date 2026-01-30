//
//  SentimentDashboard.swift
//  MBox Explorer
//
//  Analyze and visualize email sentiment over time
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import SwiftUI
import Charts
import NaturalLanguage

class DashboardSentimentAnalyzer: ObservableObject {
    static let shared = DashboardSentimentAnalyzer()

    @Published var isAnalyzing = false
    @Published var progress: Double = 0
    @Published var results: [DashboardSentimentResult] = []

    private let tagger = NLTagger(tagSchemes: [.sentimentScore])

    // MARK: - Analyze Single Email

    func analyzeSentiment(of email: Email) -> DashboardSentimentResult {
        let text = "\(email.subject) \(email.body)"
        tagger.string = text

        var totalScore: Double = 0
        var sentenceCount = 0

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .sentence, scheme: .sentimentScore) { tag, range in
            if let tag = tag, let score = Double(tag.rawValue) {
                totalScore += score
                sentenceCount += 1
            }
            return true
        }

        let averageScore = sentenceCount > 0 ? totalScore / Double(sentenceCount) : 0

        return DashboardSentimentResult(
            emailId: email.id,
            subject: email.subject,
            from: email.from,
            date: email.dateObject ?? Date(),
            score: averageScore,
            sentiment: DashboardSentimentType(from: averageScore)
        )
    }

    // MARK: - Batch Analysis

    func analyzeEmails(_ emails: [Email], progressCallback: ((Double) -> Void)? = nil) async -> [DashboardSentimentResult] {
        await MainActor.run {
            isAnalyzing = true
            progress = 0
            results = []
        }

        defer {
            Task { @MainActor in
                isAnalyzing = false
            }
        }

        var allResults: [DashboardSentimentResult] = []

        for (index, email) in emails.enumerated() {
            let result = analyzeSentiment(of: email)
            allResults.append(result)

            let progressValue = Double(index + 1) / Double(emails.count)
            await MainActor.run {
                self.progress = progressValue
                self.results = allResults
            }
            progressCallback?(progressValue)
        }

        return allResults
    }

    // MARK: - Aggregate Analysis

    func getSentimentOverTime(_ results: [DashboardSentimentResult]) -> [DashboardSentimentByDate] {
        let calendar = Calendar.current

        var byDate: [Date: [Double]] = [:]

        for result in results {
            let day = calendar.startOfDay(for: result.date)
            byDate[day, default: []].append(result.score)
        }

        return byDate.map { date, scores in
            DashboardSentimentByDate(
                date: date,
                averageScore: scores.reduce(0, +) / Double(scores.count),
                count: scores.count
            )
        }.sorted { $0.date < $1.date }
    }

    func getSentimentBySender(_ results: [DashboardSentimentResult]) -> [DashboardSentimentBySender] {
        var bySender: [String: [Double]] = [:]

        for result in results {
            let sender = extractName(from: result.from)
            bySender[sender, default: []].append(result.score)
        }

        return bySender.map { sender, scores in
            DashboardSentimentBySender(
                sender: sender,
                averageScore: scores.reduce(0, +) / Double(scores.count),
                emailCount: scores.count
            )
        }.sorted { $0.emailCount > $1.emailCount }
    }

    private func extractName(from address: String) -> String {
        if let range = address.range(of: "<") {
            return String(address[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return address
    }
}

// MARK: - Dashboard View

struct SentimentDashboardView: View {
    @ObservedObject var viewModel: MboxViewModel
    @StateObject private var analyzer = DashboardSentimentAnalyzer()
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sentiment Analysis")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if analyzer.isAnalyzing {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("\(Int(analyzer.progress * 100))%")
                        .foregroundColor(.secondary)
                } else if analyzer.results.isEmpty {
                    Button("Analyze Emails") {
                        Task {
                            await analyzer.analyzeEmails(viewModel.emails)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()

            if !analyzer.results.isEmpty {
                // Tab selector
                Picker("View", selection: $selectedTab) {
                    Text("Overview").tag(0)
                    Text("Timeline").tag(1)
                    Text("By Sender").tag(2)
                    Text("Details").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Divider()
                    .padding(.top)

                // Content
                switch selectedTab {
                case 0:
                    overviewTab
                case 1:
                    timelineTab
                case 2:
                    bySenderTab
                case 3:
                    detailsTab
                default:
                    EmptyView()
                }
            }

            Spacer()
        }
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary cards
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                    SentimentCard(
                        title: "Positive",
                        count: analyzer.results.filter { $0.sentiment == DashboardSentimentType.positive }.count,
                        icon: "face.smiling",
                        color: .green
                    )

                    SentimentCard(
                        title: "Neutral",
                        count: analyzer.results.filter { $0.sentiment == DashboardSentimentType.neutral }.count,
                        icon: "minus.circle",
                        color: .gray
                    )

                    SentimentCard(
                        title: "Negative",
                        count: analyzer.results.filter { $0.sentiment == DashboardSentimentType.negative }.count,
                        icon: "exclamationmark.triangle",
                        color: .red
                    )

                    SentimentCard(
                        title: "Average",
                        value: averageSentiment,
                        icon: "chart.bar",
                        color: sentimentColor(averageSentiment)
                    )
                }
                .padding()

                // Distribution chart
                sentimentDistributionChart
                    .padding()
            }
        }
    }

    private var averageSentiment: Double {
        let results = analyzer.results
        guard !results.isEmpty else { return 0 }
        return results.map { $0.score }.reduce(0, +) / Double(results.count)
    }

    private var sentimentDistributionChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sentiment Distribution")
                .font(.headline)

            let results = analyzer.results
            let positive = results.filter { $0.sentiment == DashboardSentimentType.positive }.count
            let neutral = results.filter { $0.sentiment == DashboardSentimentType.neutral }.count
            let negative = results.filter { $0.sentiment == DashboardSentimentType.negative }.count

            Chart {
                SectorMark(angle: .value("Count", positive), innerRadius: .ratio(0.6))
                    .foregroundStyle(.green)
                    .annotation(position: .overlay) {
                        Text("\(positive)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }

                SectorMark(angle: .value("Count", neutral), innerRadius: .ratio(0.6))
                    .foregroundStyle(.gray)
                    .annotation(position: .overlay) {
                        Text("\(neutral)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }

                SectorMark(angle: .value("Count", negative), innerRadius: .ratio(0.6))
                    .foregroundStyle(.red)
                    .annotation(position: .overlay) {
                        Text("\(negative)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
            }
            .frame(height: 200)

            // Legend
            HStack(spacing: 20) {
                LegendItem(color: .green, label: "Positive")
                LegendItem(color: .gray, label: "Neutral")
                LegendItem(color: .red, label: "Negative")
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Timeline Tab

    private var timelineTab: some View {
        let results = analyzer.results
        let timelineData = analyzer.getSentimentOverTime(results)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Sentiment Over Time")
                .font(.headline)
                .padding(.horizontal)

            Chart(timelineData) { item in
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Score", item.averageScore)
                )
                .foregroundStyle(sentimentColor(item.averageScore))

                PointMark(
                    x: .value("Date", item.date),
                    y: .value("Score", item.averageScore)
                )
                .foregroundStyle(sentimentColor(item.averageScore))
            }
            .chartYScale(domain: -1...1)
            .chartYAxis {
                AxisMarks(values: [-1, -0.5, 0, 0.5, 1]) { value in
                    AxisValueLabel {
                        if let score = value.as(Double.self) {
                            Text(sentimentLabel(score))
                        }
                    }
                    AxisGridLine()
                }
            }
            .padding()
        }
    }

    // MARK: - By Sender Tab

    private var bySenderTab: some View {
        let results = analyzer.results
        let senderData = Array(analyzer.getSentimentBySender(results)
            .filter { $0.emailCount >= 3 }
            .prefix(20))

        return List(senderData, id: \.sender) { item in
            HStack {
                Circle()
                    .fill(sentimentColor(item.averageScore))
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading) {
                    Text(item.sender)
                        .fontWeight(.medium)
                    Text("\(item.emailCount) emails")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text(String(format: "%.2f", item.averageScore))
                        .fontWeight(.medium)
                        .foregroundColor(sentimentColor(item.averageScore))

                    Text(sentimentLabel(item.averageScore))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Details Tab

    private var detailsTab: some View {
        let results = analyzer.results.sorted { $0.score < $1.score }
        return List(results) { result in
            HStack {
                Circle()
                    .fill(sentimentColor(result.score))
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading) {
                    Text(result.subject)
                        .lineLimit(1)

                    HStack {
                        Text(result.from)
                        Text("•")
                        Text(result.date, style: .date)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                Text(String(format: "%.2f", result.score))
                    .fontWeight(.medium)
                    .foregroundColor(sentimentColor(result.score))
            }
        }
    }

    // MARK: - Helpers

    private func sentimentColor(_ score: Double) -> Color {
        if score > 0.2 { return .green }
        if score < -0.2 { return .red }
        return .gray
    }

    private func sentimentLabel(_ score: Double) -> String {
        if score > 0.2 { return "Positive" }
        if score < -0.2 { return "Negative" }
        return "Neutral"
    }
}

// MARK: - Supporting Views

struct SentimentCard: View {
    let title: String
    var count: Int? = nil
    var value: Double? = nil
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            if let count = count {
                Text("\(count)")
                    .font(.title)
                    .fontWeight(.bold)
            } else if let value = value {
                Text(String(format: "%.2f", value))
                    .font(.title)
                    .fontWeight(.bold)
            }

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
    }
}

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
        }
    }
}

// MARK: - Models

struct DashboardSentimentResult: Identifiable {
    let id = UUID()
    let emailId: UUID
    let subject: String
    let from: String
    let date: Date
    let score: Double
    let sentiment: DashboardSentimentType
}

enum DashboardSentimentType: String {
    case positive = "Positive"
    case neutral = "Neutral"
    case negative = "Negative"

    init(from score: Double) {
        if score > 0.2 {
            self = .positive
        } else if score < -0.2 {
            self = .negative
        } else {
            self = .neutral
        }
    }

    var color: Color {
        switch self {
        case .positive: return .green
        case .neutral: return .gray
        case .negative: return .red
        }
    }
}

struct DashboardSentimentByDate: Identifiable {
    let id = UUID()
    let date: Date
    let averageScore: Double
    let count: Int
}

struct DashboardSentimentBySender: Identifiable {
    let id = UUID()
    let sender: String
    let averageScore: Double
    let emailCount: Int
}

#Preview {
    SentimentDashboardView(viewModel: MboxViewModel())
}

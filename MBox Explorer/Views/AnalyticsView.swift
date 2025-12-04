//
//  AnalyticsView.swift
//  MBox Explorer
//
//  Comprehensive analytics dashboard with charts and statistics
//

import SwiftUI

struct AnalyticsView: View {
    @ObservedObject var viewModel: MboxViewModel
    @State private var analytics: AnalyticsEngine.EmailAnalytics?
    @State private var isLoading = false
    @State private var selectedTimeRange: TimeRange = .all
    @State private var showingExportDialog = false

    enum TimeRange: String, CaseIterable {
        case all = "All Time"
        case lastYear = "Last Year"
        case lastMonth = "Last Month"
        case lastWeek = "Last Week"
    }

    var filteredEmails: [Email] {
        let emails = viewModel.emails

        switch selectedTimeRange {
        case .all:
            return emails
        case .lastYear:
            let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
            return emails.filter { $0.dateObject ?? Date.distantPast > yearAgo }
        case .lastMonth:
            let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
            return emails.filter { $0.dateObject ?? Date.distantPast > monthAgo }
        case .lastWeek:
            let weekAgo = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date())!
            return emails.filter { $0.dateObject ?? Date.distantPast > weekAgo }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("Email Analytics")
                            .font(.largeTitle)
                            .bold()
                        Text("Insights and statistics from your email archive")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Time range selector
                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 400)
                    .onChange(of: selectedTimeRange) {
                        generateAnalytics()
                    }

                    Button {
                        showingExportDialog = true
                    } label: {
                        Label("Export Report", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()

                if isLoading {
                    ProgressView("Analyzing emails...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(50)
                } else if let analytics = analytics {
                    // Overview Cards
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        AnalyticStatCard(
                            title: "Total Emails",
                            value: "\(analytics.totalCount)",
                            icon: "envelope.fill",
                            color: .blue
                        )

                        AnalyticStatCard(
                            title: "Date Range",
                            value: "\(analytics.dateRange.days) days",
                            icon: "calendar",
                            color: .green
                        )

                        AnalyticStatCard(
                            title: "Total Size",
                            value: ByteCountFormatter.string(fromByteCount: Int64(analytics.totalSize), countStyle: .file),
                            icon: "internaldrive.fill",
                            color: .orange
                        )

                        AnalyticStatCard(
                            title: "Attachments",
                            value: "\(analytics.attachmentStats.totalAttachments)",
                            icon: "paperclip",
                            color: .purple
                        )
                    }
                    .padding(.horizontal)

                    // Charts Section
                    VStack(spacing: 20) {
                        // Email Activity by Hour
                        AnalyticsCard(title: "Email Activity by Hour", icon: "clock.fill") {
                            HourlyActivityChart(data: analytics.emailsByHour)
                        }

                        HStack(spacing: 20) {
                            // Top Senders
                            AnalyticsCard(title: "Top 10 Senders", icon: "person.fill") {
                                TopListView(items: analytics.topSenders.map { ($0.email, $0.count) })
                            }

                            // Top Domains
                            AnalyticsCard(title: "Top Domains", icon: "globe") {
                                TopListView(items: analytics.domainStats.topDomains.map { ($0.domain, $0.count) })
                            }
                        }

                        // Email Timeline
                        AnalyticsCard(title: "Email Timeline", icon: "chart.line.uptrend.xyaxis") {
                            TimelineChart(emails: filteredEmails)
                        }

                        HStack(spacing: 20) {
                            // Thread Statistics
                            AnalyticsCard(title: "Thread Statistics", icon: "bubble.left.and.bubble.right.fill") {
                                ThreadStatsView(stats: analytics.threadStats)
                            }

                            // Attachment Statistics
                            AnalyticsCard(title: "Attachment Breakdown", icon: "paperclip") {
                                AttachmentStatsView(stats: analytics.attachmentStats)
                            }
                        }

                        // Email Activity by Day of Week
                        AnalyticsCard(title: "Activity by Day of Week", icon: "calendar.badge.clock") {
                            DayOfWeekChart(data: analytics.emailsByDay)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    ContentUnavailableView(
                        "No Analytics Available",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Load an MBOX file to view analytics")
                    )
                }
            }
            .padding(.vertical)
        }
        .onAppear {
            if analytics == nil && !viewModel.emails.isEmpty {
                generateAnalytics()
            }
        }
        .onChange(of: viewModel.emails.count) {
            generateAnalytics()
        }
        .sheet(isPresented: $showingExportDialog) {
            if let analytics = analytics {
                ExportAnalyticsDialog(analytics: analytics, isPresented: $showingExportDialog)
            }
        }
    }

    private func generateAnalytics() {
        isLoading = true
        Task {
            let result = AnalyticsEngine.analyze(filteredEmails)
            await MainActor.run {
                self.analytics = result
                self.isLoading = false
            }
        }
    }
}

// MARK: - Stat Card

struct AnalyticStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                Spacer()
            }

            Text(value)
                .font(.title)
                .bold()

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Analytics Card

struct AnalyticsCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
                    .bold()
            }

            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Hourly Activity Chart

struct HourlyActivityChart: View {
    let data: [Int: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let maxCount = data.values.max() ?? 1

            ForEach(0..<24, id: \.self) { hour in
                HStack(spacing: 8) {
                    Text(String(format: "%02d:00", hour))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)

                    GeometryReader { geometry in
                        let count = data[hour] ?? 0
                        let width = CGFloat(count) / CGFloat(maxCount) * geometry.size.width

                        HStack(spacing: 4) {
                            Rectangle()
                                .fill(Color.blue.gradient)
                                .frame(width: max(width, 0))
                                .cornerRadius(4)

                            Text("\(count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Spacer()
                        }
                    }
                }
                .frame(height: 16)
            }
        }
    }
}

// MARK: - Top List View

struct TopListView: View {
    let items: [(String, Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text("\(index + 1).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 20, alignment: .trailing)

                    Text(item.0)
                        .font(.body)
                        .lineLimit(1)

                    Spacer()

                    Text("\(item.1)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
    }
}

// MARK: - Timeline Chart

struct TimelineChart: View {
    let emails: [Email]

    var body: some View {
        let timeSeries = AnalyticsEngine.generateTimeSeries(emails, groupBy: .day)

        if timeSeries.dates.isEmpty {
            Text("No timeline data available")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 150)
        } else {
            GeometryReader { geometry in
                let maxCount = timeSeries.maxCount
                let width = geometry.size.width
                let height = geometry.size.height
                let pointSpacing = width / CGFloat(max(timeSeries.dates.count - 1, 1))

                ZStack(alignment: .bottomLeading) {
                    // Grid lines
                    ForEach(0..<5) { i in
                        let y = height * (1.0 - CGFloat(i) / 4.0)
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: width, y: y))
                        }
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    }

                    // Line chart
                    Path { path in
                        for (index, count) in timeSeries.counts.enumerated() {
                            let x = CGFloat(index) * pointSpacing
                            let y = height - (height * CGFloat(count) / CGFloat(maxCount))

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.blue, lineWidth: 2)

                    // Area fill
                    Path { path in
                        for (index, count) in timeSeries.counts.enumerated() {
                            let x = CGFloat(index) * pointSpacing
                            let y = height - (height * CGFloat(count) / CGFloat(maxCount))

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: height))
                                path.addLine(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }

                        if !timeSeries.counts.isEmpty {
                            path.addLine(to: CGPoint(x: width, y: height))
                            path.closeSubpath()
                        }
                    }
                    .fill(LinearGradient(
                        colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                }
            }
            .frame(height: 200)
        }
    }
}

// MARK: - Thread Stats View

struct ThreadStatsView: View {
    let stats: AnalyticsEngine.ThreadStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalyticStatRow(label: "Total Threads", value: "\(stats.totalThreads)")
            AnalyticStatRow(label: "Longest Thread", value: "\(stats.longestThread) emails")
            AnalyticStatRow(label: "Average Thread Length", value: String(format: "%.1f emails", stats.averageThreadLength))
            AnalyticStatRow(label: "Single Email Threads", value: "\(stats.singleEmailCount)")
        }
    }
}

// MARK: - Attachment Stats View

struct AttachmentStatsView: View {
    let stats: AnalyticsEngine.AttachmentStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AnalyticStatRow(label: "Total Attachments", value: "\(stats.totalAttachments)")
            AnalyticStatRow(label: "Emails with Attachments", value: "\(stats.emailsWithAttachments)")
            AnalyticStatRow(label: "Total Size", value: ByteCountFormatter.string(fromByteCount: Int64(stats.totalAttachmentSize), countStyle: .file))
            AnalyticStatRow(label: "Avg. per Email", value: String(format: "%.2f", stats.averageAttachmentsPerEmail))
        }
    }
}

// MARK: - Day of Week Chart

struct DayOfWeekChart: View {
    let data: [Int: Int]

    let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(1...7, id: \.self) { weekday in
                VStack(spacing: 4) {
                    let count = data[weekday] ?? 0
                    let maxCount = data.values.max() ?? 1
                    let height = CGFloat(count) / CGFloat(maxCount) * 150

                    Text("\(count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Rectangle()
                        .fill(Color.blue.gradient)
                        .frame(width: 40, height: max(height, 20))
                        .cornerRadius(6)

                    Text(dayNames[weekday - 1])
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Stat Row

struct AnalyticStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.body)
                .bold()
        }
    }
}

// MARK: - Export Dialog

struct ExportAnalyticsDialog: View {
    let analytics: AnalyticsEngine.EmailAnalytics
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Export Analytics Report")
                .font(.title2)
                .bold()

            Text("Export comprehensive analytics report to a text file")
                .font(.body)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Export...") {
                    isPresented = false
                    exportReport()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func exportReport() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "email_analytics_report.txt"
        panel.message = "Export analytics report"

        panel.begin { (response: NSApplication.ModalResponse) in
            if response == .OK, let url = panel.url {
                do {
                    try AnalyticsEngine.exportAnalyticsReport(analytics, to: url)
                } catch {
                    print("Error exporting analytics report: \(error)")
                }
            }
        }
    }
}

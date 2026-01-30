//
//  EmailStatisticsDashboard.swift
//  MBox Explorer
//
//  Comprehensive email statistics and analytics dashboard
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import SwiftUI
import Charts

struct EmailStatisticsDashboard: View {
    @ObservedObject var viewModel: MboxViewModel
    @State private var selectedTimeRange: TimeRange = .all
    @State private var statistics: EmailStatistics?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with time range selector
                HStack {
                    Text("Email Statistics")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }
                .padding(.horizontal)

                if isLoading {
                    ProgressView("Analyzing emails...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let stats = statistics {
                    // Overview Cards
                    overviewCards(stats: stats)

                    // Charts Section
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        // Volume over time
                        volumeChart(stats: stats)

                        // Top senders
                        topSendersChart(stats: stats)

                        // Day of week distribution
                        dayOfWeekChart(stats: stats)

                        // Hour of day distribution
                        hourOfDayChart(stats: stats)
                    }
                    .padding(.horizontal)

                    // Detailed Tables
                    HStack(alignment: .top, spacing: 20) {
                        topDomainsTable(stats: stats)
                        responseTimeTable(stats: stats)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .onAppear {
            calculateStatistics()
        }
        .onChange(of: selectedTimeRange) { _, _ in
            calculateStatistics()
        }
    }

    // MARK: - Overview Cards

    private func overviewCards(stats: EmailStatistics) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
            StatCard(
                title: "Total Emails",
                value: "\(stats.totalEmails)",
                icon: "envelope.fill",
                color: .blue
            )

            StatCard(
                title: "Unique Senders",
                value: "\(stats.uniqueSenders)",
                icon: "person.2.fill",
                color: .green
            )

            StatCard(
                title: "With Attachments",
                value: "\(stats.withAttachments)",
                icon: "paperclip",
                color: .orange
            )

            StatCard(
                title: "Avg. per Day",
                value: String(format: "%.1f", stats.averagePerDay),
                icon: "chart.line.uptrend.xyaxis",
                color: .purple
            )
        }
        .padding(.horizontal)
    }

    // MARK: - Charts

    private func volumeChart(stats: EmailStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Email Volume Over Time")
                .font(.headline)

            Chart(stats.volumeByDate) { item in
                BarMark(
                    x: .value("Date", item.date),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(.blue.gradient)
            }
            .frame(height: 200)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
    }

    private func topSendersChart(stats: EmailStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Senders")
                .font(.headline)

            Chart(stats.topSenders.prefix(10)) { sender in
                BarMark(
                    x: .value("Count", sender.count),
                    y: .value("Sender", sender.name)
                )
                .foregroundStyle(.green.gradient)
            }
            .frame(height: 200)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
    }

    private func dayOfWeekChart(stats: EmailStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Emails by Day of Week")
                .font(.headline)

            Chart(stats.byDayOfWeek) { item in
                BarMark(
                    x: .value("Day", item.day),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(.orange.gradient)
            }
            .frame(height: 200)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
    }

    private func hourOfDayChart(stats: EmailStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Emails by Hour")
                .font(.headline)

            Chart(stats.byHourOfDay) { item in
                LineMark(
                    x: .value("Hour", item.hour),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(.purple)

                AreaMark(
                    x: .value("Hour", item.hour),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(.purple.opacity(0.2))
            }
            .frame(height: 200)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Tables

    private func topDomainsTable(stats: EmailStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Domains")
                .font(.headline)

            ForEach(stats.topDomains.prefix(10), id: \.domain) { item in
                HStack {
                    Text(item.domain)
                    Spacer()
                    Text("\(item.count)")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
    }

    private func responseTimeTable(stats: EmailStatistics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Response Time Analysis")
                .font(.headline)

            HStack {
                Text("Average Response Time")
                Spacer()
                Text(formatDuration(stats.avgResponseTime))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)

            Divider()

            HStack {
                Text("Fastest Response")
                Spacer()
                Text(formatDuration(stats.fastestResponse))
                    .foregroundColor(.green)
            }
            .padding(.vertical, 4)

            Divider()

            HStack {
                Text("Slowest Response")
                Spacer()
                Text(formatDuration(stats.slowestResponse))
                    .foregroundColor(.red)
            }
            .padding(.vertical, 4)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private func calculateStatistics() {
        isLoading = true

        Task {
            let emails = filterByTimeRange(viewModel.emails)
            let stats = await computeStatistics(for: emails)

            await MainActor.run {
                self.statistics = stats
                self.isLoading = false
            }
        }
    }

    private func filterByTimeRange(_ emails: [Email]) -> [Email] {
        guard selectedTimeRange != .all else { return emails }

        let calendar = Calendar.current
        let now = Date()

        let cutoff: Date? = {
            switch selectedTimeRange {
            case .week:
                return calendar.date(byAdding: .day, value: -7, to: now)
            case .month:
                return calendar.date(byAdding: .month, value: -1, to: now)
            case .quarter:
                return calendar.date(byAdding: .month, value: -3, to: now)
            case .year:
                return calendar.date(byAdding: .year, value: -1, to: now)
            case .all:
                return nil
            }
        }()

        guard let cutoff = cutoff else { return emails }

        return emails.filter { email in
            guard let date = email.dateObject else { return false }
            return date >= cutoff
        }
    }

    private func computeStatistics(for emails: [Email]) async -> EmailStatistics {
        var senderCounts: [String: Int] = [:]
        var domainCounts: [String: Int] = [:]
        var dateCounts: [Date: Int] = [:]
        var dayOfWeekCounts: [Int: Int] = [:]
        var hourCounts: [Int: Int] = [:]
        var attachmentCount = 0

        let calendar = Calendar.current

        for email in emails {
            // Sender
            let sender = extractName(from: email.from)
            senderCounts[sender, default: 0] += 1

            // Domain
            if let domain = extractDomain(from: email.from) {
                domainCounts[domain, default: 0] += 1
            }

            // Date analysis
            if let date = email.dateObject {
                let day = calendar.startOfDay(for: date)
                dateCounts[day, default: 0] += 1

                let weekday = calendar.component(.weekday, from: date)
                dayOfWeekCounts[weekday, default: 0] += 1

                let hour = calendar.component(.hour, from: date)
                hourCounts[hour, default: 0] += 1
            }

            // Attachments
            if email.attachments?.isEmpty == false {
                attachmentCount += 1
            }
        }

        // Calculate averages
        let uniqueDays = Set(dateCounts.keys).count
        let avgPerDay = uniqueDays > 0 ? Double(emails.count) / Double(uniqueDays) : 0

        // Build statistics object
        let topSenders = senderCounts
            .map { SenderStat(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        let topDomains = domainCounts
            .map { DomainStat(domain: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        let volumeByDate = dateCounts
            .map { DateCount(date: $0.key, count: $0.value) }
            .sorted { $0.date < $1.date }

        let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let byDayOfWeek = (1...7).map { day in
            DayOfWeekCount(day: dayNames[day], count: dayOfWeekCounts[day] ?? 0)
        }

        let byHourOfDay = (0...23).map { hour in
            HourCount(hour: hour, count: hourCounts[hour] ?? 0)
        }

        return EmailStatistics(
            totalEmails: emails.count,
            uniqueSenders: senderCounts.count,
            withAttachments: attachmentCount,
            averagePerDay: avgPerDay,
            topSenders: topSenders,
            topDomains: topDomains,
            volumeByDate: volumeByDate,
            byDayOfWeek: byDayOfWeek,
            byHourOfDay: byHourOfDay,
            avgResponseTime: 0, // Would need thread analysis
            fastestResponse: 0,
            slowestResponse: 0
        )
    }

    private func extractName(from address: String) -> String {
        if let range = address.range(of: "<") {
            return String(address[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return address
    }

    private func extractDomain(from address: String) -> String? {
        guard let atRange = address.range(of: "@") else { return nil }
        var domain = String(address[atRange.upperBound...])
        if let endRange = domain.range(of: ">") {
            domain = String(domain[..<endRange.lowerBound])
        }
        return domain.lowercased()
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else if seconds < 86400 {
            return "\(Int(seconds / 3600))h"
        } else {
            return "\(Int(seconds / 86400))d"
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Models

enum TimeRange: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"
    case all = "All Time"
}

struct EmailStatistics {
    let totalEmails: Int
    let uniqueSenders: Int
    let withAttachments: Int
    let averagePerDay: Double
    let topSenders: [SenderStat]
    let topDomains: [DomainStat]
    let volumeByDate: [DateCount]
    let byDayOfWeek: [DayOfWeekCount]
    let byHourOfDay: [HourCount]
    let avgResponseTime: TimeInterval
    let fastestResponse: TimeInterval
    let slowestResponse: TimeInterval
}

struct SenderStat: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
}

struct DomainStat {
    let domain: String
    let count: Int
}

struct DateCount: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
}

struct DayOfWeekCount: Identifiable {
    let id = UUID()
    let day: String
    let count: Int
}

struct HourCount: Identifiable {
    let id = UUID()
    let hour: Int
    let count: Int
}

#Preview {
    EmailStatisticsDashboard(viewModel: MboxViewModel())
}

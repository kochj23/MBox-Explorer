//
//  HeatmapView.swift
//  MBox Explorer
//
//  Activity heatmap showing when emails are sent/received
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import SwiftUI

struct HeatmapView: View {
    @ObservedObject var viewModel: MboxViewModel
    @State private var heatmapType: HeatmapType = .dayHour
    @State private var hoveredCell: (Int, Int)?
    @State private var selectedPerson: String?

    private let cellSize: CGFloat = 25
    private let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let hours = (0..<24).map { String(format: "%02d:00", $0) }
    private let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            heatmapHeader

            Divider()

            if viewModel.emails.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Main heatmap
                        heatmapGrid

                        Divider()

                        // Statistics
                        statsSection
                    }
                    .padding()
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Header

    private var heatmapHeader: some View {
        HStack {
            Text("Activity Heatmap")
                .font(.headline)

            Spacer()

            // Heatmap type picker
            Picker("Type", selection: $heatmapType) {
                ForEach(HeatmapType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            // Person filter
            if !topSenders.isEmpty {
                Picker("Filter by", selection: $selectedPerson) {
                    Text("All").tag(nil as String?)
                    ForEach(topSenders, id: \.self) { sender in
                        Text(sender.prefix(30)).tag(sender as String?)
                    }
                }
                .frame(width: 200)
            }
        }
        .padding()
    }

    // MARK: - Heatmap Grid

    @ViewBuilder
    private var heatmapGrid: some View {
        switch heatmapType {
        case .dayHour:
            dayHourHeatmap
        case .monthDay:
            monthDayHeatmap
        case .yearMonth:
            yearMonthHeatmap
        }
    }

    // MARK: - Day × Hour Heatmap

    private var dayHourHeatmap: some View {
        let data = calculateDayHourData()
        let maxCount = data.values.max() ?? 1

        return VStack(alignment: .leading, spacing: 0) {
            // Title
            Text("Emails by Day of Week and Hour")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)

            HStack(alignment: .top, spacing: 0) {
                // Y-axis labels (hours)
                VStack(spacing: 0) {
                    Text("") // Spacer for day labels
                        .frame(height: cellSize)

                    ForEach(0..<24, id: \.self) { hour in
                        Text(hours[hour])
                            .font(.caption2)
                            .frame(width: 50, height: cellSize, alignment: .trailing)
                    }
                }

                VStack(spacing: 0) {
                    // X-axis labels (days)
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { day in
                            Text(days[day])
                                .font(.caption)
                                .frame(width: cellSize, height: cellSize)
                        }
                    }

                    // Grid
                    ForEach(0..<24, id: \.self) { hour in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { day in
                                let count = data["\(day)-\(hour)"] ?? 0
                                let intensity = Double(count) / Double(maxCount)

                                cellView(count: count, intensity: intensity, row: hour, col: day)
                            }
                        }
                    }
                }
            }

            // Legend
            heatmapLegend(maxCount: maxCount)
        }
    }

    // MARK: - Month × Day Heatmap

    private var monthDayHeatmap: some View {
        let data = calculateMonthDayData()
        let maxCount = data.values.max() ?? 1

        return VStack(alignment: .leading, spacing: 0) {
            Text("Emails by Month and Day of Month")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)

            HStack(alignment: .top, spacing: 0) {
                // Y-axis labels (days 1-31)
                VStack(spacing: 0) {
                    Text("")
                        .frame(height: cellSize)

                    ForEach(1...31, id: \.self) { day in
                        Text("\(day)")
                            .font(.caption2)
                            .frame(width: 30, height: cellSize, alignment: .trailing)
                    }
                }

                VStack(spacing: 0) {
                    // X-axis labels (months)
                    HStack(spacing: 0) {
                        ForEach(0..<12, id: \.self) { month in
                            Text(months[month])
                                .font(.caption2)
                                .frame(width: cellSize, height: cellSize)
                        }
                    }

                    // Grid
                    ForEach(1...31, id: \.self) { day in
                        HStack(spacing: 0) {
                            ForEach(0..<12, id: \.self) { month in
                                let count = data["\(month)-\(day)"] ?? 0
                                let intensity = Double(count) / Double(maxCount)

                                cellView(count: count, intensity: intensity, row: day, col: month)
                            }
                        }
                    }
                }
            }

            heatmapLegend(maxCount: maxCount)
        }
    }

    // MARK: - Year × Month Heatmap

    private var yearMonthHeatmap: some View {
        let data = calculateYearMonthData()
        let maxCount = data.counts.values.max() ?? 1
        let years = data.years.sorted()

        return VStack(alignment: .leading, spacing: 0) {
            Text("Emails by Year and Month")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)

            HStack(alignment: .top, spacing: 0) {
                // Y-axis labels (months)
                VStack(spacing: 0) {
                    Text("")
                        .frame(height: cellSize)

                    ForEach(0..<12, id: \.self) { month in
                        Text(months[month])
                            .font(.caption2)
                            .frame(width: 40, height: cellSize, alignment: .trailing)
                    }
                }

                VStack(spacing: 0) {
                    // X-axis labels (years)
                    HStack(spacing: 0) {
                        ForEach(years, id: \.self) { year in
                            Text("\(year)")
                                .font(.caption2)
                                .frame(width: cellSize * 1.5, height: cellSize)
                        }
                    }

                    // Grid
                    ForEach(0..<12, id: \.self) { month in
                        HStack(spacing: 0) {
                            ForEach(years, id: \.self) { year in
                                let count = data.counts["\(year)-\(month)"] ?? 0
                                let intensity = Double(count) / Double(maxCount)

                                cellView(count: count, intensity: intensity, row: month, col: year)
                                    .frame(width: cellSize * 1.5)
                            }
                        }
                    }
                }
            }

            heatmapLegend(maxCount: maxCount)
        }
    }

    // MARK: - Cell View

    private func cellView(count: Int, intensity: Double, row: Int, col: Int) -> some View {
        let isHovered = hoveredCell?.0 == row && hoveredCell?.1 == col

        return Rectangle()
            .fill(cellColor(intensity: intensity, isHovered: isHovered))
            .frame(width: cellSize - 2, height: cellSize - 2)
            .cornerRadius(3)
            .overlay(
                Group {
                    if isHovered && count > 0 {
                        Text("\(count)")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                }
            )
            .onHover { hovering in
                hoveredCell = hovering ? (row, col) : nil
            }
            .help("\(count) emails")
    }

    private func cellColor(intensity: Double, isHovered: Bool) -> Color {
        if isHovered {
            return .accentColor
        }

        if intensity == 0 {
            return Color.gray.opacity(0.1)
        }

        // Gradient from light blue to dark blue
        return Color.blue.opacity(0.2 + intensity * 0.7)
    }

    // MARK: - Legend

    private func heatmapLegend(maxCount: Int) -> some View {
        HStack(spacing: 4) {
            Text("Less")
                .font(.caption2)
                .foregroundColor(.secondary)

            ForEach(0..<5, id: \.self) { level in
                Rectangle()
                    .fill(Color.blue.opacity(0.2 + Double(level) * 0.15))
                    .frame(width: 12, height: 12)
                    .cornerRadius(2)
            }

            Text("More")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            Text("Max: \(maxCount) emails")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 12)
    }

    // MARK: - Statistics Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity Patterns")
                .font(.headline)

            let patterns = analyzePatterns()

            HStack(spacing: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Peak Day")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(patterns.peakDay)
                        .font(.title3)
                        .fontWeight(.medium)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Peak Hour")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(patterns.peakHour)
                        .font(.title3)
                        .fontWeight(.medium)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Weekend Activity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(patterns.weekendPercent)%")
                        .font(.title3)
                        .fontWeight(.medium)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Business Hours")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(patterns.businessHoursPercent)%")
                        .font(.title3)
                        .fontWeight(.medium)
                }

                Spacer()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No activity data")
                .font(.headline)
            Text("Open an MBOX file to see the heatmap")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Calculation

    private var filteredEmails: [Email] {
        guard let person = selectedPerson else {
            return viewModel.emails
        }
        return viewModel.emails.filter { $0.from.contains(person) }
    }

    private var topSenders: [String] {
        let grouped = Dictionary(grouping: viewModel.emails, by: { $0.from })
        return grouped.sorted { $0.value.count > $1.value.count }
            .prefix(10)
            .map { $0.key }
    }

    private func calculateDayHourData() -> [String: Int] {
        let calendar = Calendar.current
        var data: [String: Int] = [:]

        for email in filteredEmails {
            guard let date = email.dateObject else { continue }
            let weekday = calendar.component(.weekday, from: date) - 1 // 0-6
            let hour = calendar.component(.hour, from: date)
            let key = "\(weekday)-\(hour)"
            data[key, default: 0] += 1
        }

        return data
    }

    private func calculateMonthDayData() -> [String: Int] {
        let calendar = Calendar.current
        var data: [String: Int] = [:]

        for email in filteredEmails {
            guard let date = email.dateObject else { continue }
            let month = calendar.component(.month, from: date) - 1 // 0-11
            let day = calendar.component(.day, from: date)
            let key = "\(month)-\(day)"
            data[key, default: 0] += 1
        }

        return data
    }

    private func calculateYearMonthData() -> (counts: [String: Int], years: [Int]) {
        let calendar = Calendar.current
        var data: [String: Int] = [:]
        var years = Set<Int>()

        for email in filteredEmails {
            guard let date = email.dateObject else { continue }
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date) - 1
            let key = "\(year)-\(month)"
            data[key, default: 0] += 1
            years.insert(year)
        }

        return (data, Array(years))
    }

    private func analyzePatterns() -> ActivityPatterns {
        let calendar = Calendar.current
        var dayCount = [Int: Int]()
        var hourCount = [Int: Int]()
        var weekendCount = 0
        var businessHoursCount = 0

        for email in filteredEmails {
            guard let date = email.dateObject else { continue }
            let weekday = calendar.component(.weekday, from: date)
            let hour = calendar.component(.hour, from: date)

            dayCount[weekday, default: 0] += 1
            hourCount[hour, default: 0] += 1

            if weekday == 1 || weekday == 7 {
                weekendCount += 1
            }

            if hour >= 9 && hour < 17 && weekday >= 2 && weekday <= 6 {
                businessHoursCount += 1
            }
        }

        let peakDay = dayCount.max(by: { $0.value < $1.value })?.key ?? 1
        let peakHour = hourCount.max(by: { $0.value < $1.value })?.key ?? 12

        let total = filteredEmails.count
        let weekendPercent = total > 0 ? Int(Double(weekendCount) / Double(total) * 100) : 0
        let businessPercent = total > 0 ? Int(Double(businessHoursCount) / Double(total) * 100) : 0

        return ActivityPatterns(
            peakDay: days[(peakDay - 1) % 7],
            peakHour: hours[peakHour],
            weekendPercent: weekendPercent,
            businessHoursPercent: businessPercent
        )
    }
}

// MARK: - Models

enum HeatmapType: String, CaseIterable {
    case dayHour = "Day × Hour"
    case monthDay = "Month × Day"
    case yearMonth = "Year × Month"
}

struct ActivityPatterns {
    let peakDay: String
    let peakHour: String
    let weekendPercent: Int
    let businessHoursPercent: Int
}

#Preview {
    HeatmapView(viewModel: MboxViewModel())
}

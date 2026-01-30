//
//  TimelineView.swift
//  MBox Explorer
//
//  Visual email timeline with zoom and navigation
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import SwiftUI

struct TimelineView: View {
    @ObservedObject var viewModel: MboxViewModel
    @State private var selectedDate: Date?
    @State private var zoomLevel: TimelineZoom = .month
    @State private var scrollOffset: CGFloat = 0
    @State private var hoveredDay: Date?

    private let dayWidth: CGFloat = 20
    private let maxBarHeight: CGFloat = 100

    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            timelineHeader

            Divider()

            // Main timeline
            if viewModel.emails.isEmpty {
                emptyState
            } else {
                timelineContent
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Header

    private var timelineHeader: some View {
        HStack {
            Text("Email Timeline")
                .font(.headline)

            Spacer()

            // Zoom controls
            Picker("Zoom", selection: $zoomLevel) {
                ForEach(TimelineZoom.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            // Jump to date
            DatePicker("", selection: Binding(
                get: { selectedDate ?? Date() },
                set: { selectedDate = $0 }
            ), displayedComponents: .date)
            .datePickerStyle(.compact)
            .frame(width: 120)
        }
        .padding()
    }

    // MARK: - Timeline Content

    private var timelineContent: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Stats bar
                statsBar

                // Timeline visualization
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Bar chart
                        barChart
                            .frame(height: maxBarHeight + 40)

                        // Date labels
                        dateLabels
                            .frame(height: 50)
                    }
                    .padding(.horizontal)
                }

                Divider()

                // Selected day detail
                if let date = selectedDate ?? hoveredDay {
                    selectedDayDetail(date: date)
                }
            }
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        let data = calculateTimelineData()

        return HStack(spacing: 20) {
            StatBadge(label: "Total", value: "\(viewModel.emails.count)")
            StatBadge(label: "Date Range", value: formatDateRange(data.dateRange))
            StatBadge(label: "Peak Day", value: formatPeakDay(data.peakDay))
            StatBadge(label: "Avg/Day", value: String(format: "%.1f", data.averagePerDay))

            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Bar Chart

    private var barChart: some View {
        let data = calculateTimelineData()
        let maxCount = data.dailyCounts.values.max() ?? 1

        return HStack(alignment: .bottom, spacing: 1) {
            ForEach(data.sortedDays, id: \.self) { day in
                let count = data.dailyCounts[day] ?? 0
                let height = CGFloat(count) / CGFloat(maxCount) * maxBarHeight

                VStack(spacing: 2) {
                    if hoveredDay == day || selectedDate == day {
                        Text("\(count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Rectangle()
                        .fill(barColor(for: day, count: count, max: maxCount))
                        .frame(width: dayWidth - 2, height: max(2, height))
                        .cornerRadius(2)
                }
                .frame(width: dayWidth)
                .onTapGesture {
                    selectedDate = day
                }
                .onHover { hovering in
                    hoveredDay = hovering ? day : nil
                }
            }
        }
    }

    // MARK: - Date Labels

    private var dateLabels: some View {
        let data = calculateTimelineData()
        let calendar = Calendar.current

        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(data.sortedDays.enumerated()), id: \.element) { index, day in
                let components = calendar.dateComponents([.day, .month, .year], from: day)
                let showLabel = shouldShowLabel(at: index, for: day, in: data.sortedDays)

                VStack {
                    if showLabel {
                        Text(formatLabel(for: day))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(-45))
                    }
                }
                .frame(width: dayWidth)
            }
        }
    }

    // MARK: - Selected Day Detail

    private func selectedDayDetail(date: Date) -> some View {
        let dayEmails = viewModel.emails.filter { email in
            guard let emailDate = email.dateObject else { return false }
            return Calendar.current.isDate(emailDate, inSameDayAs: date)
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formatFullDate(date))
                    .font(.headline)
                Text("(\(dayEmails.count) emails)")
                    .foregroundColor(.secondary)

                Spacer()

                Button("Clear") {
                    selectedDate = nil
                }
                .buttonStyle(.borderless)
            }

            if dayEmails.isEmpty {
                Text("No emails on this day")
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(dayEmails.prefix(20)) { email in
                            HStack {
                                Text(email.from)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: 150, alignment: .leading)

                                Text(email.subject)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                            .onTapGesture {
                                viewModel.selectedEmail = email
                            }
                        }

                        if dayEmails.count > 20 {
                            Text("... and \(dayEmails.count - 20) more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No emails to display")
                .font(.headline)
            Text("Open an MBOX file to see the timeline")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func calculateTimelineData() -> TimelineData {
        let calendar = Calendar.current

        var dailyCounts: [Date: Int] = [:]
        var minDate: Date?
        var maxDate: Date?

        for email in viewModel.emails {
            guard let date = email.dateObject else { continue }

            let dayStart = calendar.startOfDay(for: date)
            dailyCounts[dayStart, default: 0] += 1

            if minDate == nil || date < minDate! {
                minDate = date
            }
            if maxDate == nil || date > maxDate! {
                maxDate = date
            }
        }

        let sortedDays = dailyCounts.keys.sorted()
        let peakDay = dailyCounts.max(by: { $0.value < $1.value })
        let totalDays = sortedDays.count
        let average = totalDays > 0 ? Double(viewModel.emails.count) / Double(totalDays) : 0

        return TimelineData(
            dailyCounts: dailyCounts,
            sortedDays: sortedDays,
            dateRange: (minDate, maxDate),
            peakDay: peakDay.map { ($0.key, $0.value) },
            averagePerDay: average
        )
    }

    private func barColor(for day: Date, count: Int, max: Int) -> Color {
        if selectedDate == day {
            return .accentColor
        }
        if hoveredDay == day {
            return .accentColor.opacity(0.7)
        }

        let intensity = Double(count) / Double(max)
        return Color.blue.opacity(0.3 + intensity * 0.5)
    }

    private func shouldShowLabel(at index: Int, for day: Date, in days: [Date]) -> Bool {
        let calendar = Calendar.current

        switch zoomLevel {
        case .day:
            return true
        case .week:
            return calendar.component(.weekday, from: day) == 1 // Sundays
        case .month:
            return calendar.component(.day, from: day) == 1 // First of month
        case .year:
            return calendar.component(.month, from: day) == 1 && calendar.component(.day, from: day) == 1
        }
    }

    private func formatLabel(for date: Date) -> String {
        let formatter = DateFormatter()

        switch zoomLevel {
        case .day:
            formatter.dateFormat = "d"
        case .week:
            formatter.dateFormat = "MMM d"
        case .month:
            formatter.dateFormat = "MMM"
        case .year:
            formatter.dateFormat = "yyyy"
        }

        return formatter.string(from: date)
    }

    private func formatDateRange(_ range: (Date?, Date?)) -> String {
        guard let start = range.0, let end = range.1 else { return "N/A" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func formatPeakDay(_ peak: (Date, Int)?) -> String {
        guard let (date, count) = peak else { return "N/A" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return "\(formatter.string(from: date)) (\(count))"
    }

    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views

struct StatBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Models

enum TimelineZoom: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"
}

struct TimelineData {
    let dailyCounts: [Date: Int]
    let sortedDays: [Date]
    let dateRange: (Date?, Date?)
    let peakDay: (Date, Int)?
    let averagePerDay: Double
}

#Preview {
    TimelineView(viewModel: MboxViewModel())
}

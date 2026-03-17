//
//  MBoxExplorerWidget.swift
//  MBox Explorer Widget
//
//  WidgetKit widget for MBox Explorer showing email stats and quick actions
//
//  Author: Jordan Koch
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct Provider: TimelineProvider {

    func placeholder(in context: Context) -> MBoxEntry {
        MBoxEntry(date: Date(), data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (MBoxEntry) -> Void) {
        let data = SharedDataManager.shared.loadWidgetData()
        let entry = MBoxEntry(date: Date(), data: data.isEmpty ? .placeholder : data)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MBoxEntry>) -> Void) {
        let data = SharedDataManager.shared.loadWidgetData()
        let entry = MBoxEntry(date: Date(), data: data)

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct MBoxEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

// MARK: - Widget Views

/// Small widget - Shows email count and basic stats
struct SmallWidgetView: View {
    let entry: MBoxEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "envelope.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Spacer()
                if entry.data.isEmpty {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.orange)
                }
            }

            if entry.data.isEmpty {
                Text("No Data")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Open MBox Explorer")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(entry.data.formattedEmailCount)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("emails")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if let fileName = entry.data.loadedFileName {
                    Text(fileName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

/// Medium widget - Shows stats and top senders
struct MediumWidgetView: View {
    let entry: MBoxEntry

    var body: some View {
        HStack(spacing: 16) {
            // Left side - Stats
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.blue)
                    Text("MBox Explorer")
                        .font(.caption)
                        .fontWeight(.semibold)
                }

                if entry.data.isEmpty {
                    Spacer()
                    Text("No Data")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Load an mbox file")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    Spacer()

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(entry.data.formattedEmailCount)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("emails")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(entry.data.totalThreads)")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text("threads")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(entry.data.dateRange)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Right side - Top Senders
            VStack(alignment: .leading, spacing: 4) {
                Text("Top Senders")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                if entry.data.topSenders.isEmpty {
                    Spacer()
                    Text("No data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    ForEach(entry.data.topSenders.prefix(3)) { sender in
                        SenderRowView(sender: sender)
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

/// Large widget - Shows all information
struct LargeWidgetView: View {
    let entry: MBoxEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "envelope.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                VStack(alignment: .leading) {
                    Text("MBox Explorer")
                        .font(.headline)
                    if let fileName = entry.data.loadedFileName {
                        Text(fileName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text("Updated \(entry.data.lastUpdatedText)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if entry.data.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Data Available")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Open MBox Explorer and load an mbox file")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                // Stats Row
                HStack(spacing: 20) {
                    StatBox(value: entry.data.formattedEmailCount, label: "Emails", icon: "envelope")
                    StatBox(value: "\(entry.data.totalThreads)", label: "Threads", icon: "bubble.left.and.bubble.right")
                }
                .padding(.vertical, 4)

                // Date range
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.secondary)
                    Text(entry.data.dateRange)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Two columns
                HStack(alignment: .top, spacing: 16) {
                    // Top Senders
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Top Senders", systemImage: "person.2.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        if entry.data.topSenders.isEmpty {
                            Text("No senders")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(entry.data.topSenders.prefix(4)) { sender in
                                SenderRowView(sender: sender)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Recent Queries
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Recent Searches", systemImage: "magnifyingglass")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        if entry.data.recentQueries.isEmpty {
                            Text("No searches yet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(entry.data.recentQueries.prefix(4)) { query in
                                QueryRowView(query: query)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 0)

            // Quick Action Button
            if !entry.data.isEmpty {
                Link(destination: URL(string: "mboxexplorer://search")!) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Search Emails")
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Helper Views

struct SenderRowView: View {
    let sender: WidgetSenderInfo

    var body: some View {
        HStack(spacing: 8) {
            Text(sender.initials)
                .font(.caption2)
                .fontWeight(.bold)
                .frame(width: 24, height: 24)
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 0) {
                Text(sender.displayName)
                    .font(.caption)
                    .lineLimit(1)
                Text("\(sender.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct QueryRowView: View {
    let query: QueryInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(query.query)
                .font(.caption)
                .lineLimit(1)
            Text(query.relativeTime)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct StatBox: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Widget Entry View

struct MBoxExplorerWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget Configuration

struct MBoxExplorerWidget: Widget {
    let kind: String = "MBoxExplorerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MBoxExplorerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("MBox Explorer")
        .description("View email statistics and quick search")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget Bundle

@main
struct MBoxExplorerWidgetBundle: WidgetBundle {
    var body: some Widget {
        MBoxExplorerWidget()
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    MBoxExplorerWidget()
} timeline: {
    MBoxEntry(date: Date(), data: .placeholder)
    MBoxEntry(date: Date(), data: .empty)
}

#Preview("Medium", as: .systemMedium) {
    MBoxExplorerWidget()
} timeline: {
    MBoxEntry(date: Date(), data: .placeholder)
    MBoxEntry(date: Date(), data: .empty)
}

#Preview("Large", as: .systemLarge) {
    MBoxExplorerWidget()
} timeline: {
    MBoxEntry(date: Date(), data: .placeholder)
    MBoxEntry(date: Date(), data: .empty)
}

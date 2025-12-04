//
//  SidebarView.swift
//  MBox Explorer
//
//  Sidebar navigation
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: MboxViewModel
    @Binding var selectedView: SidebarItem
    @Binding var showingFilePicker: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Main action buttons
            VStack(spacing: 12) {
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Open MBOX File", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if !viewModel.emails.isEmpty {
                    Button {
                        viewModel.showingExportOptions = true
                    } label: {
                        Label("Export All Emails", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    // Export filtered button
                    if viewModel.isFiltered {
                        Button {
                            exportFiltered()
                        } label: {
                            Label("Export Filtered (\(viewModel.filteredEmails.count))",
                                  systemImage: "line.3.horizontal.decrease.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    // Smart filters button
                    Button {
                        viewModel.showingSmartFilters = true
                    } label: {
                        Label(viewModel.smartFilters.isActive ? "Smart Filters ●" : "Smart Filters",
                              systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    // Find duplicates button
                    Button {
                        viewModel.showingDuplicates = true
                    } label: {
                        Label("Find Duplicates", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    // Reveal in Finder button
                    if viewModel.lastExportURL != nil {
                        Button {
                            viewModel.revealLastExportInFinder()
                        } label: {
                            Label("Show Last Export", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
            }
            .padding()

            Divider()

            // Statistics
            List {
                if !viewModel.emails.isEmpty {
                    Section("Statistics") {
                        VStack(alignment: .leading, spacing: 8) {
                            StatRow(label: "Total Emails", value: "\(viewModel.stats.totalEmails)")
                            StatRow(label: "Threads", value: "\(viewModel.stats.totalThreads)")
                            StatRow(label: "Date Range", value: viewModel.stats.dateRange)
                        }
                        .font(.caption)
                    }

                    Section("Top Senders") {
                        ForEach(viewModel.stats.topSenders, id: \.0) { sender, count in
                            HStack {
                                Text(sender)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(count)")
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No MBOX File Loaded",
                        systemImage: "envelope.open",
                        description: Text("Click 'Open MBOX File' to get started")
                    )
                }
            }
        }
        .navigationTitle("MBox Explorer")
    }

    private func icon(for item: SidebarItem) -> String {
        switch item {
        case .allEmails: return "envelope.fill"
        case .ask: return "sparkles"
        case .network: return "point.3.connected.trianglepath.dotted"
        case .attachments: return "paperclip"
        case .analytics: return "chart.bar.xaxis"
        case .operations: return "scissors"
        case .threads: return "bubble.left.and.bubble.right.fill"
        case .senders: return "person.fill"
        case .dates: return "calendar"
        }
    }

    private func exportFiltered() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Filtered_Export"
        panel.message = "Choose location to export filtered emails"

        panel.begin { (response: NSApplication.ModalResponse) in
            if response == .OK, let url = panel.url {
                Task {
                    await viewModel.exportFiltered(to: url, filename: url.lastPathComponent)
                }
            }
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .bold()
        }
    }
}

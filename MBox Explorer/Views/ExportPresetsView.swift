//
//  ExportPresetsView.swift
//  MBox Explorer
//
//  UI for managing export presets and viewing history
//

import SwiftUI

struct ExportPresetsView: View {
    @ObservedObject var viewModel: MboxViewModel
    @Binding var isPresented: Bool
    @State private var selectedTab: Tab = .presets
    @State private var showingNewPreset = false
    @State private var showingEditPreset: ExportPresetManager.ExportPreset?
    @StateObject private var presetManager = PresetManagerViewModel()

    enum Tab: String, CaseIterable {
        case presets = "Presets"
        case history = "History"
        case stats = "Statistics"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Export Management")
                    .font(.title2)
                    .bold()

                Spacer()

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

            // Tab selector
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider()

            // Content
            Group {
                switch selectedTab {
                case .presets:
                    PresetsTabView(
                        presetManager: presetManager,
                        showingNewPreset: $showingNewPreset,
                        showingEditPreset: $showingEditPreset,
                        viewModel: viewModel,
                        isPresented: $isPresented
                    )
                case .history:
                    HistoryTabView(presetManager: presetManager)
                case .stats:
                    StatisticsTabView(presetManager: presetManager)
                }
            }
        }
        .frame(width: 700, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingNewPreset) {
            NewPresetView(presetManager: presetManager, isPresented: $showingNewPreset)
        }
        .sheet(item: $showingEditPreset) { preset in
            EditPresetView(preset: preset, presetManager: presetManager, isPresented: Binding(
                get: { showingEditPreset != nil },
                set: { if !$0 { showingEditPreset = nil } }
            ))
        }
    }
}

// MARK: - Presets Tab

struct PresetsTabView: View {
    @ObservedObject var presetManager: PresetManagerViewModel
    @Binding var showingNewPreset: Bool
    @Binding var showingEditPreset: ExportPresetManager.ExportPreset?
    @ObservedObject var viewModel: MboxViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("\(presetManager.presets.count) presets")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    showingNewPreset = true
                } label: {
                    Label("New Preset", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding()

            // Presets list
            if presetManager.presets.isEmpty {
                ContentUnavailableView(
                    "No Presets",
                    systemImage: "tray",
                    description: Text("Create a preset to save your export settings")
                )
            } else {
                List {
                    ForEach(presetManager.presets) { preset in
                        PresetRow(
                            preset: preset,
                            onUse: {
                                usePreset(preset)
                            },
                            onEdit: {
                                showingEditPreset = preset
                            },
                            onDelete: {
                                presetManager.deletePreset(preset)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func usePreset(_ preset: ExportPresetManager.ExportPreset) {
        // Apply preset to export options - preset.format is a string like "csv", "json", etc.
        // Map to FileFormat
        switch preset.format.lowercased() {
        case "csv":
            viewModel.exportOptions.fileFormat = .csv
        case "json":
            viewModel.exportOptions.fileFormat = .json
        case "markdown":
            viewModel.exportOptions.fileFormat = .markdown
        case "txt":
            viewModel.exportOptions.fileFormat = .txt
        default:
            viewModel.exportOptions.fileFormat = .csv
        }
        viewModel.showingExportOptions = true
        isPresented = false
    }
}

struct PresetRow: View {
    let preset: ExportPresetManager.ExportPreset
    let onUse: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: preset.formatIcon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.body)
                    .bold()

                Text(preset.formatDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    if preset.includeAttachments {
                        Label("Attachments", systemImage: "paperclip")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if preset.includeHeaders {
                        Label("Headers", systemImage: "list.bullet")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button {
                    onUse()
                } label: {
                    Label("Use", systemImage: "arrow.up.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - History Tab

struct HistoryTabView: View {
    @ObservedObject var presetManager: PresetManagerViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("\(presetManager.history.count) exports")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if !presetManager.history.isEmpty {
                    Button {
                        presetManager.clearHistory()
                    } label: {
                        Label("Clear History", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()

            // History list
            if presetManager.history.isEmpty {
                ContentUnavailableView(
                    "No Export History",
                    systemImage: "clock",
                    description: Text("Your export history will appear here")
                )
            } else {
                List {
                    ForEach(presetManager.history) { item in
                        HistoryRow(item: item, onRemove: {
                            presetManager.removeFromHistory(item)
                        })
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct HistoryRow: View {
    let item: ExportPresetManager.ExportHistoryItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: item.formatIcon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 30)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.format.uppercased())
                        .font(.body)
                        .bold()

                    if let presetName = item.presetName {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(presetName)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Label("\(item.emailCount) emails", systemImage: "envelope")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(item.displaySize)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(item.relativeTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(item.destinationPath)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                NSWorkspace.shared.selectFile(item.destinationPath, inFileViewerRootedAtPath: "")
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Statistics Tab

struct StatisticsTabView: View {
    @ObservedObject var presetManager: PresetManagerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let stats = presetManager.statistics

                // Overview
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    PresetStatCard(
                        title: "Total Exports",
                        value: "\(stats.totalExports)",
                        icon: "arrow.up.doc.fill",
                        color: .blue
                    )

                    PresetStatCard(
                        title: "Emails Exported",
                        value: "\(stats.totalEmailsExported)",
                        icon: "envelope.fill",
                        color: .green
                    )

                    PresetStatCard(
                        title: "Data Exported",
                        value: stats.totalDataFormatted,
                        icon: "internaldrive.fill",
                        color: .orange
                    )
                }

                Divider()

                // Format breakdown
                VStack(alignment: .leading, spacing: 12) {
                    Text("Format Breakdown")
                        .font(.headline)

                    ForEach(Array(stats.formatBreakdown.keys.sorted()), id: \.self) { format in
                        let count = stats.formatBreakdown[format] ?? 0
                        let percentage = stats.totalExports > 0 ? Double(count) / Double(stats.totalExports) * 100 : 0

                        HStack {
                            Text(format.uppercased())
                                .font(.body)
                                .frame(width: 80, alignment: .leading)

                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 24)
                                        .cornerRadius(4)

                                    Rectangle()
                                        .fill(Color.blue)
                                        .frame(width: geometry.size.width * CGFloat(percentage / 100), height: 24)
                                        .cornerRadius(4)
                                }
                            }
                            .frame(height: 24)

                            Text("\(count)")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .frame(width: 50, alignment: .trailing)

                            Text(String(format: "%.1f%%", percentage))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }

                Divider()

                // Most used format
                VStack(alignment: .leading, spacing: 8) {
                    Text("Most Used Format")
                        .font(.headline)

                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text(stats.mostUsedFormat.uppercased())
                            .font(.title3)
                            .bold()
                    }
                }
            }
            .padding()
        }
    }
}

struct PresetStatCard: View {
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

// MARK: - New/Edit Preset Views

struct NewPresetView: View {
    @ObservedObject var presetManager: PresetManagerViewModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var format: ExportEngine.FileFormat = .csv
    @State private var includeAttachments = true
    @State private var includeHeaders = true

    var body: some View {
        VStack(spacing: 16) {
            Text("New Export Preset")
                .font(.title2)
                .bold()

            Form {
                TextField("Preset Name", text: $name)

                Picker("Format", selection: $format) {
                    Text("CSV").tag(ExportEngine.FileFormat.csv)
                    Text("JSON").tag(ExportEngine.FileFormat.json)
                    Text("Markdown").tag(ExportEngine.FileFormat.markdown)
                }

                Toggle("Include Attachments", isOn: $includeAttachments)
                Toggle("Include Headers", isOn: $includeHeaders)
            }
            .padding()

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    let formatString: String
                    switch format {
                    case .txt: formatString = "txt"
                    case .csv: formatString = "csv"
                    case .json: formatString = "json"
                    case .markdown: formatString = "markdown"
                    }

                    let preset = ExportPresetManager.ExportPreset(
                        name: name,
                        format: formatString,
                        includeAttachments: includeAttachments,
                        includeHeaders: includeHeaders
                    )
                    presetManager.savePreset(preset)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

struct EditPresetView: View {
    let preset: ExportPresetManager.ExportPreset
    @ObservedObject var presetManager: PresetManagerViewModel
    @Binding var isPresented: Bool
    @State private var name = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Preset")
                .font(.title2)
                .bold()

            TextField("Preset Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .padding()

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    presetManager.renamePreset(preset, newName: name)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            name = preset.name
        }
    }
}

// MARK: - ViewModel

class PresetManagerViewModel: ObservableObject {
    @Published var presets: [ExportPresetManager.ExportPreset] = []
    @Published var history: [ExportPresetManager.ExportHistoryItem] = []
    @Published var statistics: ExportPresetManager.ExportStatistics

    init() {
        self.statistics = ExportPresetManager.ExportStatistics(
            totalExports: 0,
            totalEmailsExported: 0,
            totalDataExported: 0,
            mostUsedFormat: "",
            formatBreakdown: [:]
        )
        loadData()
    }

    func loadData() {
        presets = ExportPresetManager.shared.presets
        history = ExportPresetManager.shared.exportHistory
        statistics = ExportPresetManager.shared.getStatistics()
    }

    func savePreset(_ preset: ExportPresetManager.ExportPreset) {
        ExportPresetManager.shared.savePreset(preset)
        loadData()
    }

    func deletePreset(_ preset: ExportPresetManager.ExportPreset) {
        ExportPresetManager.shared.deletePreset(preset)
        loadData()
    }

    func renamePreset(_ preset: ExportPresetManager.ExportPreset, newName: String) {
        ExportPresetManager.shared.renamePreset(preset, newName: newName)
        loadData()
    }

    func clearHistory() {
        ExportPresetManager.shared.clearHistory()
        loadData()
    }

    func removeFromHistory(_ item: ExportPresetManager.ExportHistoryItem) {
        ExportPresetManager.shared.removeFromHistory(item)
        loadData()
    }
}

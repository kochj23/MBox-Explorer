//
//  MboxOperationsView.swift
//  MBox Explorer
//
//  UI for merging and splitting MBOX files
//

import SwiftUI

struct MboxOperationsView: View {
    @ObservedObject var viewModel: MboxViewModel
    @State private var selectedOperation: Operation = .merge
    @State private var showingFilePicker = false
    @State private var showingDirectoryPicker = false
    @State private var selectedFiles: [URL] = []
    @State private var isProcessing = false
    @State private var progress: Double = 0.0
    @State private var statusMessage = ""

    // Split options
    @State private var splitStrategy: SplitStrategyOption = .byCount
    @State private var splitCount = 1000
    @State private var splitSizeMB = 50
    @State private var splitPeriod: DatePeriod = .month
    @State private var splitDomains = ""

    enum Operation: String, CaseIterable {
        case merge = "Merge Files"
        case split = "Split File"
    }

    enum SplitStrategyOption: String, CaseIterable {
        case byCount = "By Email Count"
        case bySize = "By File Size"
        case byDate = "By Date Period"
        case bySender = "By Sender Domain"
    }

    enum DatePeriod: String, CaseIterable {
        case day = "Day"
        case month = "Month"
        case year = "Year"
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("MBOX File Operations")
                        .font(.largeTitle)
                        .bold()
                    Text("Merge multiple files or split large archives")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker("Operation", selection: $selectedOperation) {
                    ForEach(Operation.allCases, id: \.self) { op in
                        Text(op.rawValue).tag(op)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    if selectedOperation == .merge {
                        mergeSection
                    } else {
                        splitSection
                    }

                    // Progress section
                    if isProcessing {
                        progressSection
                    }

                    // Status message
                    if !statusMessage.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(statusMessage)
                                .font(.body)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result)
        }
    }

    // MARK: - Merge Section

    private var mergeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Merge Multiple MBOX Files")
                .font(.headline)

            Text("Select multiple MBOX files to combine into a single archive. Emails will be sorted by date.")
                .font(.caption)
                .foregroundColor(.secondary)

            // File selection
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Selected Files: \(selectedFiles.count)")
                        .font(.body)
                        .bold()

                    Spacer()

                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Select Files", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)

                    if !selectedFiles.isEmpty {
                        Button {
                            selectedFiles.removeAll()
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if !selectedFiles.isEmpty {
                    List {
                        ForEach(Array(selectedFiles.enumerated()), id: \.offset) { index, url in
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.blue)
                                Text(url.lastPathComponent)
                                    .lineLimit(1)

                                Spacer()

                                Button {
                                    selectedFiles.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 200)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Merge button
            Button {
                performMerge()
            } label: {
                Label("Merge Files", systemImage: "arrow.triangle.merge")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedFiles.count < 2 || isProcessing)
        }
    }

    // MARK: - Split Section

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Split MBOX File")
                .font(.headline)

            Text("Split the current MBOX file into multiple smaller files using various strategies.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Strategy selector
            VStack(alignment: .leading, spacing: 12) {
                Text("Split Strategy")
                    .font(.body)
                    .bold()

                Picker("Strategy", selection: $splitStrategy) {
                    ForEach(SplitStrategyOption.allCases, id: \.self) { strategy in
                        Text(strategy.rawValue).tag(strategy)
                    }
                }
                .pickerStyle(.segmented)

                // Strategy-specific options
                Group {
                    switch splitStrategy {
                    case .byCount:
                        HStack {
                            Text("Emails per file:")
                            Spacer()
                            TextField("", value: $splitCount, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Stepper("", value: $splitCount, in: 100...10000, step: 100)
                        }

                    case .bySize:
                        HStack {
                            Text("Max size per file (MB):")
                            Spacer()
                            TextField("", value: $splitSizeMB, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Stepper("", value: $splitSizeMB, in: 1...1000, step: 10)
                        }

                    case .byDate:
                        HStack {
                            Text("Group by:")
                            Spacer()
                            Picker("", selection: $splitPeriod) {
                                ForEach(DatePeriod.allCases, id: \.self) { period in
                                    Text(period.rawValue).tag(period)
                                }
                            }
                            .frame(width: 150)
                        }

                    case .bySender:
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Domains to split (comma-separated):")
                                .font(.caption)
                            TextField("e.g., gmail.com, outlook.com, company.com", text: $splitDomains)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Preview
            if !viewModel.emails.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.body)
                        .bold()

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Current file:")
                                .foregroundColor(.secondary)
                            Text("\(viewModel.emails.count) emails")
                                .font(.headline)
                        }

                        Spacer()

                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("Estimated output:")
                                .foregroundColor(.secondary)
                            Text("\(estimatedFileCount) files")
                                .font(.headline)
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }

            // Split button
            Button {
                performSplit()
            } label: {
                Label("Split File", systemImage: "scissors")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.emails.isEmpty || isProcessing)
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress, total: 1.0)

            Text("Processing... \(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Computed Properties

    private var estimatedFileCount: Int {
        guard !viewModel.emails.isEmpty else { return 0 }

        switch splitStrategy {
        case .byCount:
            return Int(ceil(Double(viewModel.emails.count) / Double(splitCount)))

        case .bySize:
            let totalSize = viewModel.emails.reduce(0) { $0 + $1.body.count }
            let maxSize = splitSizeMB * 1024 * 1024
            return Int(ceil(Double(totalSize) / Double(maxSize)))

        case .byDate:
            // Rough estimate - would need actual date analysis
            let dates = Set(viewModel.emails.compactMap { $0.dateObject?.description })
            return dates.count

        case .bySender:
            let domains = splitDomains.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return domains.count + 1 // +1 for "other"
        }
    }

    // MARK: - Actions

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            selectedFiles = urls
        case .failure(let error):
            statusMessage = "Error selecting files: \(error.localizedDescription)"
        }
    }

    private func performMerge() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "merged.mbox"
        panel.message = "Choose location for merged file"
        panel.allowedContentTypes = [.item]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                isProcessing = true
                progress = 0.0
                statusMessage = ""

                Task {
                    do {
                        try MboxFileOperations.mergeFiles(selectedFiles, to: url) { current, total in
                            Task { @MainActor in
                                progress = Double(current) / Double(total)
                            }
                        }

                        await MainActor.run {
                            isProcessing = false
                            progress = 1.0
                            statusMessage = "Successfully merged \(selectedFiles.count) files into \(url.lastPathComponent)"
                            selectedFiles.removeAll()
                        }
                    } catch {
                        await MainActor.run {
                            isProcessing = false
                            statusMessage = "Error merging files: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    private func performSplit() {
        let panel = NSOpenPanel()
        panel.canCreateDirectories = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose output directory for split files"

        panel.begin { response in
            if response == .OK, let outputDir = panel.url {
                isProcessing = true
                progress = 0.0
                statusMessage = ""

                Task {
                    do {
                        let strategy: MboxFileOperations.SplitStrategy

                        switch splitStrategy {
                        case .byCount:
                            strategy = .byCount(splitCount)
                        case .bySize:
                            strategy = .bySize(Int64(splitSizeMB * 1024 * 1024))
                        case .byDate:
                            let components: DateComponents
                            switch splitPeriod {
                            case .day:
                                components = DateComponents(day: 1)
                            case .month:
                                components = DateComponents(month: 1)
                            case .year:
                                components = DateComponents(year: 1)
                            }
                            strategy = .byDate(components)
                        case .bySender:
                            let domains = splitDomains.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                            strategy = .bySender(domains)
                        }

                        let outputFiles = try await MboxFileOperations.splitFile(
                            viewModel.currentFileURL ?? URL(fileURLWithPath: ""),
                            strategy: strategy,
                            toDirectory: outputDir
                        ) { current, total in
                            Task { @MainActor in
                                progress = Double(current) / Double(total)
                            }
                        }

                        await MainActor.run {
                            isProcessing = false
                            progress = 1.0
                            statusMessage = "Successfully split into \(outputFiles.count) files in \(outputDir.lastPathComponent)"
                        }
                    } catch {
                        await MainActor.run {
                            isProcessing = false
                            statusMessage = "Error splitting file: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
}

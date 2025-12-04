//
//  ExportOptionsView.swift
//  MBox Explorer
//
//  Export configuration sheet with RAG optimization options
//

import SwiftUI

struct ExportOptionsView: View {
    @ObservedObject var viewModel: MboxViewModel
    @Binding var showingExportPicker: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showingPreview = false
    @State private var showingPresets = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Export Options")
                    .font(.title)
                    .bold()

                Spacer()

                Button {
                    showingPresets = true
                } label: {
                    Label("Presets & History", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
            }

            Form {
                // MARK: - Presets
                Section("Quick Presets") {
                    HStack(spacing: 12) {
                        Button {
                            viewModel.exportOptions = .quickAndDirty()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Quick & Dirty")
                                    .font(.headline)
                                Text("Fast, simple export")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            viewModel.exportOptions = .aiOptimized()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("AI Optimized")
                                    .font(.headline)
                                Text("Best for RAG/LLMs")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            viewModel.exportOptions = .fullArchive()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Full Archive")
                                    .font(.headline)
                                Text("Complete preservation")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // MARK: - Format Options
                Section("Export Format") {
                    Picker("Structure", selection: $viewModel.exportOptions.format) {
                        Text("Per Email").tag(ExportEngine.ExportFormat.onePerEmail)
                        Text("Per Thread").tag(ExportEngine.ExportFormat.onePerThread)
                        Text("Both").tag(ExportEngine.ExportFormat.both)
                    }
                    .pickerStyle(.segmented)

                    Text("Per Email: Creates one file per email message")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Per Thread: Groups related emails into conversation files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - File Format
                Section("File Format") {
                    Picker("Format", selection: $viewModel.exportOptions.fileFormat) {
                        Label("Text", systemImage: "doc.text").tag(ExportEngine.FileFormat.txt)
                        Label("CSV", systemImage: "tablecells").tag(ExportEngine.FileFormat.csv)
                        Label("JSON", systemImage: "curlybraces").tag(ExportEngine.FileFormat.json)
                        Label("Markdown", systemImage: "doc.richtext").tag(ExportEngine.FileFormat.markdown)
                    }
                    .pickerStyle(.segmented)

                    if viewModel.exportOptions.fileFormat == .txt {
                        Text("Plain text files with optional chunking and metadata")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if viewModel.exportOptions.fileFormat == .csv {
                        Text("Spreadsheet format with email metadata and body summary")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if viewModel.exportOptions.fileFormat == .json {
                        Text("Structured JSON format ideal for data processing and APIs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if viewModel.exportOptions.fileFormat == .markdown {
                        Text("Formatted markdown with table of contents and collapsible sections")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: - RAG Optimization (only for TXT format)
                if viewModel.exportOptions.fileFormat == .txt {
                    Section("RAG Optimization") {
                        Toggle("Clean Text for RAG", isOn: $viewModel.exportOptions.cleanText)
                        Text("Removes signatures, quoted text, and email footers")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle("Include Metadata JSON", isOn: $viewModel.exportOptions.includeMetadata)
                        Text("Creates .json files with sender, date, and thread info")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle("Enable Text Chunking", isOn: $viewModel.exportOptions.enableChunking)
                        if viewModel.exportOptions.enableChunking {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Chunk Size:")
                                    TextField("Size", value: $viewModel.exportOptions.chunkSize, formatter: NumberFormatter())
                                        .frame(width: 80)
                                        .textFieldStyle(.roundedBorder)
                                    Text("characters")
                                        .foregroundColor(.secondary)
                                }
                                Text("Splits long emails into \(viewModel.exportOptions.chunkSize)-character chunks with 100-char overlap")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Toggle("Include Thread Links", isOn: $viewModel.exportOptions.includeThreadLinks)
                        Text("Preserves conversation context via Message-ID references")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: - Output Structure
                Section("Output Structure") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Export Output:")
                            .font(.caption)
                            .bold()

                        if viewModel.exportOptions.fileFormat == .txt {
                            Text("""
                            export_directory/
                            ├── emails/           (individual messages)
                            ├── threads/          (conversations)
                            ├── metadata/         (JSON files)
                            └── INDEX.txt         (export summary)
                            """)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        } else if viewModel.exportOptions.fileFormat == .csv {
                            Text("Single CSV file: emails_export.csv")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                        } else if viewModel.exportOptions.fileFormat == .json {
                            Text("Single JSON file: emails_export.json")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                        } else if viewModel.exportOptions.fileFormat == .markdown {
                            Text("Single Markdown file: emails_export.md")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                        }
                    }
                }

                // MARK: - Statistics Preview
                Section("Export Preview") {
                    HStack {
                        Text("Total Emails:")
                        Spacer()
                        Text("\(viewModel.emails.count)")
                            .bold()
                    }
                    HStack {
                        Text("Total Threads:")
                        Spacer()
                        Text("\(viewModel.threads.count)")
                            .bold()
                    }
                    if viewModel.exportOptions.enableChunking {
                        HStack {
                            Text("Est. Chunks:")
                            Spacer()
                            Text("\(estimatedChunks)")
                                .bold()
                                .foregroundColor(.blue)
                        }
                    }
                    HStack {
                        Text("Est. Files:")
                        Spacer()
                        Text("\(estimatedFiles)")
                            .bold()
                            .foregroundColor(.green)
                    }
                }
            }
            .formStyle(.grouped)

            // MARK: - Action Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Reset to Defaults") {
                    viewModel.exportOptions = ExportEngine.ExportOptions()
                }

                Button("Preview Export") {
                    showingPreview = true
                }
                .buttonStyle(.bordered)

                Button("Export...") {
                    dismiss()
                    showingExportPicker = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 600, height: 700)
        .sheet(isPresented: $showingPresets) {
            ExportPresetsView(viewModel: viewModel, isPresented: $showingPresets)
        }
        .sheet(isPresented: $showingPreview) {
            ExportPreviewView(viewModel: viewModel, showingExportPicker: $showingExportPicker)
        }
    }

    // MARK: - Computed Properties

    private var estimatedChunks: Int {
        guard viewModel.exportOptions.enableChunking else { return 0 }
        let chunkSize = viewModel.exportOptions.chunkSize
        return viewModel.emails.reduce(0) { total, email in
            let textLength = email.body.count
            return total + max(1, textLength / chunkSize)
        }
    }

    private var estimatedFiles: Int {
        var count = 0

        switch viewModel.exportOptions.format {
        case .onePerEmail:
            count = viewModel.exportOptions.enableChunking ? estimatedChunks : viewModel.emails.count
        case .onePerThread:
            count = viewModel.threads.count
        case .both:
            count = (viewModel.exportOptions.enableChunking ? estimatedChunks : viewModel.emails.count) + viewModel.threads.count
        }

        if viewModel.exportOptions.includeMetadata {
            count *= 2 // Each text file gets a JSON metadata file
        }

        return count + 1 // +1 for INDEX.txt
    }
}

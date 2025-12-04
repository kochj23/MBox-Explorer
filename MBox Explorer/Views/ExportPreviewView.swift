//
//  ExportPreviewView.swift
//  MBox Explorer
//
//  Export preview showing sample output and statistics
//

import SwiftUI

struct ExportPreviewView: View {
    @ObservedObject var viewModel: MboxViewModel
    @Binding var showingExportPicker: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Export Preview")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            // Preview content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Sample email preview
                    if let firstEmail = viewModel.filteredEmails.first {
                        GroupBox("Sample Cleaned Email") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("From:").foregroundColor(.secondary).frame(width: 60, alignment: .leading)
                                    Text(firstEmail.from)
                                }
                                HStack {
                                    Text("Subject:").foregroundColor(.secondary).frame(width: 60, alignment: .leading)
                                    Text(firstEmail.subject)
                                }
                                Divider()
                                Text(firstEmail.cleanBody.prefix(500) + "...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            }
                            .padding()
                        }
                    }

                    // Statistics
                    GroupBox("Export Statistics") {
                        VStack(alignment: .leading, spacing: 8) {
                            ExportStatRow(label: "Total Emails", value: "\(viewModel.filteredEmails.count)")
                            ExportStatRow(label: "Total Threads", value: "\(viewModel.threads.count)")
                            ExportStatRow(label: "Estimated Files", value: "\(estimatedFileCount)")
                            ExportStatRow(label: "Estimated Size", value: estimatedSize)
                        }
                        .padding()
                    }

                    // Chunk preview
                    if viewModel.exportOptions.enableChunking,
                       let firstEmail = viewModel.filteredEmails.first,
                       firstEmail.body.count > viewModel.exportOptions.chunkSize {
                        GroupBox("Chunking Example") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("This email will be split into multiple chunks:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                let chunks = TextProcessor.chunkText(firstEmail.cleanBody,
                                    maxLength: viewModel.exportOptions.chunkSize)
                                ForEach(0..<min(3, chunks.count), id: \.self) { i in
                                    HStack {
                                        Text("Chunk \(i+1):")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("\(chunks[i].count) characters")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                }
                                if chunks.count > 3 {
                                    Text("... and \(chunks.count - 3) more chunks")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                        }
                    }

                    // Export options summary
                    GroupBox("Export Options") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Format:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatString)
                            }
                            HStack {
                                Text("Clean Text:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(viewModel.exportOptions.cleanText ? "Yes" : "No")
                            }
                            HStack {
                                Text("Chunking:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(viewModel.exportOptions.enableChunking ?
                                     "Yes (\(viewModel.exportOptions.chunkSize) chars)" : "No")
                            }
                            HStack {
                                Text("Metadata:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(viewModel.exportOptions.includeMetadata ? "Yes" : "No")
                            }
                        }
                        .font(.caption)
                        .padding()
                    }
                }
                .padding()
            }

            // Footer buttons
            HStack {
                Button("Back to Settings") {
                    dismiss()
                }

                Spacer()

                Button("Looks Good - Export Now") {
                    dismiss()
                    showingExportPicker = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 600, height: 700)
    }

    private var formatString: String {
        switch viewModel.exportOptions.format {
        case .onePerEmail: return "Per Email"
        case .onePerThread: return "Per Thread"
        case .both: return "Both"
        }
    }

    private var estimatedFileCount: Int {
        var count = 0
        switch viewModel.exportOptions.format {
        case .onePerEmail:
            count = viewModel.filteredEmails.count
        case .onePerThread:
            count = viewModel.threads.count
        case .both:
            count = viewModel.filteredEmails.count + viewModel.threads.count
        }

        if viewModel.exportOptions.includeMetadata {
            count *= 2
        }
        return count + 1 // +1 for INDEX.txt
    }

    private var estimatedSize: String {
        let totalChars = viewModel.filteredEmails.reduce(0) { $0 + $1.body.count }
        let bytes = totalChars * 2 // Rough estimate
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Export Stat Row

struct ExportStatRow: View {
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

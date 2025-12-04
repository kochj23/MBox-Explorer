//
//  AttachmentsView.swift
//  MBox Explorer
//
//  Dedicated view for browsing and managing attachments
//

import SwiftUI

struct AttachmentsView: View {
    @ObservedObject var viewModel: MboxViewModel
    @State private var selectedCategory: AttachmentManager.AttachmentCategory = .all
    @State private var searchText: String = ""
    @State private var sortField: AttachmentManager.SortField = .filename
    @State private var sortOrder: AttachmentManager.SortOrder = .ascending
    @State private var selectedAttachments: Set<UUID> = []
    @State private var showingExportDialog = false

    var allAttachments: [AttachmentManager.ExtendedAttachmentInfo] {
        AttachmentManager.extractAllAttachments(from: viewModel.emails)
    }

    var filteredAttachments: [AttachmentManager.ExtendedAttachmentInfo] {
        let filtered = AttachmentManager.filter(allAttachments, by: selectedCategory, searchText: searchText)
        return AttachmentManager.sort(filtered, by: sortField, order: sortOrder)
    }

    var statistics: AttachmentManager.AttachmentStatistics {
        AttachmentManager.getStatistics(from: filteredAttachments)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search and category filter
            VStack(spacing: 12) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search attachments...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Category picker
                Picker("Category", selection: $selectedCategory) {
                    ForEach(AttachmentManager.AttachmentCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)

                // Statistics bar
                HStack {
                    Label("\(statistics.totalCount) attachments", systemImage: "paperclip")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(statistics.totalSizeFormatted)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !selectedAttachments.isEmpty {
                        Divider()
                            .frame(height: 16)

                        Text("\(selectedAttachments.count) selected")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .bold()

                        Button {
                            showingExportDialog = true
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding()

            // Column headers
            AttachmentColumnHeaders(sortField: $sortField, sortOrder: $sortOrder)

            // Attachments list
            if filteredAttachments.isEmpty {
                ContentUnavailableView(
                    "No Attachments",
                    systemImage: "paperclip.slash",
                    description: Text(searchText.isEmpty ? "No attachments found in loaded emails" : "No attachments match your search")
                )
            } else {
                List(selection: Binding<AttachmentManager.ExtendedAttachmentInfo.ID?>(
                    get: { nil },
                    set: { _ in }
                )) {
                    ForEach(filteredAttachments) { info in
                        AttachmentRow(info: info, isSelected: selectedAttachments.contains(info.id))
                            .onTapGesture {
                                toggleSelection(info.id)
                            }
                            .contextMenu {
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(info.filename, forType: .string)
                                } label: {
                                    Label("Copy Filename", systemImage: "doc.on.doc")
                                }

                                Button {
                                    // Jump to email containing this attachment
                                    viewModel.selectedEmail = info.email
                                } label: {
                                    Label("Show in Email", systemImage: "envelope")
                                }

                                Divider()

                                Button {
                                    exportSingleAttachment(info)
                                } label: {
                                    Label("Export...", systemImage: "square.and.arrow.up")
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showingExportDialog) {
            ExportAttachmentsDialog(
                count: selectedAttachments.count,
                isPresented: $showingExportDialog,
                onExport: { exportSelectedAttachments() }
            )
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedAttachments.contains(id) {
            selectedAttachments.remove(id)
        } else {
            selectedAttachments.insert(id)
        }
    }

    private func exportSelectedAttachments() {
        let panel = NSOpenPanel()
        panel.canCreateDirectories = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose folder to export attachments"
        panel.prompt = "Export"

        panel.begin { (response: NSApplication.ModalResponse) in
            if response == .OK, let url = panel.url {
                let attachmentsToExport = filteredAttachments.filter { selectedAttachments.contains($0.id) }
                do {
                    try AttachmentManager.exportAttachments(attachmentsToExport, to: url)
                    selectedAttachments.removeAll()
                    viewModel.statusMessage = "Exported \(attachmentsToExport.count) attachments"
                } catch {
                    viewModel.statusMessage = "Error exporting attachments: \(error.localizedDescription)"
                }
            }
        }
    }

    private func exportSingleAttachment(_ info: AttachmentManager.ExtendedAttachmentInfo) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(info.filename).txt"
        panel.message = "Export attachment info"

        panel.begin { (response: NSApplication.ModalResponse) in
            if response == .OK, let url = panel.url {
                do {
                    var content = "Attachment Information\n"
                    content += "=====================\n\n"
                    content += "Filename: \(info.filename)\n"
                    content += "Content Type: \(info.contentType)\n"
                    content += "Size: \(info.displaySize)\n\n"
                    content += "From Email:\n"
                    content += "  Subject: \(info.emailSubject)\n"
                    content += "  Sender: \(info.emailFrom)\n"
                    if let date = info.emailDate {
                        content += "  Date: \(date.formatted())\n"
                    }
                    content += "\nNote: Actual attachment data is not stored in MBOX metadata.\n"
                    content += "This file contains information about the attachment only.\n"

                    try content.write(to: url, atomically: true, encoding: .utf8)
                    viewModel.statusMessage = "Exported info for \(info.filename)"
                } catch {
                    viewModel.statusMessage = "Error exporting: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct AttachmentColumnHeaders: View {
    @Binding var sortField: AttachmentManager.SortField
    @Binding var sortOrder: AttachmentManager.SortOrder

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox column
            Text("")
                .frame(width: 30)

            // Icon column
            Text("")
                .frame(width: 30)

            // Filename
            Button {
                toggleSort(.filename)
            } label: {
                HStack(spacing: 4) {
                    Text("Filename")
                        .font(.caption)
                        .bold()
                    if sortField == .filename {
                        Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Type
            Button {
                toggleSort(.type)
            } label: {
                HStack(spacing: 4) {
                    Text("Type")
                        .font(.caption)
                        .bold()
                    if sortField == .type {
                        Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                }
                .frame(width: 80, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Size
            Button {
                toggleSort(.size)
            } label: {
                HStack(spacing: 4) {
                    Text("Size")
                        .font(.caption)
                        .bold()
                    if sortField == .size {
                        Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                }
                .frame(width: 80, alignment: .trailing)
            }
            .buttonStyle(.plain)

            // Email/Date
            Button {
                toggleSort(.date)
            } label: {
                HStack(spacing: 4) {
                    Text("Email / Date")
                        .font(.caption)
                        .bold()
                    if sortField == .date {
                        Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                }
                .frame(width: 200, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }

    private func toggleSort(_ field: AttachmentManager.SortField) {
        if sortField == field {
            sortOrder = sortOrder == .ascending ? .descending : .ascending
        } else {
            sortField = field
            sortOrder = .ascending
        }
    }
}

struct AttachmentRow: View {
    let info: AttachmentManager.ExtendedAttachmentInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .blue : .secondary)
                .frame(width: 30)

            // Icon
            Image(systemName: info.categoryIcon)
                .foregroundColor(.blue)
                .frame(width: 30)

            // Filename
            VStack(alignment: .leading, spacing: 2) {
                Text(info.filename)
                    .font(.body)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Type
            Text(info.fileExtension.uppercased())
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            // Size
            Text(info.displaySize)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)

            // Email info
            VStack(alignment: .leading, spacing: 2) {
                Text(info.emailSubject)
                    .font(.caption)
                    .lineLimit(1)
                Text(info.emailFrom)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 200, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

struct ExportAttachmentsDialog: View {
    let count: Int
    @Binding var isPresented: Bool
    let onExport: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Export Attachments")
                .font(.title2)
                .bold()

            Text("Export \(count) selected attachments to a folder")
                .font(.body)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Export...") {
                    isPresented = false
                    onExport()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

//
//  BatchOperationsView.swift
//  MBox Explorer
//
//  Toolbar and UI for batch email operations
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import SwiftUI

struct BatchOperationsToolbar: View {
    @Binding var selectedEmails: Set<UUID>
    @ObservedObject var viewModel: MboxViewModel
    @State private var showingExportOptions = false
    @State private var showingTagSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var operationInProgress = false
    @State private var operationProgress: Double = 0

    var selectedCount: Int {
        selectedEmails.count
    }

    var body: some View {
        HStack(spacing: 16) {
            // Selection info
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)

                Text("\(selectedCount) selected")
                    .fontWeight(.medium)

                Button("Clear") {
                    selectedEmails.removeAll()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            Divider()
                .frame(height: 20)

            // Quick actions
            Group {
                BatchButton(icon: "tag", label: "Tag") {
                    showingTagSheet = true
                }

                BatchButton(icon: "star", label: "Star") {
                    starSelected()
                }

                BatchButton(icon: "square.and.arrow.up", label: "Export") {
                    showingExportOptions = true
                }

                BatchButton(icon: "doc.on.doc", label: "Copy") {
                    copyToClipboard()
                }

                BatchButton(icon: "printer", label: "Print") {
                    printSelected()
                }
            }

            Divider()
                .frame(height: 20)

            // AI actions
            Group {
                BatchButton(icon: "brain", label: "Summarize") {
                    summarizeSelected()
                }

                BatchButton(icon: "list.bullet.clipboard", label: "Actions") {
                    extractActions()
                }
            }

            Spacer()

            // Delete
            Button(action: {
                showingDeleteConfirmation = true
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("Remove from view")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.1))
        .overlay(
            Group {
                if operationInProgress {
                    ProgressView(value: operationProgress)
                        .progressViewStyle(.linear)
                }
            },
            alignment: .bottom
        )
        .sheet(isPresented: $showingExportOptions) {
            BatchExportSheet(emails: getSelectedEmails())
        }
        .sheet(isPresented: $showingTagSheet) {
            BatchTagView(emails: getSelectedEmails())
        }
        .alert("Remove Emails?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                removeSelected()
            }
        } message: {
            Text("Remove \(selectedCount) emails from the current view? This doesn't delete the original MBOX file.")
        }
    }

    // MARK: - Actions

    private func getSelectedEmails() -> [Email] {
        viewModel.emails.filter { selectedEmails.contains($0.id) }
    }

    private func starSelected() {
        for email in getSelectedEmails() {
            TagManager.shared.toggleFavorite(email.id)
        }
    }

    private func copyToClipboard() {
        let emails = getSelectedEmails()
        var text = ""

        for email in emails {
            text += "Subject: \(email.subject)\n"
            text += "From: \(email.from)\n"
            text += "Date: \(email.date)\n"
            text += "\n\(email.body)\n"
            text += "\n---\n\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func printSelected() {
        let emails = getSelectedEmails()
        var html = "<html><body>"

        for email in emails {
            html += """
            <div style="page-break-after: always; margin-bottom: 20px;">
                <h2>\(email.subject)</h2>
                <p><strong>From:</strong> \(email.from)</p>
                <p><strong>To:</strong> \(email.to ?? "")</p>
                <p><strong>Date:</strong> \(email.date)</p>
                <hr>
                <div>\(email.body.replacingOccurrences(of: "\n", with: "<br>"))</div>
            </div>
            """
        }

        html += "</body></html>"

        // Create print operation
        if let data = html.data(using: .utf8),
           let attributedString = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {

            let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
            printView.textStorage?.setAttributedString(attributedString)

            let printInfo = NSPrintInfo.shared
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .automatic

            let printOperation = NSPrintOperation(view: printView, printInfo: printInfo)
            printOperation.run()
        }
    }

    private func summarizeSelected() {
        Task {
            await MainActor.run {
                operationInProgress = true
                operationProgress = 0
            }

            let emails = getSelectedEmails()
            var summaries: [String] = []

            for (index, email) in emails.enumerated() {
                let summary = await LocalLLM.shared.summarize(content: email.body)
                summaries.append("**\(email.subject)**\n\(summary)")

                await MainActor.run {
                    operationProgress = Double(index + 1) / Double(emails.count)
                }
            }

            let combinedSummary = summaries.joined(separator: "\n\n---\n\n")

            // Copy to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(combinedSummary, forType: .string)

            await MainActor.run {
                operationInProgress = false
            }
        }
    }

    private func extractActions() {
        Task {
            await MainActor.run {
                operationInProgress = true
                operationProgress = 0
            }

            let emails = getSelectedEmails()
            var allActions: [ActionItem] = []

            for (index, email) in emails.enumerated() {
                if let items = try? await ActionItemExtractor.shared.extractActionItems(from: email) {
                    allActions.append(contentsOf: items)
                }

                await MainActor.run {
                    operationProgress = Double(index + 1) / Double(emails.count)
                }
            }

            // Export as CSV
            let csv = ActionItemExtractor.shared.exportToCSV(items: allActions)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(csv, forType: .string)

            await MainActor.run {
                operationInProgress = false
            }
        }
    }

    private func removeSelected() {
        viewModel.emails.removeAll { selectedEmails.contains($0.id) }
        selectedEmails.removeAll()
    }
}

// MARK: - Batch Button

struct BatchButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.caption2)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 50)
    }
}

// MARK: - Batch Export View

struct BatchExportSheet: View {
    let emails: [Email]
    @Environment(\.dismiss) private var dismiss

    @State private var exportFormat: BatchExportFormat = .pdf
    @State private var includeAttachments = true
    @State private var includeHeaders = false
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Export \(emails.count) Emails")
                .font(.headline)

            Form {
                Picker("Format", selection: $exportFormat) {
                    ForEach(BatchExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }

                Toggle("Include Attachments", isOn: $includeAttachments)
                Toggle("Include Headers", isOn: $includeHeaders)
            }
            .frame(width: 300)

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Export") {
                    exportEmails()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func exportEmails() {
        isExporting = true

        let panel = NSSavePanel()
        panel.title = "Export Emails"
        panel.nameFieldStringValue = "emails-export.\(exportFormat.fileExtension)"

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                isExporting = false
                return
            }

            Task {
                do {
                    let exporter = RichExporter()
                    switch exportFormat {
                    case .pdf:
                        try exporter.exportToPDF(emails, to: url)
                    case .html:
                        try exporter.exportToHTML(emails, to: url)
                    case .markdown, .eml, .csv:
                        // For other formats, use CSV exporter
                        try CSVExporter.exportToCSV(emails: emails, to: url)
                    }
                    await MainActor.run {
                        isExporting = false
                        dismiss()
                    }
                } catch {
                    print("Export failed: \(error)")
                    await MainActor.run {
                        isExporting = false
                    }
                }
            }
        }
    }
}

enum BatchExportFormat: String, CaseIterable {
    case pdf = "PDF"
    case html = "HTML"
    case markdown = "Markdown"
    case eml = "EML"
    case csv = "CSV"

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .html: return "html"
        case .markdown: return "md"
        case .eml: return "eml"
        case .csv: return "csv"
        }
    }
}

// MARK: - Batch Tag View

struct BatchTagView: View {
    let emails: [Email]
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tagManager = TagManager.shared

    @State private var selectedTagIds: Set<UUID> = []
    @State private var newTagName = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Tag \(emails.count) Emails")
                .font(.headline)

            // Existing tags
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                    ForEach(tagManager.tags) { tag in
                        TagChip(
                            name: tag.name,
                            isSelected: selectedTagIds.contains(tag.id),
                            action: {
                                if selectedTagIds.contains(tag.id) {
                                    selectedTagIds.remove(tag.id)
                                } else {
                                    selectedTagIds.insert(tag.id)
                                }
                            }
                        )
                    }
                }
            }
            .frame(height: 150)

            // New tag
            HStack {
                TextField("New tag...", text: $newTagName)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    guard !newTagName.isEmpty else { return }
                    let newTag = tagManager.createTag(name: newTagName, color: .blue)
                    selectedTagIds.insert(newTag.id)
                    newTagName = ""
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Apply Tags") {
                    applyTags()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
    }

    private func applyTags() {
        let selectedTags = tagManager.tags.filter { selectedTagIds.contains($0.id) }
        for email in emails {
            for tag in selectedTags {
                tagManager.addTag(tag, to: email.id)
            }
        }
        dismiss()
    }
}

struct TagChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                }
                Text(name)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

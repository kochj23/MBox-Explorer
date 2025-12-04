//
//  EmailDetailView.swift
//  MBox Explorer
//
//  Email preview/detail pane
//

import SwiftUI

struct EmailDetailView: View {
    @ObservedObject var viewModel: MboxViewModel
    @State private var showQuotedText = false
    @State private var showRawSource = false
    @State private var highlightEnabled = true

    var body: some View {
        if let email = viewModel.selectedEmail {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Group {
                            if !viewModel.searchText.isEmpty && highlightEnabled {
                                Text.highlighted(
                                    email.subject,
                                    searchTerms: [viewModel.searchText]
                                )
                                .font(.title2)
                                .bold()
                            } else {
                                Text(email.subject)
                                    .font(.title2)
                                    .bold()
                            }
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("From:")
                                        .foregroundColor(.secondary)
                                        .frame(width: 50, alignment: .leading)
                                    Text(email.from)
                                        .textSelection(.enabled)
                                }

                                if let to = email.to {
                                    HStack {
                                        Text("To:")
                                            .foregroundColor(.secondary)
                                            .frame(width: 50, alignment: .leading)
                                        Text(to)
                                            .textSelection(.enabled)
                                    }
                                }

                                HStack {
                                    Text("Date:")
                                        .foregroundColor(.secondary)
                                        .frame(width: 50, alignment: .leading)
                                    Text(email.displayDate)
                                }
                            }
                            Spacer()
                        }
                        .font(.subheadline)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)

                    // Attachments
                    if email.hasAttachments {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "paperclip")
                                    .foregroundColor(.secondary)
                                Text("Attachments (\(email.attachmentCount))")
                                    .font(.headline)
                            }

                            ForEach(email.attachments ?? [], id: \.filename) { attachment in
                                HStack(spacing: 12) {
                                    Image(systemName: attachment.icon)
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                        .frame(width: 40)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(attachment.filename)
                                            .font(.subheadline)
                                        HStack(spacing: 8) {
                                            Text(attachment.contentType)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            if attachment.size != nil {
                                                Text("•")
                                                    .foregroundColor(.secondary)
                                                Text(attachment.displaySize)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(12)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                    }

                    // Body controls
                    HStack {
                        Toggle("Show Quoted Text", isOn: $showQuotedText)
                            .toggleStyle(.switch)
                            .controlSize(.small)

                        if !viewModel.searchText.isEmpty {
                            Toggle("Highlight Search", isOn: $highlightEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }

                        Spacer()

                        if !viewModel.searchText.isEmpty && highlightEnabled {
                            let matchCount = TextHighlighter.countMatches(
                                in: displayedBody(for: email),
                                searchTerms: [viewModel.searchText]
                            )
                            Text("\(matchCount) matches")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Button(showRawSource ? "Show Formatted" : "Show Raw") {
                            showRawSource.toggle()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    .padding(.horizontal)

                    // Body
                    Group {
                        if !viewModel.searchText.isEmpty && highlightEnabled && !showRawSource {
                            Text.highlighted(
                                displayedBody(for: email),
                                searchTerms: [viewModel.searchText]
                            )
                            .font(.body)
                            .textSelection(.enabled)
                        } else {
                            Text(displayedBody(for: email))
                                .font(showRawSource ? .system(.caption, design: .monospaced) : .body)
                                .textSelection(.enabled)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(showRawSource ? Color(NSColor.textBackgroundColor) : Color.clear)
                    .cornerRadius(showRawSource ? 4 : 0)

                    // Metadata
                    if let messageId = email.messageId {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Message ID")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(messageId)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItemGroup {
                    Menu {
                        ForEach(viewModel.filteredEmails.filter { $0.id != email.id }.prefix(10)) { otherEmail in
                            Button {
                                viewModel.comparisonEmail = otherEmail
                                viewModel.showingEmailComparison = true
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(otherEmail.subject)
                                    Text(otherEmail.from)
                                        .font(.caption)
                                }
                            }
                        }
                    } label: {
                        Label("Compare", systemImage: "arrow.left.arrow.right")
                    }
                    .disabled(viewModel.filteredEmails.count < 2)

                    Button {
                        exportCurrentEmail()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "No Email Selected",
                systemImage: "envelope",
                description: Text("Select an email from the list to view its contents")
            )
        }
    }

    private func displayedBody(for email: Email) -> String {
        if showRawSource {
            return email.body
        }

        if showQuotedText {
            return email.cleanBody
        }

        // Remove quoted text (lines starting with >)
        let lines = email.cleanBody.components(separatedBy: "\n")
        let filtered = lines.filter { !$0.hasPrefix(">") }
        return filtered.joined(separator: "\n")
    }

    private func exportCurrentEmail() {
        guard let email = viewModel.selectedEmail else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = email.safeFilename
        panel.allowedContentTypes = [.plainText]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? email.cleanBody.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

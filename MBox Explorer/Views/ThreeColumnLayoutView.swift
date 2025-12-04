//
//  ThreeColumnLayoutView.swift
//  MBox Explorer
//
//  Optional 3-column layout with email preview pane
//

import SwiftUI

struct ThreeColumnLayoutView: View {
    @ObservedObject var viewModel: MboxViewModel
    @Binding var selectedView: SidebarItem
    @Binding var showingFilePicker: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var previewWidth: CGFloat = 400

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Column 1: Sidebar
                SidebarView(
                    viewModel: viewModel,
                    selectedView: $selectedView,
                    showingFilePicker: $showingFilePicker
                )
                .frame(width: 250)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Column 2: Email List
                if selectedView == .attachments {
                    AttachmentsView(viewModel: viewModel)
                        .frame(width: max(300, geometry.size.width - 250 - previewWidth - 2))
                } else if selectedView == .analytics {
                    AnalyticsView(viewModel: viewModel)
                        .frame(width: max(300, geometry.size.width - 250 - previewWidth - 2))
                } else if selectedView == .operations {
                    MboxOperationsView(viewModel: viewModel)
                        .frame(width: max(300, geometry.size.width - 250 - previewWidth - 2))
                } else {
                    EmailListView(
                        viewModel: viewModel,
                        selectedView: selectedView
                    )
                    .frame(width: max(300, geometry.size.width - 250 - previewWidth - 2))
                }

                Divider()

                // Column 3: Email Preview
                EmailPreviewPane(viewModel: viewModel, width: $previewWidth)
                    .frame(width: previewWidth)
            }
        }
    }
}

// MARK: - Email Preview Pane

struct EmailPreviewPane: View {
    @ObservedObject var viewModel: MboxViewModel
    @Binding var width: CGFloat
    @State private var showQuotedText = false
    @State private var showRawSource = false
    @State private var highlightEnabled = true
    @State private var fontSize: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            HStack {
                Text("Preview")
                    .font(.headline)

                Spacer()

                // Font size controls
                HStack(spacing: 4) {
                    Button {
                        fontSize = max(10, fontSize - 1)
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .buttonStyle(.borderless)
                    .help("Decrease font size")

                    Text("\(Int(fontSize))pt")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 30)

                    Button {
                        fontSize = min(24, fontSize + 1)
                    } label: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .buttonStyle(.borderless)
                    .help("Increase font size")
                }

                // Width controls
                Menu {
                    Button("Narrow (300pt)") { width = 300 }
                    Button("Medium (400pt)") { width = 400 }
                    Button("Wide (500pt)") { width = 500 }
                    Button("Extra Wide (600pt)") { width = 600 }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .menuStyle(.borderlessButton)
                .help("Adjust preview width")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Preview content
            if let email = viewModel.selectedEmail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Compact header
                        VStack(alignment: .leading, spacing: 6) {
                            Text(email.subject)
                                .font(.system(size: fontSize + 2))
                                .bold()
                                .textSelection(.enabled)

                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("From:")
                                        .font(.system(size: fontSize - 2))
                                        .foregroundColor(.secondary)
                                        .frame(width: 45, alignment: .leading)

                                    Text(email.from)
                                        .font(.system(size: fontSize - 2))
                                        .textSelection(.enabled)
                                }

                                if let to = email.to {
                                    HStack(spacing: 6) {
                                        Text("To:")
                                            .font(.system(size: fontSize - 2))
                                            .foregroundColor(.secondary)
                                            .frame(width: 45, alignment: .leading)

                                        Text(to)
                                            .font(.system(size: fontSize - 2))
                                            .lineLimit(1)
                                            .textSelection(.enabled)
                                    }
                                }

                                HStack(spacing: 6) {
                                    Text("Date:")
                                        .font(.system(size: fontSize - 2))
                                        .foregroundColor(.secondary)
                                        .frame(width: 45, alignment: .leading)

                                    Text(email.displayDate)
                                        .font(.system(size: fontSize - 2))
                                }
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)

                        // Attachments (compact)
                        if email.hasAttachments {
                            HStack(spacing: 8) {
                                Image(systemName: "paperclip")
                                    .foregroundColor(.secondary)

                                Text("\(email.attachmentCount) attachment\(email.attachmentCount == 1 ? "" : "s")")
                                    .font(.system(size: fontSize - 2))
                                    .foregroundColor(.secondary)

                                Spacer()

                                Button {
                                    // Show attachments in detail view
                                } label: {
                                    Text("View")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                            .cornerRadius(6)
                        }

                        // View options (compact)
                        HStack(spacing: 12) {
                            Toggle(isOn: $showQuotedText) {
                                Text("Quoted")
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                            if !viewModel.searchText.isEmpty {
                                Toggle(isOn: $highlightEnabled) {
                                    Text("Highlight")
                                        .font(.caption)
                                }
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                            }

                            Toggle(isOn: $showRawSource) {
                                Text("Raw")
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        }
                        .padding(.horizontal)

                        Divider()

                        // Body
                        Group {
                            if !viewModel.searchText.isEmpty && highlightEnabled && !showRawSource {
                                Text.highlighted(
                                    displayedBody(for: email),
                                    searchTerms: [viewModel.searchText]
                                )
                                .font(.system(size: fontSize))
                                .textSelection(.enabled)
                            } else {
                                Text(displayedBody(for: email))
                                    .font(showRawSource ? .system(size: fontSize - 2, design: .monospaced) : .system(size: fontSize))
                                    .textSelection(.enabled)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "No Email Selected",
                    systemImage: "envelope",
                    description: Text("Select an email to preview")
                )
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
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
}

// MARK: - Layout Preference Manager

extension WindowStateManager {
    private static let layoutModeKey = "LayoutMode"

    enum LayoutMode: String, Codable {
        case standard = "Standard"
        case threeColumn = "Three Column"
    }

    func saveLayoutMode(_ mode: LayoutMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: Self.layoutModeKey)
    }

    func loadLayoutMode() -> LayoutMode {
        guard let rawValue = UserDefaults.standard.string(forKey: Self.layoutModeKey),
              let mode = LayoutMode(rawValue: rawValue) else {
            return .standard
        }
        return mode
    }
}

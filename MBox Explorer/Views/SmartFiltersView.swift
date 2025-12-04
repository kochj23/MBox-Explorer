//
//  SmartFiltersView.swift
//  MBox Explorer
//
//  Advanced filtering panel with smart filters
//

import SwiftUI

struct SmartFiltersView: View {
    @ObservedObject var viewModel: MboxViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var matchingCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Smart Filters")
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

            Divider()

            // Filter options
            Form {
                // MARK: - Content Filters
                Section("Content Filters") {
                    Toggle("Has Attachments", isOn: $viewModel.smartFilters.hasAttachments)
                    Toggle("Has No Attachments", isOn: $viewModel.smartFilters.hasNoAttachments)

                    Divider()

                    Toggle("Exclude Automated Emails", isOn: $viewModel.smartFilters.excludeAutomated)
                    Text("Filters out no-reply, automated notifications, and system emails")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - Size Filters
                Section("Message Size") {
                    Toggle("Filter by Length", isOn: $viewModel.smartFilters.enableLengthFilter)

                    if viewModel.smartFilters.enableLengthFilter {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Min Length:")
                                    .frame(width: 100, alignment: .leading)
                                TextField("Characters", value: $viewModel.smartFilters.minLength, formatter: NumberFormatter())
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                            }

                            HStack {
                                Text("Max Length:")
                                    .frame(width: 100, alignment: .leading)
                                TextField("Characters", value: $viewModel.smartFilters.maxLength, formatter: NumberFormatter())
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                            }
                        }
                        .padding(.leading)
                    }
                }

                // MARK: - Pattern Matching
                Section("Pattern Matching") {
                    Toggle("Use Regular Expression", isOn: $viewModel.smartFilters.useRegex)

                    if viewModel.smartFilters.useRegex {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Regex Pattern", text: $viewModel.smartFilters.regexPattern)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))

                            if !viewModel.smartFilters.regexPattern.isEmpty {
                                if viewModel.smartFilters.isValidRegex {
                                    Label("Valid regex pattern", systemImage: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                } else {
                                    Label("Invalid regex pattern", systemImage: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                            }

                            Text("Examples: @gmail\\.com$ (Gmail addresses), \\bERROR\\b (error messages)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading)
                    }
                }

                // MARK: - Thread Filters
                Section("Thread Filters") {
                    Toggle("Only Thread Roots", isOn: $viewModel.smartFilters.onlyThreadRoots)
                    Text("Shows only emails that started a conversation")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Only Replies", isOn: $viewModel.smartFilters.onlyReplies)
                    Text("Shows only emails that are replies to other messages")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - Results Preview
                Section("Results") {
                    HStack {
                        Text("Emails matching filters:")
                        Spacer()
                        Text("\(matchingCount)")
                            .bold()
                            .foregroundColor(.blue)
                    }

                    Button("Update Count") {
                        updateMatchingCount()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .formStyle(.grouped)

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                Button("Reset All") {
                    viewModel.smartFilters = SmartFilters()
                    Task { @MainActor in
                        viewModel.applyFilters()
                        updateMatchingCount()
                    }
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Apply Filters") {
                    Task { @MainActor in
                        viewModel.applyFilters()
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 550, height: 700)
        .onAppear {
            updateMatchingCount()
        }
    }

    private func updateMatchingCount() {
        matchingCount = viewModel.countMatchingSmartFilters()
    }
}

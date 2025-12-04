//
//  DuplicatesView.swift
//  MBox Explorer
//
//  Duplicate email detection and removal
//

import SwiftUI

struct DuplicatesView: View {
    @ObservedObject var viewModel: MboxViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var duplicates: [(String, [Email])] = []
    @State private var showingRemovalConfirmation = false
    @State private var removedCount = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Duplicate Emails")
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

            // Content
            if duplicates.isEmpty {
                VStack(spacing: 20) {
                    Spacer()

                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.green)

                    Text("No Duplicates Found")
                        .font(.title2)
                        .bold()

                    Text("All emails have unique Message-IDs")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                VStack(spacing: 0) {
                    // Summary
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Found \(duplicates.count) duplicate groups")
                                .font(.headline)
                            Text("Total duplicate emails: \(totalDuplicateCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))

                    Divider()

                    // Duplicate list
                    List {
                        ForEach(duplicates, id: \.0) { messageId, emails in
                            Section(header: HStack {
                                Text("Message-ID: \(messageId)")
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(emails.count) copies")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }) {
                                ForEach(emails) { email in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(email.subject)
                                            .font(.headline)
                                        HStack {
                                            Text(email.from)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(email.displayDate)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }

                    Divider()

                    // Action buttons
                    VStack(spacing: 12) {
                        Text("Remove Duplicates Options")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Button("Keep Oldest") {
                                removeDuplicates(keepFirst: true)
                            }
                            .buttonStyle(.bordered)
                            .help("Keep the earliest email in each duplicate group")

                            Button("Keep Newest") {
                                removeDuplicates(keepFirst: false)
                            }
                            .buttonStyle(.bordered)
                            .help("Keep the most recent email in each duplicate group")

                            Spacer()

                            Button("Cancel") {
                                dismiss()
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                }
            }
        }
        .frame(width: 700, height: 600)
        .onAppear {
            duplicates = viewModel.detectDuplicates()
        }
        .alert("Duplicates Removed", isPresented: $showingRemovalConfirmation) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Successfully removed \(removedCount) duplicate emails")
        }
    }

    private var totalDuplicateCount: Int {
        duplicates.reduce(0) { $0 + $1.1.count - 1 }
    }

    private func removeDuplicates(keepFirst: Bool) {
        removedCount = viewModel.removeDuplicates(keepFirst: keepFirst)
        duplicates = viewModel.detectDuplicates()
        if duplicates.isEmpty {
            showingRemovalConfirmation = true
        }
    }
}

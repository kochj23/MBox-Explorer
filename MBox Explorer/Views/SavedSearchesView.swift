//
//  SavedSearchesView.swift
//  MBox Explorer
//
//  View for managing saved searches
//

import SwiftUI

struct SavedSearchesView: View {
    @ObservedObject var searchManager: SearchHistoryManager
    @ObservedObject var viewModel: MboxViewModel
    @Binding var isPresented: Bool
    @State private var showingSaveDialog = false
    @State private var editingSearch: SavedSearch?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Saved Searches")
                    .font(.title2)
                    .bold()

                Spacer()

                Button {
                    showingSaveDialog = true
                } label: {
                    Label("Save Current", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Saved searches list
            if searchManager.savedSearches.isEmpty {
                ContentUnavailableView(
                    "No Saved Searches",
                    systemImage: "magnifyingglass",
                    description: Text("Save frequently used search queries for quick access")
                )
            } else {
                List {
                    ForEach(searchManager.savedSearches) { search in
                        SavedSearchRow(
                            search: search,
                            onApply: {
                                applySearch(search)
                                isPresented = false
                            },
                            onEdit: {
                                editingSearch = search
                            },
                            onDelete: {
                                searchManager.removeSearch(search)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Footer buttons
            HStack {
                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .sheet(isPresented: $showingSaveDialog) {
            SaveSearchDialog(
                searchManager: searchManager,
                viewModel: viewModel,
                isPresented: $showingSaveDialog
            )
        }
        .sheet(item: $editingSearch) { search in
            RenameSearchDialog(
                search: search,
                searchManager: searchManager,
                isPresented: Binding(
                    get: { editingSearch != nil },
                    set: { if !$0 { editingSearch = nil } }
                )
            )
        }
    }

    private func applySearch(_ search: SavedSearch) {
        viewModel.searchText = search.query
        viewModel.filterSender = search.filters.sender
        viewModel.startDate = search.filters.startDate
        viewModel.endDate = search.filters.endDate
        // Apply additional filters when implemented
    }
}

struct SavedSearchRow: View {
    let search: SavedSearch
    let onApply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(search.name)
                    .font(.headline)

                Text(searchDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                Text("Created \(search.createdDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    onApply()
                } label: {
                    Label("Apply", systemImage: "play.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
    }

    private var searchDescription: String {
        var parts: [String] = []

        if !search.query.isEmpty {
            parts.append("Search: \"\(search.query)\"")
        }

        if !search.filters.sender.isEmpty {
            parts.append("From: \(search.filters.sender)")
        }

        if search.filters.startDate != nil || search.filters.endDate != nil {
            parts.append("Date range applied")
        }

        if search.filters.hasAttachments {
            parts.append("Has attachments")
        }

        return parts.isEmpty ? "No filters" : parts.joined(separator: " • ")
    }
}

struct SaveSearchDialog: View {
    @ObservedObject var searchManager: SearchHistoryManager
    @ObservedObject var viewModel: MboxViewModel
    @Binding var isPresented: Bool
    @State private var searchName: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Save Current Search")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Text("Search Name")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("e.g., Q4 2024 Reports", text: $searchName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("This will save:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !viewModel.searchText.isEmpty {
                    Label("Search: \"\(viewModel.searchText)\"", systemImage: "magnifyingglass")
                        .font(.caption)
                }

                if !viewModel.filterSender.isEmpty {
                    Label("From: \(viewModel.filterSender)", systemImage: "person")
                        .font(.caption)
                }

                if viewModel.startDate != nil || viewModel.endDate != nil {
                    Label("Date range", systemImage: "calendar")
                        .font(.caption)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    let filters = SearchFilters(
                        sender: viewModel.filterSender,
                        startDate: viewModel.startDate,
                        endDate: viewModel.endDate
                    )
                    searchManager.saveSearch(name: searchName, query: viewModel.searchText, filters: filters)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(searchName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450)
    }
}

struct RenameSearchDialog: View {
    let search: SavedSearch
    @ObservedObject var searchManager: SearchHistoryManager
    @Binding var isPresented: Bool
    @State private var newName: String

    init(search: SavedSearch, searchManager: SearchHistoryManager, isPresented: Binding<Bool>) {
        self.search = search
        self.searchManager = searchManager
        self._isPresented = isPresented
        self._newName = State(initialValue: search.name)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Search")
                .font(.title2)
                .bold()

            TextField("Search name", text: $newName)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    searchManager.updateSearch(search, name: newName)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(newName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

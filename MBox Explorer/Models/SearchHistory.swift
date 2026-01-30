//
//  SearchHistory.swift
//  MBox Explorer
//
//  Track and manage search history
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation
import SwiftUI

class SearchHistory: ObservableObject {
    static let shared = SearchHistory()

    @Published var recentSearches: [SearchEntry] = []
    @Published var savedSearches: [SearchEntry] = []

    private let maxRecentSearches = 50
    private let userDefaultsKey = "SearchHistory"
    private let savedSearchesKey = "SavedSearches"

    init() {
        loadHistory()
    }

    // MARK: - Add Search

    func addSearch(_ query: String, type: SearchType = .keyword, resultCount: Int = 0) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let entry = SearchEntry(
            query: query,
            type: type,
            timestamp: Date(),
            resultCount: resultCount
        )

        // Remove duplicates
        recentSearches.removeAll { $0.query.lowercased() == query.lowercased() }

        // Add to front
        recentSearches.insert(entry, at: 0)

        // Trim to max size
        if recentSearches.count > maxRecentSearches {
            recentSearches = Array(recentSearches.prefix(maxRecentSearches))
        }

        saveHistory()
    }

    // MARK: - Save/Remove Search

    func saveSearch(_ entry: SearchEntry) {
        if !savedSearches.contains(where: { $0.query == entry.query }) {
            var saved = entry
            saved.isSaved = true
            savedSearches.insert(saved, at: 0)
            saveSavedSearches()
        }
    }

    func removeSavedSearch(_ entry: SearchEntry) {
        savedSearches.removeAll { $0.id == entry.id }
        saveSavedSearches()
    }

    func toggleSaved(_ entry: SearchEntry) {
        if entry.isSaved {
            removeSavedSearch(entry)
        } else {
            saveSearch(entry)
        }
    }

    // MARK: - Clear

    func clearRecent() {
        recentSearches.removeAll()
        saveHistory()
    }

    func removeRecent(_ entry: SearchEntry) {
        recentSearches.removeAll { $0.id == entry.id }
        saveHistory()
    }

    // MARK: - Persistence

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([SearchEntry].self, from: data) {
            recentSearches = decoded
        }

        if let data = UserDefaults.standard.data(forKey: savedSearchesKey),
           let decoded = try? JSONDecoder().decode([SearchEntry].self, from: data) {
            savedSearches = decoded
        }
    }

    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(recentSearches) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    private func saveSavedSearches() {
        if let encoded = try? JSONEncoder().encode(savedSearches) {
            UserDefaults.standard.set(encoded, forKey: savedSearchesKey)
        }
    }

    // MARK: - Suggestions

    func getSuggestions(for prefix: String) -> [SearchEntry] {
        let query = prefix.lowercased()
        let fromSaved = savedSearches.filter { $0.query.lowercased().hasPrefix(query) }
        let fromRecent = recentSearches.filter { $0.query.lowercased().hasPrefix(query) }

        // Combine, prioritizing saved
        var suggestions = fromSaved
        for entry in fromRecent {
            if !suggestions.contains(where: { $0.query.lowercased() == entry.query.lowercased() }) {
                suggestions.append(entry)
            }
        }

        return Array(suggestions.prefix(10))
    }
}

// MARK: - Models

struct SearchEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var query: String
    var type: SearchType
    var timestamp: Date
    var resultCount: Int
    var isSaved: Bool

    init(id: UUID = UUID(), query: String, type: SearchType = .keyword, timestamp: Date = Date(), resultCount: Int = 0, isSaved: Bool = false) {
        self.id = id
        self.query = query
        self.type = type
        self.timestamp = timestamp
        self.resultCount = resultCount
        self.isSaved = isSaved
    }

    var displayDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    static func == (lhs: SearchEntry, rhs: SearchEntry) -> Bool {
        lhs.id == rhs.id
    }
}

enum SearchType: String, Codable {
    case keyword = "Keyword"
    case semantic = "Semantic"
    case regex = "Regex"
    case natural = "Natural Language"

    var icon: String {
        switch self {
        case .keyword: return "magnifyingglass"
        case .semantic: return "brain"
        case .regex: return "chevron.left.forwardslash.chevron.right"
        case .natural: return "text.bubble"
        }
    }
}

// MARK: - Search History View

struct SearchHistoryView: View {
    @ObservedObject var history = SearchHistory.shared
    @Binding var searchText: String
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Search History")
                    .font(.headline)

                Spacer()

                if selectedTab == 0 && !history.recentSearches.isEmpty {
                    Button("Clear All") {
                        history.clearRecent()
                    }
                    .foregroundColor(.red)
                }
            }
            .padding()

            // Tabs
            Picker("", selection: $selectedTab) {
                Text("Recent").tag(0)
                Text("Saved (\(history.savedSearches.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider()
                .padding(.top)

            // Content
            if selectedTab == 0 {
                recentSearchesList
            } else {
                savedSearchesList
            }
        }
        .frame(width: 350, height: 400)
    }

    private var recentSearchesList: some View {
        Group {
            if history.recentSearches.isEmpty {
                emptyState(icon: "clock", message: "No recent searches")
            } else {
                List {
                    ForEach(history.recentSearches) { entry in
                        SearchEntryRow(entry: entry, onSelect: {
                            searchText = entry.query
                            onSelect(entry.query)
                            dismiss()
                        }, onToggleSave: {
                            history.toggleSaved(entry)
                        }, onDelete: {
                            history.removeRecent(entry)
                        })
                    }
                }
            }
        }
    }

    private var savedSearchesList: some View {
        Group {
            if history.savedSearches.isEmpty {
                emptyState(icon: "star", message: "No saved searches")
            } else {
                List {
                    ForEach(history.savedSearches) { entry in
                        SearchEntryRow(entry: entry, onSelect: {
                            searchText = entry.query
                            onSelect(entry.query)
                            dismiss()
                        }, onToggleSave: {
                            history.toggleSaved(entry)
                        }, onDelete: {
                            history.removeSavedSearch(entry)
                        })
                    }
                }
            }
        }
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(message)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SearchEntryRow: View {
    let entry: SearchEntry
    var onSelect: () -> Void
    var onToggleSave: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: entry.type.icon)
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.query)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(entry.displayDate)
                    if entry.resultCount > 0 {
                        Text("\(entry.resultCount) results")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onToggleSave) {
                Image(systemName: entry.isSaved ? "star.fill" : "star")
                    .foregroundColor(entry.isSaved ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Use Search", action: onSelect)
            Button(entry.isSaved ? "Remove from Saved" : "Save Search", action: onToggleSave)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

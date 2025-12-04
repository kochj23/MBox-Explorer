//
//  SearchHistoryManager.swift
//  MBox Explorer
//
//  Manages search history and saved searches
//

import Foundation

class SearchHistoryManager: ObservableObject {
    static let shared = SearchHistoryManager()

    private let historyKey = "SearchHistory"
    private let savedSearchesKey = "SavedSearches"
    private let maxHistoryItems = 20

    @Published var searchHistory: [SearchHistoryItem] = []
    @Published var savedSearches: [SavedSearch] = []

    init() {
        loadHistory()
        loadSavedSearches()
    }

    // MARK: - Search History

    func addToHistory(_ query: String, filters: SearchFilters) {
        // Don't add empty searches
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty || filters.hasActiveFilters else { return }

        // Remove if already exists
        searchHistory.removeAll { $0.query == query && $0.filters == filters }

        // Add to beginning
        let item = SearchHistoryItem(query: query, filters: filters, timestamp: Date())
        searchHistory.insert(item, at: 0)

        // Limit size
        if searchHistory.count > maxHistoryItems {
            searchHistory = Array(searchHistory.prefix(maxHistoryItems))
        }

        saveHistory()
    }

    func clearHistory() {
        searchHistory.removeAll()
        saveHistory()
    }

    func removeFromHistory(_ item: SearchHistoryItem) {
        searchHistory.removeAll { $0.id == item.id }
        saveHistory()
    }

    // MARK: - Saved Searches

    func saveSearch(name: String, query: String, filters: SearchFilters) {
        let search = SavedSearch(name: name, query: query, filters: filters)
        savedSearches.append(search)
        saveSavedSearches()
    }

    func removeSearch(_ search: SavedSearch) {
        savedSearches.removeAll { $0.id == search.id }
        saveSavedSearches()
    }

    func updateSearch(_ search: SavedSearch, name: String) {
        if let index = savedSearches.firstIndex(where: { $0.id == search.id }) {
            savedSearches[index].name = name
            saveSavedSearches()
        }
    }

    // MARK: - Persistence

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let items = try? JSONDecoder().decode([SearchHistoryItem].self, from: data) {
            searchHistory = items
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(searchHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func loadSavedSearches() {
        if let data = UserDefaults.standard.data(forKey: savedSearchesKey),
           let searches = try? JSONDecoder().decode([SavedSearch].self, from: data) {
            savedSearches = searches
        }
    }

    private func saveSavedSearches() {
        if let data = try? JSONEncoder().encode(savedSearches) {
            UserDefaults.standard.set(data, forKey: savedSearchesKey)
        }
    }
}

// MARK: - Models

struct SearchHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let query: String
    let filters: SearchFilters
    let timestamp: Date

    init(query: String, filters: SearchFilters, timestamp: Date) {
        self.id = UUID()
        self.query = query
        self.filters = filters
        self.timestamp = timestamp
    }

    var displayText: String {
        var parts: [String] = []

        if !query.isEmpty {
            parts.append("\"\(query)\"")
        }

        if !filters.sender.isEmpty {
            parts.append("from: \(filters.sender)")
        }

        if filters.startDate != nil || filters.endDate != nil {
            parts.append("date filtered")
        }

        if filters.hasAttachments {
            parts.append("has attachments")
        }

        return parts.isEmpty ? "Empty search" : parts.joined(separator: " • ")
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

struct SavedSearch: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let query: String
    let filters: SearchFilters
    let createdDate: Date

    init(name: String, query: String, filters: SearchFilters) {
        self.id = UUID()
        self.name = name
        self.query = query
        self.filters = filters
        self.createdDate = Date()
    }
}

struct SearchFilters: Codable, Equatable {
    var sender: String
    var startDate: Date?
    var endDate: Date?
    var hasAttachments: Bool
    var minSize: Int?
    var maxSize: Int?
    var domain: String

    init(sender: String = "", startDate: Date? = nil, endDate: Date? = nil,
         hasAttachments: Bool = false, minSize: Int? = nil, maxSize: Int? = nil, domain: String = "") {
        self.sender = sender
        self.startDate = startDate
        self.endDate = endDate
        self.hasAttachments = hasAttachments
        self.minSize = minSize
        self.maxSize = maxSize
        self.domain = domain
    }

    var hasActiveFilters: Bool {
        !sender.isEmpty || startDate != nil || endDate != nil || hasAttachments ||
        minSize != nil || maxSize != nil || !domain.isEmpty
    }
}

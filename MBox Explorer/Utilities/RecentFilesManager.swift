//
//  RecentFilesManager.swift
//  MBox Explorer
//
//  Manages recently opened MBOX files
//

import Foundation

class RecentFilesManager {
    static let shared = RecentFilesManager()

    private let maxRecentFiles = 10
    private let recentFilesKey = "RecentMBOXFiles"

    private init() {}

    /// Get list of recent file URLs
    var recentFiles: [URL] {
        guard let data = UserDefaults.standard.data(forKey: recentFilesKey),
              let bookmarks = try? JSONDecoder().decode([Data].self, from: data) else {
            return []
        }

        return bookmarks.compactMap { bookmark -> URL? in
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark,
                                     options: .withSecurityScope,
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &isStale),
                  !isStale,
                  FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            return url
        }
    }

    /// Add a file to recent files list
    func addRecentFile(_ url: URL) {
        // Create security-scoped bookmark
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) else {
            return
        }

        // Get existing bookmarks
        var bookmarks: [Data] = []
        if let data = UserDefaults.standard.data(forKey: recentFilesKey),
           let existing = try? JSONDecoder().decode([Data].self, from: data) {
            bookmarks = existing
        }

        // Remove if already exists (will re-add at top)
        bookmarks.removeAll { existingBookmark in
            var isStale = false
            guard let existingURL = try? URL(resolvingBookmarkData: existingBookmark,
                                             options: .withSecurityScope,
                                             relativeTo: nil,
                                             bookmarkDataIsStale: &isStale) else {
                return false
            }
            return existingURL.path == url.path
        }

        // Add to beginning
        bookmarks.insert(bookmark, at: 0)

        // Keep only max number
        if bookmarks.count > maxRecentFiles {
            bookmarks = Array(bookmarks.prefix(maxRecentFiles))
        }

        // Save
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: recentFilesKey)
        }
    }

    /// Clear all recent files
    func clearRecentFiles() {
        UserDefaults.standard.removeObject(forKey: recentFilesKey)
    }
}

//
//  RecentFilesManager.swift
//  MBox Explorer
//
//  Manages recently opened MBOX files
//

import Foundation

#if DEBUG
import os.log
#endif

class RecentFilesManager {
    static let shared = RecentFilesManager()

    private let maxRecentFiles = 10
    private let recentFilesKey = "RecentMBOXFiles"

    private init() {}

    /// Get list of recent file URLs
    var recentFiles: [URL] {
        #if DEBUG
        DebugLogger.shared.debug("RecentFilesManager.recentFiles: fetching recent files")
        #endif
        guard let data = UserDefaults.standard.data(forKey: recentFilesKey),
              let bookmarks = try? JSONDecoder().decode([Data].self, from: data) else {
            #if DEBUG
            DebugLogger.shared.debug("RecentFilesManager.recentFiles: no recent files found")
            #endif
            return []
        }

        let urls = bookmarks.compactMap { bookmark -> URL? in
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark,
                                     options: .withSecurityScope,
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &isStale),
                  !isStale,
                  FileManager.default.fileExists(atPath: url.path) else {
                #if DEBUG
                DebugLogger.shared.debug("RecentFilesManager.recentFiles: skipping stale/missing bookmark")
                #endif
                return nil
            }
            return url
        }

        #if DEBUG
        DebugLogger.shared.debug("RecentFilesManager.recentFiles: resolved \(urls.count) valid URLs")
        #endif
        return urls
    }

    /// Add a file to recent files list
    func addRecentFile(_ url: URL) {
        #if DEBUG
        DebugLogger.shared.logRecentFileAdded(url: url)
        #endif
        // Create security-scoped bookmark
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) else {
            #if DEBUG
            DebugLogger.shared.warn("RecentFilesManager.addRecentFile: failed to create bookmark for \(url.lastPathComponent)")
            #endif
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
            #if DEBUG
            DebugLogger.shared.debug("RecentFilesManager.addRecentFile: saved \(bookmarks.count) bookmarks to UserDefaults")
            #endif
        }
    }

    /// Clear all recent files
    func clearRecentFiles() {
        #if DEBUG
        DebugLogger.shared.logRecentFilesCleared()
        #endif
        UserDefaults.standard.removeObject(forKey: recentFilesKey)
    }
}

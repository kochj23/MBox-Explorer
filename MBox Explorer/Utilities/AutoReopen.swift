//
//  AutoReopen.swift
//  MBox Explorer
//
//  Decides whether to reopen the most-recent archive on launch. With the parse
//  cache in place, reopening an unchanged archive is near-instant, so this is on
//  by default; a menu toggle lets the user turn it off.
//

import Foundation

enum AutoReopen {
    static let defaultsKey = "autoReopenLastArchive"

    /// On by default (nil in UserDefaults → true).
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    /// The archive to auto-open on launch, or nil if the feature is off or there
    /// is no still-existing recent file.
    static func fileToReopen(enabled: Bool, recent: [URL]) -> URL? {
        guard enabled else { return nil }
        return recent.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

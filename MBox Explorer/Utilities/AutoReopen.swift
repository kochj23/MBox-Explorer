//
//  AutoReopen.swift
//  MBox Explorer
//
//  Decides whether to reopen the most-recent archive on launch. With the parse
//  cache in place, reopening an unchanged archive is near-instant, so this is on
//  by default; a menu toggle lets the user turn it off.
//

import Foundation

#if DEBUG
import os.log
import class MBox_Explorer.DebugLogger
#endif

enum AutoReopen {
    static let defaultsKey = "autoReopenLastArchive"

    /// On by default (nil in UserDefaults → true).
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    /// The archive to auto-open on launch, or nil if the feature is off or there
    /// is no still-existing recent file.
    static func fileToReopen(enabled: Bool, recent: [URL]) -> URL? {
        #if DEBUG
        DebugLogger.shared.info("AutoReopen.fileToReopen: enabled=\(enabled), recent.count=\(recent.count)")
        #endif
        guard enabled else {
            #if DEBUG
            DebugLogger.shared.debug("AutoReopen.fileToReopen: disabled")
            #endif
            return nil
        }

        for url in recent {
            let exists = FileManager.default.fileExists(atPath: url.path)
            #if DEBUG
            DebugLogger.shared.debug("AutoReopen.fileToReopen: checking \(url.lastPathComponent), exists=\(exists)")
            #endif
            if exists {
                #if DEBUG
                DebugLogger.shared.info("AutoReopen.fileToReopen: selected \(url.lastPathComponent)")
                #endif
                return url
            }
        }

        #if DEBUG
        DebugLogger.shared.debug("AutoReopen.fileToReopen: no valid file found")
        #endif
        return nil
    }
}

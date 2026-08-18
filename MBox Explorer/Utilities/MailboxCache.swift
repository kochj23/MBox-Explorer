//
//  MailboxCache.swift
//  MBox Explorer
//
//  Persists a parsed mailbox ([Email]) to disk so reopening an unchanged archive
//  is near-instant instead of re-parsing the entire file every time (issue #2).
//
//  Keyed by file identity — path + size + modification date — so editing or
//  replacing the .mbox invalidates the cache automatically. Email bodies are PII,
//  so the cache lives in the app's Application Support folder (same convention as
//  vectors.db / conversations.db) with owner-only (0600) permissions.
//

import Foundation
import CryptoKit

final class MailboxCache {
    static let shared = MailboxCache()

    /// Bump when the Email model or envelope format changes to invalidate all caches.
    static let schemaVersion = 1

    /// Directory holding the cache files. Injectable so tests stay hermetic.
    let directory: URL

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    struct Envelope: Codable {
        let schemaVersion: Int
        let path: String
        let fileSize: Int
        let modifiedAt: Date
        let emails: [Email]
    }

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask).first!
            self.directory = base.appendingPathComponent("MBoxExplorer/MailboxCache",
                                                          isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory,
                                                 withIntermediateDirectories: true)
    }

    /// Deterministic, filesystem-safe cache path for a given source file.
    func cacheFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.path.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }

    /// Current (size, mtime) of the source file, or nil if it can't be read.
    func fileIdentity(of url: URL) -> (size: Int, modifiedAt: Date)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.intValue,
              let mtime = attrs[.modificationDate] as? Date else { return nil }
        return (size, mtime)
    }

    /// Returns cached emails iff a valid cache exists AND the source file is unchanged.
    /// A cache miss / stale cache / unreadable file all return nil (→ caller re-parses).
    func load(for url: URL) -> [Email]? {
        guard let id = fileIdentity(of: url),
              let data = try? Data(contentsOf: cacheFileURL(for: url)),
              let env = try? decoder.decode(Envelope.self, from: data),
              env.schemaVersion == Self.schemaVersion,
              env.fileSize == id.size,
              abs(env.modifiedAt.timeIntervalSince(id.modifiedAt)) < 1.0
        else { return nil }
        return env.emails
    }

    /// Persist parsed emails for a source file. Atomic write, owner-only perms.
    @discardableResult
    func store(_ emails: [Email], for url: URL) -> Bool {
        guard let id = fileIdentity(of: url) else { return false }
        let env = Envelope(schemaVersion: Self.schemaVersion, path: url.path,
                           fileSize: id.size, modifiedAt: id.modifiedAt, emails: emails)
        guard let data = try? encoder.encode(env) else { return false }
        let out = cacheFileURL(for: url)
        do {
            try data.write(to: out, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: out.path)
            return true
        } catch {
            return false
        }
    }

    /// Remove the cache for a single file (e.g. explicit re-import).
    func remove(for url: URL) {
        try? FileManager.default.removeItem(at: cacheFileURL(for: url))
    }
}

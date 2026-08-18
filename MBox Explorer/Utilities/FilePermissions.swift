//
//  FilePermissions.swift
//  MBox Explorer
//
//  Helpers to restrict on-disk data that is derived from email content (PII)
//  to the owner only. Email bodies live in the vector/conversation stores and
//  the mailbox cache, so those files should not be group/other readable.
//

import Foundation

enum FilePermissions {
    /// Restrict a file to owner read/write (0600).
    static func restrictFile(_ path: String) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    /// Restrict a directory to owner access only (0700).
    static func restrictDirectory(_ path: String) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
    }
}

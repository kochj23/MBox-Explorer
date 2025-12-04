//
//  VectorDatabase.swift
//  MBox Explorer
//
//  Local vector database for semantic email search
//  Author: Jordan Koch
//  Date: 2025-12-03
//

import Foundation
import SQLite3

/// Local vector database for semantic search
class VectorDatabase: ObservableObject {
    @Published var isIndexed = false
    @Published var indexProgress: Double = 0.0
    @Published var totalDocuments = 0

    private var db: OpaquePointer?
    private let dbPath: String

    init() {
        let documentsPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = documentsPath.appendingPathComponent("MBoxExplorer", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        dbPath = appFolder.appendingPathComponent("vectors.db").path
        openDatabase()
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Error opening database")
        }
    }

    private func createTables() {
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS email_vectors (
            id TEXT PRIMARY KEY,
            email_id TEXT,
            content TEXT,
            embedding BLOB,
            from_address TEXT,
            subject TEXT,
            date TEXT,
            metadata TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE INDEX IF NOT EXISTS idx_email_id ON email_vectors(email_id);
        CREATE INDEX IF NOT EXISTS idx_from ON email_vectors(from_address);
        CREATE INDEX IF NOT EXISTS idx_date ON email_vectors(date);

        CREATE VIRTUAL TABLE IF NOT EXISTS email_fts USING fts5(
            content,
            from_address,
            subject,
            content=email_vectors,
            content_rowid=rowid
        );
        """

        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createTableSQL, nil, nil, &error) != SQLITE_OK {
            let errorMessage = String(cString: error!)
            print("Error creating tables: \(errorMessage)")
            sqlite3_free(error)
        }
    }

    /// Index emails for semantic search
    func indexEmails(_ emails: [Email], progressCallback: @escaping (Double) -> Void) async {
        isIndexed = false
        totalDocuments = 0

        await withTaskGroup(of: Void.self) { group in
            for (index, email) in emails.enumerated() {
                group.addTask {
                    await self.indexEmail(email)
                }

                let progress = Double(index + 1) / Double(emails.count)
                await MainActor.run {
                    self.indexProgress = progress
                    progressCallback(progress)
                }
            }
        }

        await MainActor.run {
            self.isIndexed = true
            self.totalDocuments = emails.count
        }
    }

    private func indexEmail(_ email: Email) async {
        // For now, just store in FTS (full implementation would generate embeddings with MLX)
        let insertSQL = """
        INSERT OR REPLACE INTO email_vectors (id, email_id, content, from_address, subject, date, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, email.id.uuidString, -1, nil)
            sqlite3_bind_text(statement, 2, email.messageId, -1, nil)
            sqlite3_bind_text(statement, 3, email.body, -1, nil)
            sqlite3_bind_text(statement, 4, email.from, -1, nil)
            sqlite3_bind_text(statement, 5, email.subject, -1, nil)
            sqlite3_bind_text(statement, 6, email.date.ISO8601Format(), -1, nil)
            sqlite3_bind_text(statement, 7, "{}", -1, nil)  // Placeholder for metadata

            if sqlite3_step(statement) != SQLITE_DONE {
                print("Error inserting email")
            }
        }
        sqlite3_finalize(statement)
    }

    /// Search emails semantically
    func search(query: String) async -> [SearchResult] {
        var results: [SearchResult] = []

        // Use FTS5 for fast full-text search
        let searchSQL = """
        SELECT email_id, content, from_address, subject, date,
               snippet(email_fts, -1, '<mark>', '</mark>', '...', 32) as snippet
        FROM email_fts
        WHERE email_fts MATCH ?
        ORDER BY rank
        LIMIT 20;
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, searchSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, query, -1, nil)

            while sqlite3_step(statement) == SQLITE_ROW {
                let emailId = String(cString: sqlite3_column_text(statement, 0))
                let content = String(cString: sqlite3_column_text(statement, 1))
                let fromAddress = String(cString: sqlite3_column_text(statement, 2))
                let subject = String(cString: sqlite3_column_text(statement, 3))
                let dateString = String(cString: sqlite3_column_text(statement, 4))
                let snippet = String(cString: sqlite3_column_text(statement, 5))

                let result = SearchResult(
                    emailId: emailId,
                    content: content,
                    from: fromAddress,
                    subject: subject,
                    date: dateString,
                    snippet: snippet,
                    score: 1.0
                )
                results.append(result)
            }
        }
        sqlite3_finalize(statement)

        return results
    }

    /// Clear database
    func clearIndex() {
        let deleteSQL = "DELETE FROM email_vectors;"
        sqlite3_exec(db, deleteSQL, nil, nil, nil)
        isIndexed = false
        totalDocuments = 0
    }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let emailId: String
    let content: String
    let from: String
    let subject: String
    let date: String
    let snippet: String
    let score: Double
}

//
//  VectorDatabase.swift
//  MBox Explorer
//
//  Local vector database for semantic email search
//  Author: Jordan Koch
//  Date: 2025-12-03
//  Updated: 2025-01-17 - Added Ollama embeddings support
//  Updated: 2026-01-30 - Added multi-provider embedding support (MLX, OpenAI, sentence-transformers)
//

import Foundation
import SQLite3

/// Local vector database for semantic search
class VectorDatabase: ObservableObject {
    @Published var isIndexed = false
    @Published var indexProgress: Double = 0.0
    @Published var totalDocuments = 0
    @Published var useSemanticSearch = false
    @Published var embeddingProvider: String = "None"
    @Published var embeddingDimension: Int = 0

    private var db: OpaquePointer?
    private let dbPath: String
    private let embeddingManager = EmbeddingManager.shared

    init() {
        let documentsPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = documentsPath.appendingPathComponent("MBoxExplorer", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        dbPath = appFolder.appendingPathComponent("vectors.db").path
        openDatabase()
        createTables()

        // Initialize embedding provider
        Task {
            await initializeEmbeddings()
        }
    }

    private func initializeEmbeddings() async {
        await embeddingManager.updateActiveProvider()
        await MainActor.run {
            self.useSemanticSearch = embeddingManager.useSemanticSearch
            self.embeddingProvider = embeddingManager.selectedProvider.rawValue
            self.embeddingDimension = embeddingManager.currentDimension
        }
    }

    /// Refresh embedding provider status
    func refreshEmbeddingStatus() async {
        await embeddingManager.updateActiveProvider()
        await MainActor.run {
            self.useSemanticSearch = embeddingManager.useSemanticSearch
            self.embeddingProvider = embeddingManager.selectedProvider.rawValue
            self.embeddingDimension = embeddingManager.currentDimension
        }
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

    /// Index emails for semantic search with embeddings
    func indexEmails(_ emails: [Email], progressCallback: @escaping (Double) -> Void) async {
        isIndexed = false
        totalDocuments = 0

        // Refresh embedding status
        await refreshEmbeddingStatus()

        // Process in batches for efficiency
        let batchSize = 20
        let batches = stride(from: 0, to: emails.count, by: batchSize).map {
            Array(emails[$0..<min($0 + batchSize, emails.count)])
        }

        var processedCount = 0

        for batch in batches {
            // Generate embeddings for batch if embedding provider available
            var embeddings: [[Float]] = []

            if embeddingManager.useSemanticSearch {
                let texts = batch.map { email in
                    // Combine subject + first 500 chars of body for embedding
                    let bodyPrefix = String(email.body.prefix(500))
                    return "\(email.subject) \(bodyPrefix)"
                }

                do {
                    embeddings = try await embeddingManager.generateBatchEmbeddings(for: texts)
                } catch {
                    print("Embedding generation error (\(embeddingManager.selectedProvider.rawValue)): \(error.localizedDescription)")
                    // Continue without embeddings
                }
            }

            // Store emails with embeddings
            for (index, email) in batch.enumerated() {
                let embedding = embeddings.count > index ? embeddings[index] : nil
                await indexEmail(email, embedding: embedding)

                processedCount += 1
                let progress = Double(processedCount) / Double(emails.count)
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

    private func indexEmail(_ email: Email, embedding: [Float]?) async {
        let insertSQL = """
        INSERT OR REPLACE INTO email_vectors (id, email_id, content, embedding, from_address, subject, date, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, email.id.uuidString, -1, nil)
            sqlite3_bind_text(statement, 2, email.messageId, -1, nil)
            sqlite3_bind_text(statement, 3, email.body, -1, nil)

            // Store embedding as BLOB
            if let embedding = embedding {
                let data = embedding.withUnsafeBytes { Data($0) }
                data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(data.count), nil)
                }
            } else {
                sqlite3_bind_null(statement, 4)
            }

            sqlite3_bind_text(statement, 5, email.from, -1, nil)
            sqlite3_bind_text(statement, 6, email.subject, -1, nil)
            sqlite3_bind_text(statement, 7, email.date, -1, nil)

            // Store metadata as JSON
            let metadataJSON: String
            if let jsonData = try? JSONSerialization.data(withJSONObject: email.metadata, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                metadataJSON = jsonString
            } else {
                metadataJSON = "{}"
            }
            sqlite3_bind_text(statement, 8, metadataJSON, -1, nil)

            if sqlite3_step(statement) != SQLITE_DONE {
                print("Error inserting email")
            }
        }
        sqlite3_finalize(statement)
    }

    /// Search emails semantically or with FTS5
    func search(query: String) async -> [SearchResult] {
        // Refresh embedding status
        await refreshEmbeddingStatus()

        // Try semantic search first if available
        if embeddingManager.useSemanticSearch {
            do {
                return try await semanticSearch(query: query)
            } catch {
                print("Semantic search failed (\(embeddingManager.selectedProvider.rawValue)), falling back to FTS: \(error.localizedDescription)")
            }
        }

        // Fallback to FTS5 keyword search
        return await keywordSearch(query: query)
    }

    /// Semantic search using vector embeddings
    private func semanticSearch(query: String) async throws -> [SearchResult] {
        // Generate query embedding using active provider
        let queryEmbedding = try await embeddingManager.generateEmbedding(for: query)

        // Fetch all email embeddings from database
        var emailData: [(id: String, from: String, subject: String, date: String, content: String, embedding: [Float])] = []

        let fetchSQL = """
        SELECT id, email_id, content, from_address, subject, date, embedding
        FROM email_vectors
        WHERE embedding IS NOT NULL;
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, fetchSQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                // Safely extract text columns with null checks
                guard let idPtr = sqlite3_column_text(statement, 0),
                      let emailIdPtr = sqlite3_column_text(statement, 1),
                      let contentPtr = sqlite3_column_text(statement, 2),
                      let fromPtr = sqlite3_column_text(statement, 3),
                      let subjectPtr = sqlite3_column_text(statement, 4),
                      let datePtr = sqlite3_column_text(statement, 5) else {
                    continue
                }

                let id = String(cString: idPtr)
                let emailId = String(cString: emailIdPtr)
                let content = String(cString: contentPtr)
                let fromAddress = String(cString: fromPtr)
                let subject = String(cString: subjectPtr)
                let dateString = String(cString: datePtr)

                // Deserialize embedding BLOB - copy data immediately before next sqlite3_step
                let blobSize = sqlite3_column_bytes(statement, 6)
                guard blobSize > 0, let blobPointer = sqlite3_column_blob(statement, 6) else {
                    continue
                }

                // Create embedding array directly from blob pointer (copy happens here)
                let floatCount = Int(blobSize) / MemoryLayout<Float>.size
                var embedding = [Float](repeating: 0, count: floatCount)
                memcpy(&embedding, blobPointer, Int(blobSize))

                emailData.append((id: emailId, from: fromAddress, subject: subject, date: dateString, content: content, embedding: embedding))
            }
        }
        sqlite3_finalize(statement)

        // Calculate cosine similarity for each email
        var scoredResults: [(result: SearchResult, score: Float)] = []

        for email in emailData {
            let similarity = cosineSimilarity(queryEmbedding, email.embedding)

            let snippet = String(email.content.prefix(200))
            let result = SearchResult(
                emailId: email.id,
                content: email.content,
                from: email.from,
                subject: email.subject,
                date: email.date,
                snippet: snippet,
                score: Double(similarity)
            )

            scoredResults.append((result: result, score: similarity))
        }

        // Sort by similarity score (descending) and return top 20
        let topResults = scoredResults
            .sorted { $0.score > $1.score }
            .prefix(20)
            .map { $0.result }

        return Array(topResults)
    }

    /// Keyword search using FTS5 (fallback)
    private func keywordSearch(query: String) async -> [SearchResult] {
        var results: [SearchResult] = []

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

    /// Calculate cosine similarity between two vectors
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }

        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard magnitudeA > 0, magnitudeB > 0 else { return 0.0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    /// Clear database
    func clearIndex() {
        let deleteSQL = "DELETE FROM email_vectors;"
        sqlite3_exec(db, deleteSQL, nil, nil, nil)
        isIndexed = false
        totalDocuments = 0
    }

    /// Direct search through emails without requiring indexing
    /// This is a fallback when emails haven't been indexed yet
    func directSearch(query: String, emails: [Email], limit: Int = 20) -> [SearchResult] {
        let queryTerms = query.lowercased().split(separator: " ").map { String($0) }

        var scoredResults: [(email: Email, score: Int)] = []

        for email in emails {
            var score = 0
            let searchableText = "\(email.from) \(email.subject) \(email.body)".lowercased()

            for term in queryTerms {
                // Count occurrences of each term
                let occurrences = searchableText.components(separatedBy: term).count - 1
                score += occurrences

                // Bonus for subject match
                if email.subject.lowercased().contains(term) {
                    score += 5
                }

                // Bonus for sender match
                if email.from.lowercased().contains(term) {
                    score += 3
                }
            }

            if score > 0 {
                scoredResults.append((email: email, score: score))
            }
        }

        // Sort by score and take top results
        let topResults = scoredResults
            .sorted { $0.score > $1.score }
            .prefix(limit)

        return topResults.map { item in
            let snippet = String(item.email.body.prefix(300))
            return SearchResult(
                emailId: item.email.messageId ?? item.email.id.uuidString,
                content: item.email.body,
                from: item.email.from,
                subject: item.email.subject,
                date: item.email.date,
                snippet: snippet,
                score: Double(item.score)
            )
        }
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

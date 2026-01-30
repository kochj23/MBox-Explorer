//
//  ConversationDatabase.swift
//  MBox Explorer
//
//  SQLite-based persistent storage for conversations
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation
import SQLite3

/// Manages persistent storage for AI conversations
class ConversationDatabase: ObservableObject {
    static let shared = ConversationDatabase()

    @Published var conversations: [Conversation] = []
    @Published var commitments: [Commitment] = []
    @Published var patterns: [EmailPattern] = []

    private var db: OpaquePointer?
    private let dbPath: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Initialization

    private init() {
        let documentsPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = documentsPath.appendingPathComponent("MBoxExplorer", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        dbPath = appFolder.appendingPathComponent("conversations.db").path
        openDatabase()
        createTables()
        loadConversations()
        loadCommitments()
        loadPatterns()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Database Setup

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Error opening conversation database")
        }
    }

    private func createTables() {
        let createTablesSQL = """
        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            messages_json TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            is_favorite INTEGER DEFAULT 0,
            tags_json TEXT,
            email_context_json TEXT,
            branch_parent_id TEXT,
            branch_point_message_id TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations(updated_at DESC);
        CREATE INDEX IF NOT EXISTS idx_conversations_favorite ON conversations(is_favorite);

        CREATE TABLE IF NOT EXISTS commitments (
            id TEXT PRIMARY KEY,
            description TEXT NOT NULL,
            committer TEXT NOT NULL,
            recipient TEXT,
            deadline REAL,
            deadline_text TEXT,
            source_email_id TEXT NOT NULL,
            source_subject TEXT NOT NULL,
            source_date REAL NOT NULL,
            extracted_at REAL NOT NULL,
            status TEXT NOT NULL,
            notes TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_commitments_status ON commitments(status);
        CREATE INDEX IF NOT EXISTS idx_commitments_deadline ON commitments(deadline);

        CREATE TABLE IF NOT EXISTS patterns (
            id TEXT PRIMARY KEY,
            pattern_type TEXT NOT NULL,
            description TEXT NOT NULL,
            frequency TEXT NOT NULL,
            last_occurrence REAL NOT NULL,
            occurrences INTEGER DEFAULT 1,
            examples_json TEXT,
            participants_json TEXT,
            topics_json TEXT
        );

        CREATE TABLE IF NOT EXISTS relationships (
            id TEXT PRIMARY KEY,
            person1 TEXT NOT NULL,
            person2 TEXT NOT NULL,
            email_count INTEGER DEFAULT 0,
            first_contact REAL NOT NULL,
            last_contact REAL NOT NULL,
            average_sentiment REAL DEFAULT 0,
            topics_json TEXT,
            relationship_strength REAL DEFAULT 0,
            UNIQUE(person1, person2)
        );

        CREATE INDEX IF NOT EXISTS idx_relationships_strength ON relationships(relationship_strength DESC);

        CREATE TABLE IF NOT EXISTS sentiment_data (
            id TEXT PRIMARY KEY,
            date REAL NOT NULL,
            sentiment REAL NOT NULL,
            email_id TEXT NOT NULL,
            subject TEXT NOT NULL,
            participant TEXT NOT NULL,
            keywords_json TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_sentiment_date ON sentiment_data(date);
        CREATE INDEX IF NOT EXISTS idx_sentiment_participant ON sentiment_data(participant);

        CREATE TABLE IF NOT EXISTS decisions (
            id TEXT PRIMARY KEY,
            topic TEXT NOT NULL,
            decision TEXT NOT NULL,
            decision_makers_json TEXT NOT NULL,
            decision_date REAL NOT NULL,
            pros_json TEXT,
            cons_json TEXT,
            alternatives_json TEXT,
            supporting_emails_json TEXT,
            attachments_json TEXT,
            confidence REAL DEFAULT 0.5
        );

        CREATE INDEX IF NOT EXISTS idx_decisions_date ON decisions(decision_date DESC);

        CREATE TABLE IF NOT EXISTS briefings (
            id TEXT PRIMARY KEY,
            date REAL NOT NULL,
            needs_response_json TEXT,
            upcoming_deadlines_json TEXT,
            unusual_activity_json TEXT,
            trending_topics_json TEXT,
            summary TEXT,
            generated_at REAL NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_briefings_date ON briefings(date DESC);

        CREATE TABLE IF NOT EXISTS drafts (
            id TEXT PRIMARY KEY,
            recipient TEXT NOT NULL,
            subject TEXT NOT NULL,
            body TEXT NOT NULL,
            in_reply_to TEXT,
            conversation_context TEXT,
            tone TEXT NOT NULL,
            suggested_attachments_json TEXT,
            created_at REAL NOT NULL,
            is_edited INTEGER DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS personas (
            id TEXT PRIMARY KEY,
            email TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            communication_style TEXT,
            common_phrases_json TEXT,
            topic_expertise_json TEXT,
            sentiment_profile TEXT,
            average_response_time TEXT,
            sample_emails_json TEXT
        );
        """

        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createTablesSQL, nil, nil, &error) != SQLITE_OK {
            let errorMessage = String(cString: error!)
            print("Error creating tables: \(errorMessage)")
            sqlite3_free(error)
        }
    }

    // MARK: - Conversation CRUD

    func loadConversations() {
        var results: [Conversation] = []

        let sql = """
        SELECT id, title, messages_json, created_at, updated_at, is_favorite,
               tags_json, email_context_json, branch_parent_id, branch_point_message_id
        FROM conversations
        ORDER BY updated_at DESC;
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))) ?? UUID()
                let title = String(cString: sqlite3_column_text(statement, 1))
                let messagesJson = String(cString: sqlite3_column_text(statement, 2))
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                let isFavorite = sqlite3_column_int(statement, 5) == 1

                var tags: [String] = []
                if let tagsText = sqlite3_column_text(statement, 6) {
                    let tagsJson = String(cString: tagsText)
                    tags = (try? decoder.decode([String].self, from: tagsJson.data(using: .utf8)!)) ?? []
                }

                var emailContext: [String] = []
                if let contextText = sqlite3_column_text(statement, 7) {
                    let contextJson = String(cString: contextText)
                    emailContext = (try? decoder.decode([String].self, from: contextJson.data(using: .utf8)!)) ?? []
                }

                var branchParentId: UUID?
                if let parentText = sqlite3_column_text(statement, 8) {
                    branchParentId = UUID(uuidString: String(cString: parentText))
                }

                var branchPointMessageId: UUID?
                if let messageText = sqlite3_column_text(statement, 9) {
                    branchPointMessageId = UUID(uuidString: String(cString: messageText))
                }

                let messages = (try? decoder.decode([ConversationMessage].self, from: messagesJson.data(using: .utf8)!)) ?? []

                let conversation = Conversation(
                    id: id,
                    title: title,
                    messages: messages,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    isFavorite: isFavorite,
                    tags: tags,
                    emailContext: emailContext,
                    branchParentId: branchParentId,
                    branchPointMessageId: branchPointMessageId
                )
                results.append(conversation)
            }
        }
        sqlite3_finalize(statement)

        DispatchQueue.main.async {
            self.conversations = results
        }
    }

    func saveConversation(_ conversation: Conversation) {
        let sql = """
        INSERT OR REPLACE INTO conversations
        (id, title, messages_json, created_at, updated_at, is_favorite, tags_json,
         email_context_json, branch_parent_id, branch_point_message_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, conversation.id.uuidString, -1, nil)
            sqlite3_bind_text(statement, 2, conversation.title, -1, nil)

            if let messagesJson = try? encoder.encode(conversation.messages),
               let messagesString = String(data: messagesJson, encoding: .utf8) {
                sqlite3_bind_text(statement, 3, messagesString, -1, nil)
            } else {
                sqlite3_bind_text(statement, 3, "[]", -1, nil)
            }

            sqlite3_bind_double(statement, 4, conversation.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 5, conversation.updatedAt.timeIntervalSince1970)
            sqlite3_bind_int(statement, 6, conversation.isFavorite ? 1 : 0)

            if let tagsJson = try? encoder.encode(conversation.tags),
               let tagsString = String(data: tagsJson, encoding: .utf8) {
                sqlite3_bind_text(statement, 7, tagsString, -1, nil)
            } else {
                sqlite3_bind_text(statement, 7, "[]", -1, nil)
            }

            if let contextJson = try? encoder.encode(conversation.emailContext),
               let contextString = String(data: contextJson, encoding: .utf8) {
                sqlite3_bind_text(statement, 8, contextString, -1, nil)
            } else {
                sqlite3_bind_text(statement, 8, "[]", -1, nil)
            }

            if let branchParentId = conversation.branchParentId {
                sqlite3_bind_text(statement, 9, branchParentId.uuidString, -1, nil)
            } else {
                sqlite3_bind_null(statement, 9)
            }

            if let branchPointMessageId = conversation.branchPointMessageId {
                sqlite3_bind_text(statement, 10, branchPointMessageId.uuidString, -1, nil)
            } else {
                sqlite3_bind_null(statement, 10)
            }

            if sqlite3_step(statement) != SQLITE_DONE {
                print("Error saving conversation")
            }
        }
        sqlite3_finalize(statement)

        loadConversations()
    }

    func deleteConversation(_ conversation: Conversation) {
        let sql = "DELETE FROM conversations WHERE id = ?;"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, conversation.id.uuidString, -1, nil)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)

        loadConversations()
    }

    func searchConversations(query: String) -> [Conversation] {
        return conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(query) ||
            conversation.messages.contains { $0.content.localizedCaseInsensitiveContains(query) } ||
            conversation.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func getFavoriteConversations() -> [Conversation] {
        return conversations.filter { $0.isFavorite }
    }

    // MARK: - Commitment CRUD

    func loadCommitments() {
        var results: [Commitment] = []

        let sql = """
        SELECT id, description, committer, recipient, deadline, deadline_text,
               source_email_id, source_subject, source_date, extracted_at, status, notes
        FROM commitments
        ORDER BY deadline ASC NULLS LAST;
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))) ?? UUID()
                let description = String(cString: sqlite3_column_text(statement, 1))
                let committer = String(cString: sqlite3_column_text(statement, 2))

                var recipient: String?
                if sqlite3_column_type(statement, 3) != SQLITE_NULL {
                    recipient = String(cString: sqlite3_column_text(statement, 3))
                }

                var deadline: Date?
                if sqlite3_column_type(statement, 4) != SQLITE_NULL {
                    deadline = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                }

                var deadlineText: String?
                if sqlite3_column_type(statement, 5) != SQLITE_NULL {
                    deadlineText = String(cString: sqlite3_column_text(statement, 5))
                }

                let sourceEmailId = String(cString: sqlite3_column_text(statement, 6))
                let sourceSubject = String(cString: sqlite3_column_text(statement, 7))
                let sourceDate = Date(timeIntervalSince1970: sqlite3_column_double(statement, 8))
                let extractedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 9))
                let statusString = String(cString: sqlite3_column_text(statement, 10))
                let status = CommitmentStatus(rawValue: statusString) ?? .pending

                var notes: String?
                if sqlite3_column_type(statement, 11) != SQLITE_NULL {
                    notes = String(cString: sqlite3_column_text(statement, 11))
                }

                let commitment = Commitment(
                    id: id,
                    description: description,
                    committer: committer,
                    recipient: recipient,
                    deadline: deadline,
                    deadlineText: deadlineText,
                    sourceEmailId: sourceEmailId,
                    sourceSubject: sourceSubject,
                    sourceDate: sourceDate,
                    extractedAt: extractedAt,
                    status: status,
                    notes: notes
                )
                results.append(commitment)
            }
        }
        sqlite3_finalize(statement)

        DispatchQueue.main.async {
            self.commitments = results
        }
    }

    func saveCommitment(_ commitment: Commitment) {
        let sql = """
        INSERT OR REPLACE INTO commitments
        (id, description, committer, recipient, deadline, deadline_text,
         source_email_id, source_subject, source_date, extracted_at, status, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, commitment.id.uuidString, -1, nil)
            sqlite3_bind_text(statement, 2, commitment.description, -1, nil)
            sqlite3_bind_text(statement, 3, commitment.committer, -1, nil)

            if let recipient = commitment.recipient {
                sqlite3_bind_text(statement, 4, recipient, -1, nil)
            } else {
                sqlite3_bind_null(statement, 4)
            }

            if let deadline = commitment.deadline {
                sqlite3_bind_double(statement, 5, deadline.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 5)
            }

            if let deadlineText = commitment.deadlineText {
                sqlite3_bind_text(statement, 6, deadlineText, -1, nil)
            } else {
                sqlite3_bind_null(statement, 6)
            }

            sqlite3_bind_text(statement, 7, commitment.sourceEmailId, -1, nil)
            sqlite3_bind_text(statement, 8, commitment.sourceSubject, -1, nil)
            sqlite3_bind_double(statement, 9, commitment.sourceDate.timeIntervalSince1970)
            sqlite3_bind_double(statement, 10, commitment.extractedAt.timeIntervalSince1970)
            sqlite3_bind_text(statement, 11, commitment.status.rawValue, -1, nil)

            if let notes = commitment.notes {
                sqlite3_bind_text(statement, 12, notes, -1, nil)
            } else {
                sqlite3_bind_null(statement, 12)
            }

            if sqlite3_step(statement) != SQLITE_DONE {
                print("Error saving commitment")
            }
        }
        sqlite3_finalize(statement)

        loadCommitments()
    }

    func updateCommitmentStatus(_ commitment: Commitment, status: CommitmentStatus) {
        var updated = commitment
        updated.status = status
        saveCommitment(updated)
    }

    func getPendingCommitments() -> [Commitment] {
        return commitments.filter { $0.status == .pending }
    }

    func getOverdueCommitments() -> [Commitment] {
        return commitments.filter { $0.isOverdue }
    }

    // MARK: - Pattern CRUD

    func loadPatterns() {
        var results: [EmailPattern] = []

        let sql = """
        SELECT id, pattern_type, description, frequency, last_occurrence, occurrences,
               examples_json, participants_json, topics_json
        FROM patterns
        ORDER BY occurrences DESC;
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))) ?? UUID()
                let patternTypeString = String(cString: sqlite3_column_text(statement, 1))
                let patternType = PatternType(rawValue: patternTypeString) ?? .recurringTopic
                let description = String(cString: sqlite3_column_text(statement, 2))
                let frequency = String(cString: sqlite3_column_text(statement, 3))
                let lastOccurrence = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                let occurrences = Int(sqlite3_column_int(statement, 5))

                var examples: [String] = []
                if let examplesText = sqlite3_column_text(statement, 6) {
                    let examplesJson = String(cString: examplesText)
                    examples = (try? decoder.decode([String].self, from: examplesJson.data(using: .utf8)!)) ?? []
                }

                var participants: [String] = []
                if let participantsText = sqlite3_column_text(statement, 7) {
                    let participantsJson = String(cString: participantsText)
                    participants = (try? decoder.decode([String].self, from: participantsJson.data(using: .utf8)!)) ?? []
                }

                var topics: [String] = []
                if let topicsText = sqlite3_column_text(statement, 8) {
                    let topicsJson = String(cString: topicsText)
                    topics = (try? decoder.decode([String].self, from: topicsJson.data(using: .utf8)!)) ?? []
                }

                let pattern = EmailPattern(
                    id: id,
                    patternType: patternType,
                    description: description,
                    frequency: frequency,
                    lastOccurrence: lastOccurrence,
                    occurrences: occurrences,
                    examples: examples,
                    participants: participants,
                    topics: topics
                )
                results.append(pattern)
            }
        }
        sqlite3_finalize(statement)

        DispatchQueue.main.async {
            self.patterns = results
        }
    }

    func savePattern(_ pattern: EmailPattern) {
        let sql = """
        INSERT OR REPLACE INTO patterns
        (id, pattern_type, description, frequency, last_occurrence, occurrences,
         examples_json, participants_json, topics_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, pattern.id.uuidString, -1, nil)
            sqlite3_bind_text(statement, 2, pattern.patternType.rawValue, -1, nil)
            sqlite3_bind_text(statement, 3, pattern.description, -1, nil)
            sqlite3_bind_text(statement, 4, pattern.frequency, -1, nil)
            sqlite3_bind_double(statement, 5, pattern.lastOccurrence.timeIntervalSince1970)
            sqlite3_bind_int(statement, 6, Int32(pattern.occurrences))

            if let examplesJson = try? encoder.encode(pattern.examples),
               let examplesString = String(data: examplesJson, encoding: .utf8) {
                sqlite3_bind_text(statement, 7, examplesString, -1, nil)
            } else {
                sqlite3_bind_text(statement, 7, "[]", -1, nil)
            }

            if let participantsJson = try? encoder.encode(pattern.participants),
               let participantsString = String(data: participantsJson, encoding: .utf8) {
                sqlite3_bind_text(statement, 8, participantsString, -1, nil)
            } else {
                sqlite3_bind_text(statement, 8, "[]", -1, nil)
            }

            if let topicsJson = try? encoder.encode(pattern.topics),
               let topicsString = String(data: topicsJson, encoding: .utf8) {
                sqlite3_bind_text(statement, 9, topicsString, -1, nil)
            } else {
                sqlite3_bind_text(statement, 9, "[]", -1, nil)
            }

            if sqlite3_step(statement) != SQLITE_DONE {
                print("Error saving pattern")
            }
        }
        sqlite3_finalize(statement)

        loadPatterns()
    }

    // MARK: - Relationship Operations

    func saveRelationship(_ relationship: EmailRelationship) {
        let sql = """
        INSERT OR REPLACE INTO relationships
        (id, person1, person2, email_count, first_contact, last_contact,
         average_sentiment, topics_json, relationship_strength)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, relationship.id.uuidString, -1, nil)
            sqlite3_bind_text(statement, 2, relationship.person1, -1, nil)
            sqlite3_bind_text(statement, 3, relationship.person2, -1, nil)
            sqlite3_bind_int(statement, 4, Int32(relationship.emailCount))
            sqlite3_bind_double(statement, 5, relationship.firstContact.timeIntervalSince1970)
            sqlite3_bind_double(statement, 6, relationship.lastContact.timeIntervalSince1970)
            sqlite3_bind_double(statement, 7, relationship.averageSentiment)

            if let topicsJson = try? encoder.encode(relationship.topics),
               let topicsString = String(data: topicsJson, encoding: .utf8) {
                sqlite3_bind_text(statement, 8, topicsString, -1, nil)
            } else {
                sqlite3_bind_text(statement, 8, "[]", -1, nil)
            }

            sqlite3_bind_double(statement, 9, relationship.relationshipStrength)

            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    func getRelationships() -> [EmailRelationship] {
        var results: [EmailRelationship] = []

        let sql = """
        SELECT id, person1, person2, email_count, first_contact, last_contact,
               average_sentiment, topics_json, relationship_strength
        FROM relationships
        ORDER BY relationship_strength DESC;
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))) ?? UUID()
                let person1 = String(cString: sqlite3_column_text(statement, 1))
                let person2 = String(cString: sqlite3_column_text(statement, 2))
                let emailCount = Int(sqlite3_column_int(statement, 3))
                let firstContact = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                let lastContact = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
                let averageSentiment = sqlite3_column_double(statement, 6)

                var topics: [String] = []
                if let topicsText = sqlite3_column_text(statement, 7) {
                    let topicsJson = String(cString: topicsText)
                    topics = (try? decoder.decode([String].self, from: topicsJson.data(using: .utf8)!)) ?? []
                }

                let relationshipStrength = sqlite3_column_double(statement, 8)

                let relationship = EmailRelationship(
                    id: id,
                    person1: person1,
                    person2: person2,
                    emailCount: emailCount,
                    firstContact: firstContact,
                    lastContact: lastContact,
                    averageSentiment: averageSentiment,
                    topics: topics,
                    relationshipStrength: relationshipStrength
                )
                results.append(relationship)
            }
        }
        sqlite3_finalize(statement)

        return results
    }

    // MARK: - Sentiment Operations

    func saveSentimentDataPoint(_ dataPoint: SentimentDataPoint) {
        let sql = """
        INSERT OR REPLACE INTO sentiment_data
        (id, date, sentiment, email_id, subject, participant, keywords_json)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, dataPoint.id.uuidString, -1, nil)
            sqlite3_bind_double(statement, 2, dataPoint.date.timeIntervalSince1970)
            sqlite3_bind_double(statement, 3, dataPoint.sentiment)
            sqlite3_bind_text(statement, 4, dataPoint.emailId, -1, nil)
            sqlite3_bind_text(statement, 5, dataPoint.subject, -1, nil)
            sqlite3_bind_text(statement, 6, dataPoint.participant, -1, nil)

            if let keywordsJson = try? encoder.encode(dataPoint.keywords),
               let keywordsString = String(data: keywordsJson, encoding: .utf8) {
                sqlite3_bind_text(statement, 7, keywordsString, -1, nil)
            } else {
                sqlite3_bind_text(statement, 7, "[]", -1, nil)
            }

            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    func getSentimentTimeline(for participant: String? = nil, from startDate: Date? = nil, to endDate: Date? = nil) -> [SentimentDataPoint] {
        var results: [SentimentDataPoint] = []

        var sql = "SELECT id, date, sentiment, email_id, subject, participant, keywords_json FROM sentiment_data WHERE 1=1"
        var params: [Any] = []

        if let participant = participant {
            sql += " AND participant = ?"
            params.append(participant)
        }

        if let startDate = startDate {
            sql += " AND date >= ?"
            params.append(startDate.timeIntervalSince1970)
        }

        if let endDate = endDate {
            sql += " AND date <= ?"
            params.append(endDate.timeIntervalSince1970)
        }

        sql += " ORDER BY date ASC;"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            var paramIndex: Int32 = 1
            for param in params {
                if let stringParam = param as? String {
                    sqlite3_bind_text(statement, paramIndex, stringParam, -1, nil)
                } else if let doubleParam = param as? Double {
                    sqlite3_bind_double(statement, paramIndex, doubleParam)
                }
                paramIndex += 1
            }

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))) ?? UUID()
                let date = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
                let sentiment = sqlite3_column_double(statement, 2)
                let emailId = String(cString: sqlite3_column_text(statement, 3))
                let subject = String(cString: sqlite3_column_text(statement, 4))
                let participantName = String(cString: sqlite3_column_text(statement, 5))

                var keywords: [String] = []
                if let keywordsText = sqlite3_column_text(statement, 6) {
                    let keywordsJson = String(cString: keywordsText)
                    keywords = (try? decoder.decode([String].self, from: keywordsJson.data(using: .utf8)!)) ?? []
                }

                let dataPoint = SentimentDataPoint(
                    id: id,
                    date: date,
                    sentiment: sentiment,
                    emailId: emailId,
                    subject: subject,
                    participant: participantName,
                    keywords: keywords
                )
                results.append(dataPoint)
            }
        }
        sqlite3_finalize(statement)

        return results
    }

    // MARK: - Decision Operations

    func saveDecision(_ decision: TracedDecision) {
        let sql = """
        INSERT OR REPLACE INTO decisions
        (id, topic, decision, decision_makers_json, decision_date, pros_json, cons_json,
         alternatives_json, supporting_emails_json, attachments_json, confidence)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, decision.id.uuidString, -1, nil)
            sqlite3_bind_text(statement, 2, decision.topic, -1, nil)
            sqlite3_bind_text(statement, 3, decision.decision, -1, nil)

            if let makersJson = try? encoder.encode(decision.decisionMakers),
               let makersString = String(data: makersJson, encoding: .utf8) {
                sqlite3_bind_text(statement, 4, makersString, -1, nil)
            } else {
                sqlite3_bind_text(statement, 4, "[]", -1, nil)
            }

            sqlite3_bind_double(statement, 5, decision.decisionDate.timeIntervalSince1970)

            if let prosJson = try? encoder.encode(decision.pros),
               let prosString = String(data: prosJson, encoding: .utf8) {
                sqlite3_bind_text(statement, 6, prosString, -1, nil)
            } else {
                sqlite3_bind_text(statement, 6, "[]", -1, nil)
            }

            if let consJson = try? encoder.encode(decision.cons),
               let consString = String(data: consJson, encoding: .utf8) {
                sqlite3_bind_text(statement, 7, consString, -1, nil)
            } else {
                sqlite3_bind_text(statement, 7, "[]", -1, nil)
            }

            if let alternativesJson = try? encoder.encode(decision.alternatives),
               let alternativesString = String(data: alternativesJson, encoding: .utf8) {
                sqlite3_bind_text(statement, 8, alternativesString, -1, nil)
            } else {
                sqlite3_bind_text(statement, 8, "[]", -1, nil)
            }

            if let emailsJson = try? encoder.encode(decision.supportingEmails),
               let emailsString = String(data: emailsJson, encoding: .utf8) {
                sqlite3_bind_text(statement, 9, emailsString, -1, nil)
            } else {
                sqlite3_bind_text(statement, 9, "[]", -1, nil)
            }

            if let attachmentsJson = try? encoder.encode(decision.attachments),
               let attachmentsString = String(data: attachmentsJson, encoding: .utf8) {
                sqlite3_bind_text(statement, 10, attachmentsString, -1, nil)
            } else {
                sqlite3_bind_text(statement, 10, "[]", -1, nil)
            }

            sqlite3_bind_double(statement, 11, decision.confidence)

            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    func getDecisions(topic: String? = nil) -> [TracedDecision] {
        var results: [TracedDecision] = []

        var sql = """
        SELECT id, topic, decision, decision_makers_json, decision_date, pros_json, cons_json,
               alternatives_json, supporting_emails_json, attachments_json, confidence
        FROM decisions
        """

        if let topic = topic {
            sql += " WHERE topic LIKE '%\(topic)%'"
        }

        sql += " ORDER BY decision_date DESC;"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))) ?? UUID()
                let topic = String(cString: sqlite3_column_text(statement, 1))
                let decisionText = String(cString: sqlite3_column_text(statement, 2))

                var decisionMakers: [String] = []
                if let makersText = sqlite3_column_text(statement, 3) {
                    let makersJson = String(cString: makersText)
                    decisionMakers = (try? decoder.decode([String].self, from: makersJson.data(using: .utf8)!)) ?? []
                }

                let decisionDate = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))

                var pros: [String] = []
                if let prosText = sqlite3_column_text(statement, 5) {
                    let prosJson = String(cString: prosText)
                    pros = (try? decoder.decode([String].self, from: prosJson.data(using: .utf8)!)) ?? []
                }

                var cons: [String] = []
                if let consText = sqlite3_column_text(statement, 6) {
                    let consJson = String(cString: consText)
                    cons = (try? decoder.decode([String].self, from: consJson.data(using: .utf8)!)) ?? []
                }

                var alternatives: [String] = []
                if let alternativesText = sqlite3_column_text(statement, 7) {
                    let alternativesJson = String(cString: alternativesText)
                    alternatives = (try? decoder.decode([String].self, from: alternativesJson.data(using: .utf8)!)) ?? []
                }

                var supportingEmails: [String] = []
                if let emailsText = sqlite3_column_text(statement, 8) {
                    let emailsJson = String(cString: emailsText)
                    supportingEmails = (try? decoder.decode([String].self, from: emailsJson.data(using: .utf8)!)) ?? []
                }

                var attachments: [String] = []
                if let attachmentsText = sqlite3_column_text(statement, 9) {
                    let attachmentsJson = String(cString: attachmentsText)
                    attachments = (try? decoder.decode([String].self, from: attachmentsJson.data(using: .utf8)!)) ?? []
                }

                let confidence = sqlite3_column_double(statement, 10)

                let decision = TracedDecision(
                    id: id,
                    topic: topic,
                    decision: decisionText,
                    decisionMakers: decisionMakers,
                    decisionDate: decisionDate,
                    pros: pros,
                    cons: cons,
                    alternatives: alternatives,
                    supportingEmails: supportingEmails,
                    attachments: attachments,
                    confidence: confidence
                )
                results.append(decision)
            }
        }
        sqlite3_finalize(statement)

        return results
    }

    // MARK: - Export

    func exportConversation(_ conversation: Conversation, format: ExportFormat) -> String {
        switch format {
        case .markdown:
            return exportToMarkdown(conversation)
        case .json:
            return exportToJSON(conversation)
        case .plainText:
            return exportToPlainText(conversation)
        }
    }

    private func exportToMarkdown(_ conversation: Conversation) -> String {
        var output = "# \(conversation.title)\n\n"
        output += "**Created:** \(formatDate(conversation.createdAt))\n"
        output += "**Updated:** \(formatDate(conversation.updatedAt))\n\n"

        if !conversation.tags.isEmpty {
            output += "**Tags:** \(conversation.tags.joined(separator: ", "))\n\n"
        }

        output += "---\n\n"

        for message in conversation.messages {
            let roleIcon = message.role == .user ? "You" : "AI"
            output += "### \(roleIcon) (\(formatTime(message.timestamp)))\n\n"
            output += "\(message.content)\n\n"

            if !message.citations.isEmpty {
                output += "**Sources:**\n"
                for citation in message.citations {
                    output += "- [\(citation.citationIndex)] \(citation.subject) (from: \(citation.from), \(citation.date))\n"
                }
                output += "\n"
            }

            output += "---\n\n"
        }

        return output
    }

    private func exportToJSON(_ conversation: Conversation) -> String {
        if let data = try? encoder.encode(conversation),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }

    private func exportToPlainText(_ conversation: Conversation) -> String {
        var output = "Conversation: \(conversation.title)\n"
        output += "Created: \(formatDate(conversation.createdAt))\n"
        output += "Updated: \(formatDate(conversation.updatedAt))\n"
        output += String(repeating: "=", count: 50) + "\n\n"

        for message in conversation.messages {
            let role = message.role == .user ? "YOU" : "AI"
            output += "[\(role)] \(formatTime(message.timestamp))\n"
            output += "\(message.content)\n\n"
        }

        return output
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    enum ExportFormat {
        case markdown
        case json
        case plainText
    }
}

//
//  ConversationModels.swift
//  MBox Explorer
//
//  Data models for multi-turn AI conversations with email
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation

// MARK: - Conversation

/// Represents a multi-turn conversation with email context
struct Conversation: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var messages: [ConversationMessage]
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var tags: [String]
    var emailContext: [String] // Email IDs referenced in conversation
    var branchParentId: UUID? // For conversation branching
    var branchPointMessageId: UUID? // Message where branch started

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        messages: [ConversationMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isFavorite: Bool = false,
        tags: [String] = [],
        emailContext: [String] = [],
        branchParentId: UUID? = nil,
        branchPointMessageId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.tags = tags
        self.emailContext = emailContext
        self.branchParentId = branchParentId
        self.branchPointMessageId = branchPointMessageId
    }

    var messageCount: Int { messages.count }

    var lastMessage: ConversationMessage? { messages.last }

    var displayTitle: String {
        if title == "New Conversation" {
            return messages.first?.content.prefix(50).appending("...") ?? "New Conversation"
        }
        return title
    }

    /// Get messages for context window (last N turns)
    func contextMessages(maxTurns: Int = 10) -> [ConversationMessage] {
        let relevantMessages = messages.suffix(maxTurns * 2) // User + Assistant pairs
        return Array(relevantMessages)
    }

    mutating func addMessage(_ message: ConversationMessage) {
        messages.append(message)
        updatedAt = Date()
    }
}

// MARK: - Conversation Message

/// A single message in a conversation
struct ConversationMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var citations: [EmailCitation]
    var metadata: MessageMetadata?
    var isStreaming: Bool
    var tokenCount: Int?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        citations: [EmailCitation] = [],
        metadata: MessageMetadata? = nil,
        isStreaming: Bool = false,
        tokenCount: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.citations = citations
        self.metadata = metadata
        self.isStreaming = isStreaming
        self.tokenCount = tokenCount
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

// MARK: - Email Citation

/// Reference to an email used as source in AI response
struct EmailCitation: Identifiable, Codable, Hashable {
    let id: UUID
    let emailId: String
    let from: String
    let subject: String
    let date: String
    let snippet: String
    let relevanceScore: Double
    let citationIndex: Int // [1], [2], etc.

    init(
        id: UUID = UUID(),
        emailId: String,
        from: String,
        subject: String,
        date: String,
        snippet: String,
        relevanceScore: Double,
        citationIndex: Int
    ) {
        self.id = id
        self.emailId = emailId
        self.from = from
        self.subject = subject
        self.date = date
        self.snippet = snippet
        self.relevanceScore = relevanceScore
        self.citationIndex = citationIndex
    }

    /// Format citation marker for display in text
    var marker: String { "[\(citationIndex)]" }

    /// Confidence level based on relevance score
    var confidence: CitationConfidence {
        switch relevanceScore {
        case 0.8...1.0: return .high
        case 0.5..<0.8: return .medium
        default: return .low
        }
    }
}

enum CitationConfidence: String, Codable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var color: String {
        switch self {
        case .high: return "green"
        case .medium: return "yellow"
        case .low: return "orange"
        }
    }
}

// MARK: - Message Metadata

/// Additional metadata for conversation messages
struct MessageMetadata: Codable, Hashable {
    var queryType: QueryType?
    var processingTime: TimeInterval?
    var modelUsed: String?
    var searchResults: Int?
    var actionsTaken: [String]?
    var suggestedFollowUps: [String]?

    init(
        queryType: QueryType? = nil,
        processingTime: TimeInterval? = nil,
        modelUsed: String? = nil,
        searchResults: Int? = nil,
        actionsTaken: [String]? = nil,
        suggestedFollowUps: [String]? = nil
    ) {
        self.queryType = queryType
        self.processingTime = processingTime
        self.modelUsed = modelUsed
        self.searchResults = searchResults
        self.actionsTaken = actionsTaken
        self.suggestedFollowUps = suggestedFollowUps
    }
}

enum QueryType: String, Codable {
    case search = "Search"
    case summary = "Summary"
    case analysis = "Analysis"
    case action = "Action"
    case clarification = "Clarification"
    case persona = "Persona"
    case timeTravel = "Time Travel"
    case hypothetical = "Hypothetical"
    case draft = "Draft"
    case forward = "Forward"
}

// MARK: - Commitment

/// Represents a commitment/action item extracted from emails
struct Commitment: Identifiable, Codable, Hashable {
    let id: UUID
    let description: String
    let committer: String // Who made the commitment
    let recipient: String? // Who it was made to
    let deadline: Date?
    let deadlineText: String? // Original text like "by Friday"
    let sourceEmailId: String
    let sourceSubject: String
    let sourceDate: Date
    let extractedAt: Date
    var status: CommitmentStatus
    var notes: String?

    init(
        id: UUID = UUID(),
        description: String,
        committer: String,
        recipient: String? = nil,
        deadline: Date? = nil,
        deadlineText: String? = nil,
        sourceEmailId: String,
        sourceSubject: String,
        sourceDate: Date,
        extractedAt: Date = Date(),
        status: CommitmentStatus = .pending,
        notes: String? = nil
    ) {
        self.id = id
        self.description = description
        self.committer = committer
        self.recipient = recipient
        self.deadline = deadline
        self.deadlineText = deadlineText
        self.sourceEmailId = sourceEmailId
        self.sourceSubject = sourceSubject
        self.sourceDate = sourceDate
        self.extractedAt = extractedAt
        self.status = status
        self.notes = notes
    }

    var isOverdue: Bool {
        guard let deadline = deadline else { return false }
        return deadline < Date() && status == .pending
    }

    var daysUntilDeadline: Int? {
        guard let deadline = deadline else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: deadline).day
    }
}

enum CommitmentStatus: String, Codable, CaseIterable {
    case pending = "Pending"
    case completed = "Completed"
    case cancelled = "Cancelled"
    case deferred = "Deferred"
}

// MARK: - Relationship

/// Represents a relationship between email participants
struct EmailRelationship: Identifiable, Codable, Hashable {
    let id: UUID
    let person1: String
    let person2: String
    var emailCount: Int
    var firstContact: Date
    var lastContact: Date
    var averageSentiment: Double // -1 to 1
    var topics: [String]
    var relationshipStrength: Double // 0 to 1 based on frequency

    init(
        id: UUID = UUID(),
        person1: String,
        person2: String,
        emailCount: Int = 0,
        firstContact: Date = Date(),
        lastContact: Date = Date(),
        averageSentiment: Double = 0,
        topics: [String] = [],
        relationshipStrength: Double = 0
    ) {
        self.id = id
        self.person1 = person1
        self.person2 = person2
        self.emailCount = emailCount
        self.firstContact = firstContact
        self.lastContact = lastContact
        self.averageSentiment = averageSentiment
        self.topics = topics
        self.relationshipStrength = relationshipStrength
    }

    var participants: Set<String> { Set([person1, person2]) }
}

// MARK: - Sentiment Data Point

/// Sentiment measurement at a point in time
struct SentimentDataPoint: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let sentiment: Double // -1 (negative) to 1 (positive)
    let emailId: String
    let subject: String
    let participant: String
    var keywords: [String]

    init(
        id: UUID = UUID(),
        date: Date,
        sentiment: Double,
        emailId: String,
        subject: String,
        participant: String,
        keywords: [String] = []
    ) {
        self.id = id
        self.date = date
        self.sentiment = sentiment
        self.emailId = emailId
        self.subject = subject
        self.participant = participant
        self.keywords = keywords
    }

    var sentimentCategory: SentimentCategory {
        switch sentiment {
        case 0.3...1.0: return .positive
        case -0.3..<0.3: return .neutral
        default: return .negative
        }
    }
}

enum SentimentCategory: String, Codable {
    case positive = "Positive"
    case neutral = "Neutral"
    case negative = "Negative"
}

// MARK: - Decision

/// Represents a decision traced through email threads
struct TracedDecision: Identifiable, Codable, Hashable {
    let id: UUID
    let topic: String
    let decision: String
    let decisionMakers: [String]
    let decisionDate: Date
    var pros: [String]
    var cons: [String]
    var alternatives: [String]
    var supportingEmails: [String] // Email IDs
    var attachments: [String] // Referenced attachments
    var confidence: Double

    init(
        id: UUID = UUID(),
        topic: String,
        decision: String,
        decisionMakers: [String],
        decisionDate: Date,
        pros: [String] = [],
        cons: [String] = [],
        alternatives: [String] = [],
        supportingEmails: [String] = [],
        attachments: [String] = [],
        confidence: Double = 0.5
    ) {
        self.id = id
        self.topic = topic
        self.decision = decision
        self.decisionMakers = decisionMakers
        self.decisionDate = decisionDate
        self.pros = pros
        self.cons = cons
        self.alternatives = alternatives
        self.supportingEmails = supportingEmails
        self.attachments = attachments
        self.confidence = confidence
    }
}

// MARK: - Pattern

/// Detected pattern in email communications
struct EmailPattern: Identifiable, Codable, Hashable {
    let id: UUID
    let patternType: PatternType
    let description: String
    let frequency: String // "Weekly", "Monthly", "Quarterly"
    let lastOccurrence: Date
    var occurrences: Int
    var examples: [String] // Email IDs
    var participants: [String]
    var topics: [String]

    init(
        id: UUID = UUID(),
        patternType: PatternType,
        description: String,
        frequency: String,
        lastOccurrence: Date,
        occurrences: Int = 1,
        examples: [String] = [],
        participants: [String] = [],
        topics: [String] = []
    ) {
        self.id = id
        self.patternType = patternType
        self.description = description
        self.frequency = frequency
        self.lastOccurrence = lastOccurrence
        self.occurrences = occurrences
        self.examples = examples
        self.participants = participants
        self.topics = topics
    }
}

enum PatternType: String, Codable, CaseIterable {
    case recurringTopic = "Recurring Topic"
    case seasonalActivity = "Seasonal Activity"
    case communicationSpike = "Communication Spike"
    case responseDelay = "Response Delay"
    case threadLength = "Long Threads"
    case sentimentShift = "Sentiment Shift"
}

// MARK: - Daily Briefing

/// AI-generated daily briefing about email activity
struct DailyBriefing: Identifiable, Codable {
    let id: UUID
    let date: Date
    var needsResponse: [BriefingItem]
    var upcomingDeadlines: [BriefingItem]
    var unusualActivity: [BriefingItem]
    var trendingTopics: [String]
    var summary: String
    var generatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        needsResponse: [BriefingItem] = [],
        upcomingDeadlines: [BriefingItem] = [],
        unusualActivity: [BriefingItem] = [],
        trendingTopics: [String] = [],
        summary: String = "",
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.needsResponse = needsResponse
        self.upcomingDeadlines = upcomingDeadlines
        self.unusualActivity = unusualActivity
        self.trendingTopics = trendingTopics
        self.summary = summary
        self.generatedAt = generatedAt
    }
}

struct BriefingItem: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let description: String
    let emailId: String?
    let priority: BriefingPriority
    let actionRequired: Bool

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        emailId: String? = nil,
        priority: BriefingPriority = .medium,
        actionRequired: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.emailId = emailId
        self.priority = priority
        self.actionRequired = actionRequired
    }
}

enum BriefingPriority: String, Codable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

// MARK: - Smart Suggestion

/// Proactive suggestion from AI while browsing
struct SmartSuggestion: Identifiable, Codable, Hashable {
    let id: UUID
    let suggestionType: SuggestionType
    let title: String
    let description: String
    let actionLabel: String
    let relatedEmailIds: [String]
    let confidence: Double
    let createdAt: Date
    var isDismissed: Bool

    init(
        id: UUID = UUID(),
        suggestionType: SuggestionType,
        title: String,
        description: String,
        actionLabel: String,
        relatedEmailIds: [String] = [],
        confidence: Double = 0.7,
        createdAt: Date = Date(),
        isDismissed: Bool = false
    ) {
        self.id = id
        self.suggestionType = suggestionType
        self.title = title
        self.description = description
        self.actionLabel = actionLabel
        self.relatedEmailIds = relatedEmailIds
        self.confidence = confidence
        self.createdAt = createdAt
        self.isDismissed = isDismissed
    }
}

enum SuggestionType: String, Codable, CaseIterable {
    case summarize = "Summarize Thread"
    case compare = "Compare Discussions"
    case toneChange = "Tone Change Detected"
    case actionItems = "Action Items Found"
    case followUp = "Follow-Up Needed"
    case duplicate = "Duplicate Discussion"
    case missedReply = "Missed Reply"
}

// MARK: - Draft

/// AI-generated email draft
struct EmailDraft: Identifiable, Codable {
    let id: UUID
    var to: String
    var subject: String
    var body: String
    var inReplyTo: String? // Email ID being replied to
    var conversationContext: UUID? // Conversation that generated this
    var tone: DraftTone
    var suggestedAttachments: [String]
    var createdAt: Date
    var isEdited: Bool

    init(
        id: UUID = UUID(),
        to: String,
        subject: String,
        body: String,
        inReplyTo: String? = nil,
        conversationContext: UUID? = nil,
        tone: DraftTone = .professional,
        suggestedAttachments: [String] = [],
        createdAt: Date = Date(),
        isEdited: Bool = false
    ) {
        self.id = id
        self.to = to
        self.subject = subject
        self.body = body
        self.inReplyTo = inReplyTo
        self.conversationContext = conversationContext
        self.tone = tone
        self.suggestedAttachments = suggestedAttachments
        self.createdAt = createdAt
        self.isEdited = isEdited
    }
}

enum DraftTone: String, Codable, CaseIterable {
    case professional = "Professional"
    case friendly = "Friendly"
    case formal = "Formal"
    case concise = "Concise"
    case detailed = "Detailed"
}

// MARK: - Persona

/// Represents an email sender's communication style for persona chat
struct EmailPersona: Identifiable, Codable, Hashable {
    let id: UUID
    let email: String
    let name: String
    var communicationStyle: String
    var commonPhrases: [String]
    var topicExpertise: [String]
    var sentimentProfile: String
    var averageResponseTime: String
    var sampleEmails: [String] // Email IDs for context

    init(
        id: UUID = UUID(),
        email: String,
        name: String,
        communicationStyle: String = "",
        commonPhrases: [String] = [],
        topicExpertise: [String] = [],
        sentimentProfile: String = "Neutral",
        averageResponseTime: String = "Unknown",
        sampleEmails: [String] = []
    ) {
        self.id = id
        self.email = email
        self.name = name
        self.communicationStyle = communicationStyle
        self.commonPhrases = commonPhrases
        self.topicExpertise = topicExpertise
        self.sentimentProfile = sentimentProfile
        self.averageResponseTime = averageResponseTime
        self.sampleEmails = sampleEmails
    }
}

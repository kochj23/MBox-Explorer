//
//  PersonaChat.swift
//  MBox Explorer
//
//  AI impersonation of email senders for perspective understanding
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation

/// Enables chatting "as" an email sender to understand their perspective
@MainActor
class PersonaChat: ObservableObject {
    static let shared = PersonaChat()

    @Published var availablePersonas: [EmailPersona] = []
    @Published var activePersona: EmailPersona?
    @Published var personaConversation: [PersonaMessage] = []
    @Published var isGenerating = false

    private let aiBackend = AIBackendManager.shared

    private init() {}

    // MARK: - Persona Management

    /// Build personas from email archive
    func buildPersonas(from emails: [Email]) async {
        var personaData: [String: PersonaBuilder] = [:]

        for email in emails {
            let normalizedEmail = normalizeEmail(email.from)
            let name = extractName(from: email.from)

            if personaData[normalizedEmail] == nil {
                personaData[normalizedEmail] = PersonaBuilder(email: normalizedEmail, name: name)
            }

            personaData[normalizedEmail]?.addEmail(email)
        }

        // Build personas for people with sufficient data
        var builtPersonas: [EmailPersona] = []

        for (_, builder) in personaData where builder.emailCount >= 5 {
            let persona = await buildPersona(from: builder)
            builtPersonas.append(persona)
        }

        availablePersonas = builtPersonas.sorted { $0.sampleEmails.count > $1.sampleEmails.count }
    }

    /// Start chatting with a persona
    func startPersonaChat(with persona: EmailPersona) {
        activePersona = persona
        personaConversation = []

        // Add introduction message
        let intro = PersonaMessage(
            role: .persona,
            content: "Hi, I'm speaking as \(persona.name). I can help you understand my perspective based on our email history. What would you like to know?",
            timestamp: Date()
        )
        personaConversation.append(intro)
    }

    /// Send a message to the persona
    func sendMessage(_ content: String, emails: [Email]) async -> String {
        guard let persona = activePersona else {
            return "No persona selected."
        }

        // Add user message
        let userMessage = PersonaMessage(role: .user, content: content, timestamp: Date())
        personaConversation.append(userMessage)

        isGenerating = true

        // Get relevant emails from this person
        let personaEmails = emails.filter { normalizeEmail($0.from) == persona.email }
            .sorted { ($0.dateObject ?? Date()) > ($1.dateObject ?? Date()) }
            .prefix(10)

        let emailContext = personaEmails.map { email in
            """
            Subject: \(email.subject)
            Date: \(email.date)
            ---
            \(email.body.prefix(400))
            """
        }.joined(separator: "\n\n")

        let prompt = """
        You are roleplaying as \(persona.name) (\(persona.email)).

        Communication style: \(persona.communicationStyle)
        Common phrases: \(persona.commonPhrases.joined(separator: ", "))
        Topics of expertise: \(persona.topicExpertise.joined(separator: ", "))
        Typical sentiment: \(persona.sentimentProfile)

        Here are some of their recent emails for reference:
        \(emailContext)

        The user asks: "\(content)"

        Respond as \(persona.name) would, based on their communication style and the context of their emails. Stay in character and provide helpful insight into their perspective.
        """

        do {
            let response = try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You are an AI that accurately impersonates email senders to help users understand different perspectives. Stay in character based on the provided email samples.",
                temperature: 0.7
            )

            let personaMessage = PersonaMessage(role: .persona, content: response, timestamp: Date())
            personaConversation.append(personaMessage)

            isGenerating = false
            return response
        } catch {
            isGenerating = false
            let errorMessage = "Error generating response: \(error.localizedDescription)"
            personaConversation.append(PersonaMessage(role: .persona, content: errorMessage, timestamp: Date()))
            return errorMessage
        }
    }

    /// Ask what someone would likely say about a topic
    func whatWouldTheySay(persona: EmailPersona, about topic: String, emails: [Email]) async -> String {
        let personaEmails = emails.filter { normalizeEmail($0.from) == persona.email }
            .filter { $0.subject.lowercased().contains(topic.lowercased()) || $0.body.lowercased().contains(topic.lowercased()) }
            .prefix(5)

        let context = personaEmails.isEmpty
            ? "No direct emails about this topic found."
            : personaEmails.map { "Subject: \($0.subject)\n\($0.body.prefix(300))" }.joined(separator: "\n---\n")

        let prompt = """
        Based on \(persona.name)'s communication style and history:

        Communication style: \(persona.communicationStyle)
        Common phrases: \(persona.commonPhrases.joined(separator: ", "))
        Sentiment: \(persona.sentimentProfile)

        Relevant emails about "\(topic)":
        \(context)

        What would \(persona.name) likely say about "\(topic)"? Consider:
        1. Their typical perspective and concerns
        2. How they usually frame discussions
        3. What questions they might raise
        """

        do {
            return try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You predict how someone would respond based on their communication history.",
                temperature: 0.6
            )
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    /// End persona chat
    func endPersonaChat() {
        activePersona = nil
        personaConversation = []
    }

    // MARK: - Persona Building

    private func buildPersona(from builder: PersonaBuilder) async -> EmailPersona {
        // Analyze communication style
        let style = analyzeStyle(builder.emailBodies)
        let phrases = extractCommonPhrases(builder.emailBodies)
        let topics = extractTopics(builder.subjects)
        let sentiment = analyzeSentimentProfile(builder.emailBodies)

        return EmailPersona(
            email: builder.email,
            name: builder.name,
            communicationStyle: style,
            commonPhrases: phrases,
            topicExpertise: topics,
            sentimentProfile: sentiment,
            averageResponseTime: calculateResponseTime(builder.timestamps),
            sampleEmails: builder.emailIds
        )
    }

    private func analyzeStyle(_ bodies: [String]) -> String {
        let combinedText = bodies.joined(separator: " ")
        let avgWordCount = bodies.isEmpty ? 0 : bodies.map { $0.components(separatedBy: .whitespaces).count }.reduce(0, +) / bodies.count

        var styles: [String] = []

        // Length analysis
        if avgWordCount < 50 {
            styles.append("concise")
        } else if avgWordCount > 200 {
            styles.append("detailed")
        }

        // Formality analysis
        let formalIndicators = ["regards", "sincerely", "dear", "please find", "kindly"]
        let informalIndicators = ["hey", "hi!", "cheers", "lol", "thanks!"]

        let formalCount = formalIndicators.filter { combinedText.lowercased().contains($0) }.count
        let informalCount = informalIndicators.filter { combinedText.lowercased().contains($0) }.count

        if formalCount > informalCount {
            styles.append("formal")
        } else if informalCount > formalCount {
            styles.append("casual")
        } else {
            styles.append("balanced")
        }

        // Question frequency
        let questionCount = combinedText.filter { $0 == "?" }.count
        if Double(questionCount) / Double(bodies.count) > 2 {
            styles.append("inquisitive")
        }

        return styles.isEmpty ? "Standard professional" : styles.joined(separator: ", ")
    }

    private func extractCommonPhrases(_ bodies: [String]) -> [String] {
        var phraseCounts: [String: Int] = [:]

        for body in bodies {
            let sentences = body.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            for sentence in sentences {
                let trimmed = sentence.trimmingCharacters(in: .whitespaces).lowercased()
                if trimmed.count >= 10 && trimmed.count <= 50 {
                    phraseCounts[trimmed, default: 0] += 1
                }
            }
        }

        return phraseCounts
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key.capitalized }
    }

    private func extractTopics(_ subjects: [String]) -> [String] {
        var wordCounts: [String: Int] = [:]
        let stopWords = Set(["re:", "fw:", "fwd:", "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with"])

        for subject in subjects {
            let words = subject.lowercased()
                .components(separatedBy: .whitespaces)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count > 3 && !stopWords.contains($0) }

            for word in words {
                wordCounts[word, default: 0] += 1
            }
        }

        return wordCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key.capitalized }
    }

    private func analyzeSentimentProfile(_ bodies: [String]) -> String {
        let combinedText = bodies.joined(separator: " ").lowercased()

        let positiveIndicators = ["thank", "appreciate", "great", "excellent", "happy", "pleased"]
        let negativeIndicators = ["concern", "issue", "problem", "unfortunately", "disappointed"]

        let positiveCount = positiveIndicators.filter { combinedText.contains($0) }.count
        let negativeCount = negativeIndicators.filter { combinedText.contains($0) }.count

        if positiveCount > negativeCount * 2 {
            return "Generally positive and appreciative"
        } else if negativeCount > positiveCount * 2 {
            return "Often raises concerns"
        } else if positiveCount > negativeCount {
            return "Moderately positive"
        } else {
            return "Neutral/professional"
        }
    }

    private func calculateResponseTime(_ timestamps: [Date]) -> String {
        // This would need reply tracking to be accurate
        return "Unknown"
    }

    // MARK: - Helpers

    private func normalizeEmail(_ email: String) -> String {
        if let emailMatch = email.range(of: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, options: .regularExpression) {
            return String(email[emailMatch]).lowercased()
        }
        return email.lowercased()
    }

    private func extractName(from email: String) -> String {
        if let nameMatch = email.range(of: #"^[^<]+"#, options: .regularExpression) {
            let name = String(email[nameMatch]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !name.contains("@") {
                return name
            }
        }
        if let atIndex = email.firstIndex(of: "@") {
            return String(email[..<atIndex]).replacingOccurrences(of: ".", with: " ").capitalized
        }
        return email
    }
}

// MARK: - Supporting Types

struct PersonaMessage: Identifiable {
    let id = UUID()
    let role: PersonaRole
    let content: String
    let timestamp: Date
}

enum PersonaRole: String {
    case user
    case persona
}

private class PersonaBuilder {
    let email: String
    let name: String
    var emailBodies: [String] = []
    var subjects: [String] = []
    var timestamps: [Date] = []
    var emailIds: [String] = []

    var emailCount: Int { emailIds.count }

    init(email: String, name: String) {
        self.email = email
        self.name = name
    }

    func addEmail(_ email: Email) {
        emailBodies.append(email.body)
        subjects.append(email.subject)
        if let date = email.dateObject {
            timestamps.append(date)
        }
        emailIds.append(email.id.uuidString)
    }
}

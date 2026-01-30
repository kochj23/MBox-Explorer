//
//  DraftGenerator.swift
//  MBox Explorer
//
//  AI-powered email draft generation from conversation context
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation

/// Generates email drafts based on conversation context
@MainActor
class DraftGenerator: ObservableObject {
    static let shared = DraftGenerator()

    @Published var currentDraft: EmailDraft?
    @Published var isGenerating = false
    @Published var writingStyleProfile: WritingStyleProfile?

    private let aiBackend = AIBackendManager.shared
    private let database = ConversationDatabase.shared

    private init() {}

    // MARK: - Draft Generation

    /// Generate a reply to an email based on conversation context
    func generateReply(
        to email: Email,
        instructions: String,
        tone: DraftTone = .professional,
        conversationContext: Conversation? = nil
    ) async -> EmailDraft {
        isGenerating = true

        // Build context from conversation
        var contextText = ""
        if let conversation = conversationContext {
            let recentMessages = conversation.messages.suffix(5)
            contextText = recentMessages.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
        }

        let prompt = """
        Generate a professional email reply.

        ORIGINAL EMAIL:
        From: \(email.from)
        Subject: \(email.subject)
        Date: \(email.date)
        ---
        \(email.body.prefix(1000))

        USER INSTRUCTIONS: \(instructions)

        TONE: \(tone.rawValue)

        \(contextText.isEmpty ? "" : "CONVERSATION CONTEXT:\n\(contextText)")

        \(writingStyleProfile.map { "WRITING STYLE: \($0.description)" } ?? "")

        Generate ONLY the email body (no subject line, no greeting). Start directly with the content.
        Keep it concise and professional.
        """

        do {
            let body = try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You are an expert email writer. Generate professional, clear email replies.",
                temperature: 0.7
            )

            let draft = EmailDraft(
                to: email.from,
                subject: generateReplySubject(email.subject),
                body: body,
                inReplyTo: email.id.uuidString,
                conversationContext: conversationContext?.id,
                tone: tone,
                suggestedAttachments: extractSuggestedAttachments(from: body)
            )

            currentDraft = draft
            isGenerating = false

            return draft
        } catch {
            let errorDraft = EmailDraft(
                to: email.from,
                subject: generateReplySubject(email.subject),
                body: "Error generating draft: \(error.localizedDescription)",
                inReplyTo: email.id.uuidString,
                tone: tone
            )

            isGenerating = false
            return errorDraft
        }
    }

    /// Generate a new email from scratch
    func generateEmail(
        to recipient: String,
        about topic: String,
        instructions: String,
        tone: DraftTone = .professional,
        referenceEmails: [Email] = []
    ) async -> EmailDraft {
        isGenerating = true

        let referenceContext = referenceEmails.isEmpty ? "" : """

        REFERENCE EMAILS FOR CONTEXT:
        \(referenceEmails.prefix(3).map { "Subject: \($0.subject)\n\($0.body.prefix(300))" }.joined(separator: "\n---\n"))
        """

        let prompt = """
        Generate a professional email.

        RECIPIENT: \(recipient)
        TOPIC: \(topic)
        USER INSTRUCTIONS: \(instructions)
        TONE: \(tone.rawValue)
        \(referenceContext)

        \(writingStyleProfile.map { "WRITING STYLE: \($0.description)" } ?? "")

        Generate:
        1. A clear, concise subject line
        2. The email body

        Format as:
        SUBJECT: [subject line]
        ---
        [email body]
        """

        do {
            let response = try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You are an expert email writer. Generate clear, professional emails.",
                temperature: 0.7
            )

            let (subject, body) = parseGeneratedEmail(response, defaultSubject: "RE: \(topic)")

            let draft = EmailDraft(
                to: recipient,
                subject: subject,
                body: body,
                tone: tone,
                suggestedAttachments: extractSuggestedAttachments(from: body)
            )

            currentDraft = draft
            isGenerating = false

            return draft
        } catch {
            let errorDraft = EmailDraft(
                to: recipient,
                subject: "RE: \(topic)",
                body: "Error generating draft: \(error.localizedDescription)",
                tone: tone
            )

            isGenerating = false
            return errorDraft
        }
    }

    /// Improve an existing draft
    func improveDraft(_ draft: EmailDraft, instructions: String) async -> EmailDraft {
        isGenerating = true

        let prompt = """
        Improve this email draft based on the instructions:

        CURRENT DRAFT:
        To: \(draft.to)
        Subject: \(draft.subject)
        ---
        \(draft.body)

        IMPROVEMENT INSTRUCTIONS: \(instructions)

        Provide the improved email body only.
        """

        do {
            let improvedBody = try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You are an expert email editor. Improve emails while maintaining their core message.",
                temperature: 0.5
            )

            var improved = draft
            improved.body = improvedBody
            improved.isEdited = true

            currentDraft = improved
            isGenerating = false

            return improved
        } catch {
            isGenerating = false
            return draft
        }
    }

    /// Change the tone of a draft
    func changeTone(_ draft: EmailDraft, to newTone: DraftTone) async -> EmailDraft {
        isGenerating = true

        let prompt = """
        Rewrite this email with a \(newTone.rawValue.lowercased()) tone:

        ORIGINAL:
        \(draft.body)

        Keep the same information but adjust the tone to be more \(newTone.rawValue.lowercased()).
        """

        do {
            let rewrittenBody = try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You are an expert at adjusting email tone.",
                temperature: 0.6
            )

            var updated = draft
            updated.body = rewrittenBody
            updated.tone = newTone
            updated.isEdited = true

            currentDraft = updated
            isGenerating = false

            return updated
        } catch {
            isGenerating = false
            return draft
        }
    }

    // MARK: - Writing Style Learning

    /// Learn user's writing style from their sent emails
    func learnWritingStyle(from sentEmails: [Email]) async {
        guard sentEmails.count >= 5 else {
            writingStyleProfile = nil
            return
        }

        // Analyze patterns
        let avgLength = sentEmails.map { $0.body.count }.reduce(0, +) / sentEmails.count
        let commonPhrases = extractCommonPhrases(from: sentEmails.map { $0.body })
        let greetings = extractGreetings(from: sentEmails.map { $0.body })
        let closings = extractClosings(from: sentEmails.map { $0.body })

        writingStyleProfile = WritingStyleProfile(
            averageLength: avgLength,
            commonPhrases: commonPhrases,
            preferredGreetings: greetings,
            preferredClosings: closings,
            formality: analyzeFormality(sentEmails.map { $0.body })
        )
    }

    // MARK: - Helpers

    private func generateReplySubject(_ originalSubject: String) -> String {
        if originalSubject.lowercased().hasPrefix("re:") {
            return originalSubject
        }
        return "Re: \(originalSubject)"
    }

    private func parseGeneratedEmail(_ response: String, defaultSubject: String) -> (subject: String, body: String) {
        let lines = response.components(separatedBy: "\n")

        var subject = defaultSubject
        var bodyStartIndex = 0

        for (index, line) in lines.enumerated() {
            if line.uppercased().hasPrefix("SUBJECT:") {
                subject = line.replacingOccurrences(of: "SUBJECT:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
            } else if line == "---" || line == "—" {
                bodyStartIndex = index + 1
                break
            }
        }

        let body = lines.dropFirst(bodyStartIndex).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        return (subject, body.isEmpty ? response : body)
    }

    private func extractSuggestedAttachments(from text: String) -> [String] {
        var suggestions: [String] = []

        let patterns = [
            "attached", "attaching", "please find", "enclosed",
            "send you the", "include the"
        ]

        let lowerText = text.lowercased()
        for pattern in patterns {
            if lowerText.contains(pattern) {
                // Look for file types mentioned
                let filePatterns = ["document", "file", "spreadsheet", "presentation", "report", "pdf"]
                for filePattern in filePatterns {
                    if lowerText.contains(filePattern) {
                        suggestions.append(filePattern.capitalized)
                    }
                }
            }
        }

        return Array(Set(suggestions))
    }

    private func extractCommonPhrases(from bodies: [String]) -> [String] {
        var phraseCounts: [String: Int] = [:]

        for body in bodies {
            let sentences = body.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            for sentence in sentences {
                let trimmed = sentence.trimmingCharacters(in: .whitespaces)
                if trimmed.count >= 10 && trimmed.count <= 60 {
                    phraseCounts[trimmed.lowercased(), default: 0] += 1
                }
            }
        }

        return phraseCounts
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key.capitalized }
    }

    private func extractGreetings(from bodies: [String]) -> [String] {
        let greetingPatterns = ["hi", "hello", "dear", "good morning", "good afternoon", "hey"]
        var found: [String: Int] = [:]

        for body in bodies {
            let firstLine = body.components(separatedBy: .newlines).first?.lowercased() ?? ""
            for pattern in greetingPatterns {
                if firstLine.contains(pattern) {
                    found[pattern.capitalized, default: 0] += 1
                }
            }
        }

        return found.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
    }

    private func extractClosings(from bodies: [String]) -> [String] {
        let closingPatterns = ["regards", "best", "thanks", "cheers", "sincerely", "kind regards"]
        var found: [String: Int] = [:]

        for body in bodies {
            let lines = body.components(separatedBy: .newlines)
            let lastLines = lines.suffix(3).joined(separator: " ").lowercased()
            for pattern in closingPatterns {
                if lastLines.contains(pattern) {
                    found[pattern.capitalized, default: 0] += 1
                }
            }
        }

        return found.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
    }

    private func analyzeFormality(_ bodies: [String]) -> Formality {
        let combinedText = bodies.joined(separator: " ").lowercased()

        let formalIndicators = ["please find", "kindly", "sincerely", "regards", "dear", "pursuant"]
        let informalIndicators = ["hey", "lol", "thanks!", "cheers", "cool", "awesome"]

        let formalCount = formalIndicators.filter { combinedText.contains($0) }.count
        let informalCount = informalIndicators.filter { combinedText.contains($0) }.count

        if formalCount > informalCount * 2 {
            return .formal
        } else if informalCount > formalCount * 2 {
            return .casual
        }
        return .professional
    }
}

// MARK: - Supporting Types

struct WritingStyleProfile {
    let averageLength: Int
    let commonPhrases: [String]
    let preferredGreetings: [String]
    let preferredClosings: [String]
    let formality: Formality

    var description: String {
        """
        Average email length: \(averageLength) characters
        Common phrases: \(commonPhrases.joined(separator: ", "))
        Preferred greetings: \(preferredGreetings.joined(separator: ", "))
        Preferred closings: \(preferredClosings.joined(separator: ", "))
        Formality: \(formality.rawValue)
        """
    }
}

enum Formality: String {
    case formal = "Formal"
    case professional = "Professional"
    case casual = "Casual"
}

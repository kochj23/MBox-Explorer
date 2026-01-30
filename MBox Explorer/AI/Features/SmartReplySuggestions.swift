//
//  SmartReplySuggestions.swift
//  MBox Explorer
//
//  AI-powered reply suggestions for emails
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import SwiftUI

class SmartReplyGenerator: ObservableObject {
    static let shared = SmartReplyGenerator()

    @Published var isGenerating = false
    @Published var suggestions: [ReplySuggestion] = []
    @Published var fullReply: String = ""

    private let llm = LocalLLM.shared

    // MARK: - Quick Suggestions

    func generateQuickReplies(for email: Email) async -> [ReplySuggestion] {
        await MainActor.run {
            isGenerating = true
            suggestions = []
        }

        defer {
            Task { @MainActor in
                isGenerating = false
            }
        }

        let prompt = """
        Generate 4 short reply suggestions for this email. Each should be 1-2 sentences.
        Include a variety of tones: professional, friendly, brief, and detailed.

        From: \(email.from)
        Subject: \(email.subject)
        Date: \(email.date)

        Content:
        \(email.body.prefix(2000))

        Format each reply as:
        TONE: [Professional/Friendly/Brief/Detailed]
        REPLY: [The reply text]
        ---

        Suggestions:
        """

        let response = await llm.summarize(content: prompt)
        let parsed = parseQuickReplies(response)

        await MainActor.run {
            suggestions = parsed
        }

        return parsed
    }

    private func parseQuickReplies(_ response: String) -> [ReplySuggestion] {
        var replies: [ReplySuggestion] = []
        let blocks = response.components(separatedBy: "---")

        for block in blocks {
            guard !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            var tone: ReplyTone = .professional
            var text = ""

            let lines = block.components(separatedBy: .newlines)
            for line in lines {
                let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }

                let key = parts[0].uppercased()
                let value = parts[1]

                switch key {
                case "TONE":
                    tone = ReplyTone(rawValue: value.lowercased()) ?? .professional
                case "REPLY":
                    text = value
                default:
                    break
                }
            }

            guard !text.isEmpty else { continue }

            replies.append(ReplySuggestion(
                id: UUID(),
                tone: tone,
                text: text,
                isQuick: true
            ))
        }

        return replies
    }

    // MARK: - Full Reply Generation

    func generateFullReply(for email: Email, tone: ReplyTone, includeQuote: Bool = true) async -> String {
        await MainActor.run {
            isGenerating = true
            fullReply = ""
        }

        defer {
            Task { @MainActor in
                isGenerating = false
            }
        }

        let toneInstructions: String = {
            switch tone {
            case .professional:
                return "formal and professional, using proper business language"
            case .friendly:
                return "warm and friendly, with a conversational tone"
            case .brief:
                return "concise and to the point, minimal pleasantries"
            case .detailed:
                return "thorough and comprehensive, addressing all points"
            }
        }()

        let prompt = """
        Write a complete email reply to this message.
        The tone should be \(toneInstructions).

        Original Email:
        From: \(email.from)
        Subject: \(email.subject)
        Date: \(email.date)

        \(email.body.prefix(3000))

        Write ONLY the reply body (no subject line, no signature).
        Start directly with the greeting.

        Reply:
        """

        let reply = await llm.summarize(content: prompt)

        var finalReply = reply

        if includeQuote {
            let formattedDate = email.date
            let quotedOriginal = email.body
                .components(separatedBy: .newlines)
                .map { "> \($0)" }
                .joined(separator: "\n")

            finalReply += "\n\nOn \(formattedDate), \(email.from) wrote:\n\(quotedOriginal)"
        }

        await MainActor.run {
            fullReply = finalReply
        }

        return finalReply
    }

    // MARK: - Context-Aware Suggestions

    func suggestFollowUp(for threadEmails: [Email]) async -> String {
        guard !threadEmails.isEmpty else { return "" }

        let threadContext = threadEmails.suffix(5).map { email in
            "From: \(email.from)\nDate: \(email.date)\n\(email.body.prefix(500))\n---"
        }.joined(separator: "\n")

        let prompt = """
        Based on this email thread, suggest a follow-up message.
        Consider any unanswered questions or pending items.

        Thread:
        \(threadContext)

        Suggest a brief follow-up:
        """

        return await llm.summarize(content: prompt)
    }

    func generateMeetingResponse(for email: Email, response: MeetingResponse) async -> String {
        let responseText: String = {
            switch response {
            case .accept:
                return "Accept the meeting"
            case .decline:
                return "Politely decline the meeting"
            case .tentative:
                return "Tentatively accept, mention you need to confirm"
            case .proposeNew:
                return "Propose an alternative time"
            }
        }()

        let prompt = """
        Write a brief email to \(responseText).

        Original meeting request:
        From: \(email.from)
        Subject: \(email.subject)
        \(email.body.prefix(1000))

        Response (1-2 sentences):
        """

        return await llm.summarize(content: prompt)
    }
}

// MARK: - Smart Reply View

struct SmartReplyView: View {
    let email: Email
    @StateObject private var generator = SmartReplyGenerator.shared
    @State private var selectedSuggestion: ReplySuggestion?
    @State private var customReply = ""
    @State private var selectedTone: ReplyTone = .professional
    @State private var showFullReply = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Smart Reply")
                    .font(.headline)

                Spacer()

                if generator.isGenerating {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            // Quick suggestions
            if !generator.suggestions.isEmpty {
                quickSuggestionsSection
            }

            Divider()

            // Full reply generator
            fullReplySection

            // Action buttons
            HStack {
                Button("Copy Reply") {
                    copyReply()
                }

                Spacer()

                Button("Open in Mail") {
                    openInMail()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear {
            Task {
                await generator.generateQuickReplies(for: email)
            }
        }
    }

    private var quickSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Replies")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(generator.suggestions) { suggestion in
                QuickReplyButton(
                    suggestion: suggestion,
                    isSelected: selectedSuggestion?.id == suggestion.id,
                    action: {
                        selectedSuggestion = suggestion
                        customReply = suggestion.text
                    }
                )
            }
        }
    }

    private var fullReplySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Generate Full Reply")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Picker("Tone", selection: $selectedTone) {
                    ForEach(ReplyTone.allCases, id: \.self) { tone in
                        Text(tone.rawValue.capitalized).tag(tone)
                    }
                }
                .frame(width: 150)

                Button("Generate") {
                    Task {
                        await generator.generateFullReply(for: email, tone: selectedTone)
                        customReply = generator.fullReply
                    }
                }
            }

            TextEditor(text: $customReply)
                .font(.body)
                .frame(minHeight: 150)
                .border(Color.gray.opacity(0.3))
        }
    }

    private func copyReply() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(customReply, forType: .string)
    }

    private func openInMail() {
        guard let encoded = customReply.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }

        let replySubject = email.subject.hasPrefix("Re:") ? email.subject : "Re: \(email.subject)"
        let encodedSubject = replySubject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let toEmail = extractEmail(from: email.from).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "mailto:\(toEmail)?subject=\(encodedSubject)&body=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func extractEmail(from address: String) -> String {
        if let startRange = address.range(of: "<"),
           let endRange = address.range(of: ">") {
            return String(address[startRange.upperBound..<endRange.lowerBound])
        }
        return address
    }
}

struct QuickReplyButton: View {
    let suggestion: ReplySuggestion
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: suggestion.tone.icon)
                    .foregroundColor(suggestion.tone.color)

                Text(suggestion.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.windowBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Models

struct ReplySuggestion: Identifiable {
    let id: UUID
    let tone: ReplyTone
    let text: String
    let isQuick: Bool
}

enum ReplyTone: String, CaseIterable {
    case professional
    case friendly
    case brief
    case detailed

    var icon: String {
        switch self {
        case .professional: return "briefcase"
        case .friendly: return "face.smiling"
        case .brief: return "bolt"
        case .detailed: return "doc.text"
        }
    }

    var color: Color {
        switch self {
        case .professional: return .blue
        case .friendly: return .green
        case .brief: return .orange
        case .detailed: return .purple
        }
    }
}

enum MeetingResponse {
    case accept
    case decline
    case tentative
    case proposeNew
}

#Preview {
    SmartReplyView(email: Email(
        id: UUID(),
        from: "test@example.com",
        to: "you@example.com",
        subject: "Meeting Request",
        date: "Jan 30, 2026",
        body: "Can we schedule a meeting to discuss the project?"
    ))
}

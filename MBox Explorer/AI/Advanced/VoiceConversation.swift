//
//  VoiceConversation.swift
//  MBox Explorer
//
//  Voice-based interaction with email archive
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation
import Speech
import AVFoundation

#if os(iOS)
import AVFAudio
#endif

/// Enables voice-based interaction with email archive
@MainActor
class VoiceConversation: NSObject, ObservableObject {
    static let shared = VoiceConversation()

    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var transcribedText = ""
    @Published var lastSpokenResponse = ""
    @Published var isAvailable = false
    @Published var errorMessage: String?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()

    private let conversationManager = ConversationManager.shared

    private override init() {
        super.init()
        setupSpeechRecognition()
    }

    // MARK: - Setup

    private func setupSpeechRecognition() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.isAvailable = true
                case .denied, .restricted, .notDetermined:
                    self?.isAvailable = false
                    self?.errorMessage = "Speech recognition not authorized"
                @unknown default:
                    self?.isAvailable = false
                }
            }
        }
    }

    // MARK: - Speech Recognition

    /// Start listening for voice input
    func startListening() {
        guard isAvailable, !isListening else { return }

        do {
            try startRecognition()
            isListening = true
            transcribedText = ""
        } catch {
            errorMessage = "Failed to start listening: \(error.localizedDescription)"
        }
    }

    /// Stop listening and process the input
    func stopListening() {
        guard isListening else { return }

        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        isListening = false

        // Clean up
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func startRecognition() throws {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session (iOS only - macOS handles this differently)
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            throw VoiceConversationError.unableToCreateRequest
        }

        recognitionRequest.shouldReportPartialResults = true

        // Start recognition
        guard let speechRecognizer = speechRecognizer else {
            throw VoiceConversationError.recognizerUnavailable
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                DispatchQueue.main.async {
                    self.transcribedText = result.bestTranscription.formattedString
                }
            }

            if error != nil || result?.isFinal == true {
                self.audioEngine.stop()
                self.audioEngine.inputNode.removeTap(onBus: 0)
            }
        }

        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    // MARK: - Text-to-Speech

    /// Speak a response aloud
    func speak(_ text: String, rate: Float = 0.5) {
        guard !isSpeaking else { return }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        lastSpokenResponse = text
        isSpeaking = true

        synthesizer.delegate = self
        synthesizer.speak(utterance)
    }

    /// Stop speaking
    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    // MARK: - Voice Commands

    /// Process a voice command
    func processVoiceCommand(_ command: String, emails: [Email]) async -> String {
        let lowerCommand = command.lowercased()

        // Check for specific voice commands
        if lowerCommand.starts(with: "read") || lowerCommand.contains("read me") {
            return await handleReadCommand(lowerCommand, emails: emails)
        }

        if lowerCommand.starts(with: "summarize") || lowerCommand.contains("summary") {
            return await handleSummarizeCommand(lowerCommand, emails: emails)
        }

        if lowerCommand.contains("how many") || lowerCommand.contains("count") {
            return handleCountCommand(lowerCommand, emails: emails)
        }

        if lowerCommand.contains("who sent") || lowerCommand.contains("from whom") {
            return handleSenderQuery(lowerCommand, emails: emails)
        }

        if lowerCommand.contains("search for") || lowerCommand.contains("find") {
            return await handleSearchCommand(lowerCommand, emails: emails)
        }

        // Default: treat as a question to the conversation manager
        await conversationManager.sendMessage(command)
        return conversationManager.currentConversation?.messages.last?.content ?? "I couldn't process that request."
    }

    private func handleReadCommand(_ command: String, emails: [Email]) async -> String {
        // "Read me the latest email from John"
        // "Read the email about budget"

        var targetEmail: Email?

        if command.contains("latest") || command.contains("last") {
            // Check if there's a sender mentioned
            let senderPatterns = ["from (\\w+)", "by (\\w+)"]
            for pattern in senderPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)) {
                    if let nameRange = Range(match.range(at: 1), in: command) {
                        let name = String(command[nameRange])
                        targetEmail = emails.first { $0.from.lowercased().contains(name.lowercased()) }
                    }
                }
            }

            if targetEmail == nil {
                targetEmail = emails.first
            }
        } else if command.contains("about") {
            // Search by topic
            let aboutIndex = command.range(of: "about")
            if let aboutIndex = aboutIndex {
                let topic = String(command[aboutIndex.upperBound...]).trimmingCharacters(in: .whitespaces)
                targetEmail = emails.first { email in
                    email.subject.lowercased().contains(topic.lowercased()) ||
                    email.body.lowercased().contains(topic.lowercased())
                }
            }
        }

        if let email = targetEmail {
            return """
            Email from \(extractName(from: email.from)), subject: \(email.subject).
            Sent on \(email.date).
            The message says: \(email.body.prefix(500))
            """
        }

        return "I couldn't find that email."
    }

    private func handleSummarizeCommand(_ command: String, emails: [Email]) async -> String {
        // "Summarize my emails from today"
        // "Give me a summary of the project thread"

        let recentEmails = emails.prefix(10)
        let summaryPoints = recentEmails.map { "From \(extractName(from: $0.from)): \($0.subject)" }

        return """
        Here's a summary of your recent emails:
        \(summaryPoints.joined(separator: ". "))
        """
    }

    private func handleCountCommand(_ command: String, emails: [Email]) -> String {
        // "How many unread emails do I have"
        // "Count emails from this week"

        if command.contains("today") {
            let today = Calendar.current.startOfDay(for: Date())
            let count = emails.filter { email in
                guard let date = email.dateObject else { return false }
                return date >= today
            }.count
            return "You have \(count) emails from today."
        }

        if command.contains("this week") {
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            let count = emails.filter { email in
                guard let date = email.dateObject else { return false }
                return date >= weekAgo
            }.count
            return "You have \(count) emails from this week."
        }

        return "You have \(emails.count) emails in total."
    }

    private func handleSenderQuery(_ command: String, emails: [Email]) -> String {
        // Count by sender
        var senderCounts: [String: Int] = [:]
        for email in emails {
            let sender = extractName(from: email.from)
            senderCounts[sender, default: 0] += 1
        }

        let topSenders = senderCounts.sorted { $0.value > $1.value }.prefix(3)
        let senderList = topSenders.map { "\($0.key) sent \($0.value) emails" }.joined(separator: ". ")

        return "Your top senders are: \(senderList)"
    }

    private func handleSearchCommand(_ command: String, emails: [Email]) async -> String {
        // Extract search term
        let patterns = ["search for (.+)", "find (.+) emails", "find emails about (.+)"]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)) {
                if let termRange = Range(match.range(at: 1), in: command) {
                    let searchTerm = String(command[termRange])
                    let results = emails.filter { email in
                        email.subject.lowercased().contains(searchTerm.lowercased()) ||
                        email.body.lowercased().contains(searchTerm.lowercased())
                    }

                    if results.isEmpty {
                        return "I couldn't find any emails about \(searchTerm)."
                    }

                    return "I found \(results.count) emails about \(searchTerm). The most recent is from \(extractName(from: results.first!.from)) with subject: \(results.first!.subject)"
                }
            }
        }

        return "I couldn't understand what you're searching for."
    }

    private func extractName(from email: String) -> String {
        if let nameMatch = email.range(of: #"^[^<]+"#, options: .regularExpression) {
            let name = String(email[nameMatch]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !name.contains("@") {
                return name
            }
        }
        if let atIndex = email.firstIndex(of: "@") {
            return String(email[..<atIndex]).capitalized
        }
        return email
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceConversation: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}

// MARK: - Errors

enum VoiceConversationError: LocalizedError {
    case unableToCreateRequest
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .unableToCreateRequest:
            return "Unable to create speech recognition request"
        case .recognizerUnavailable:
            return "Speech recognizer is unavailable"
        }
    }
}

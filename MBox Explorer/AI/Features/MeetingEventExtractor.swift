//
//  MeetingEventExtractor.swift
//  MBox Explorer
//
//  Extract meetings, events, and calendar items from emails
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import SwiftUI
import EventKit

class MeetingEventExtractor: ObservableObject {
    static let shared = MeetingEventExtractor()

    @Published var isExtracting = false
    @Published var progress: Double = 0
    @Published var extractedEvents: [ExtractedEvent] = []

    private let llm = LocalLLM.shared
    private let eventStore = EKEventStore()

    // Common meeting phrases
    private let meetingIndicators = [
        "meeting", "call", "conference", "webinar", "sync",
        "standup", "stand-up", "1:1", "one on one", "catch up",
        "interview", "presentation", "demo", "review",
        "scheduled for", "invite you to", "join us",
        "zoom", "teams", "google meet", "webex"
    ]

    private let datePatterns = [
        "tomorrow", "next week", "this friday",
        "on monday", "on tuesday", "on wednesday", "on thursday", "on friday",
        "at \\d{1,2}(?::\\d{2})?\\s*(?:am|pm)?",
        "\\d{1,2}/\\d{1,2}(?:/\\d{2,4})?",
        "(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\\w*\\s+\\d{1,2}"
    ]

    // MARK: - Extract from Single Email

    func extractEvents(from email: Email) async throws -> [ExtractedEvent] {
        await MainActor.run {
            isExtracting = true
        }

        defer {
            Task { @MainActor in
                isExtracting = false
            }
        }

        // Quick check for meeting indicators
        let content = "\(email.subject) \(email.body)".lowercased()
        let hasMeetingKeyword = meetingIndicators.contains { content.contains($0) }

        guard hasMeetingKeyword else { return [] }

        let prompt = """
        Extract all meetings, events, and calendar items from this email.

        For each event found, identify:
        - Event title/name
        - Date and time (if mentioned)
        - Duration (if mentioned)
        - Location or meeting link
        - Attendees (if mentioned)
        - Description/agenda

        From: \(email.from)
        Subject: \(email.subject)
        Date: \(email.date)

        Content:
        \(email.body.prefix(3000))

        If no events found, respond with "NO_EVENTS".

        Format each event as:
        TITLE: [event name]
        DATE: [date/time or "TBD"]
        DURATION: [duration or "TBD"]
        LOCATION: [location/link or "TBD"]
        ATTENDEES: [comma-separated or "TBD"]
        DESCRIPTION: [brief description]
        ---

        Events:
        """

        let response = await llm.summarize(content: prompt)

        if response.contains("NO_EVENTS") {
            return []
        }

        return parseEvents(from: response, email: email)
    }

    // MARK: - Batch Extraction

    func extractAllEvents(from emails: [Email], progressCallback: ((Double) -> Void)? = nil) async throws -> [ExtractedEvent] {
        await MainActor.run {
            isExtracting = true
            progress = 0
            extractedEvents = []
        }

        defer {
            Task { @MainActor in
                isExtracting = false
            }
        }

        var allEvents: [ExtractedEvent] = []

        // Pre-filter emails with meeting indicators
        let potentialEmails = emails.filter { email in
            let content = "\(email.subject) \(email.body)".lowercased()
            return meetingIndicators.contains { content.contains($0) }
        }

        for (index, email) in potentialEmails.enumerated() {
            do {
                let events = try await extractEvents(from: email)
                allEvents.append(contentsOf: events)

                let progressValue = Double(index + 1) / Double(potentialEmails.count)
                await MainActor.run {
                    self.progress = progressValue
                    self.extractedEvents = allEvents
                }
                progressCallback?(progressValue)
            } catch {
                print("Error extracting events: \(error.localizedDescription)")
            }
        }

        return allEvents
    }

    // MARK: - Calendar Integration

    func requestCalendarAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error = error {
                    print("Calendar access error: \(error.localizedDescription)")
                }
                continuation.resume(returning: granted)
            }
        }
    }

    func addToCalendar(_ event: ExtractedEvent) async throws {
        let hasAccess = await requestCalendarAccess()
        guard hasAccess else {
            throw CalendarError.accessDenied
        }

        let ekEvent = EKEvent(eventStore: eventStore)
        ekEvent.title = event.title
        ekEvent.notes = event.description

        if let startDate = event.startDate {
            ekEvent.startDate = startDate

            if let duration = event.duration {
                ekEvent.endDate = startDate.addingTimeInterval(duration)
            } else {
                ekEvent.endDate = startDate.addingTimeInterval(3600) // Default 1 hour
            }
        } else {
            // Default to tomorrow if no date
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            ekEvent.startDate = tomorrow
            ekEvent.endDate = tomorrow.addingTimeInterval(3600)
        }

        if let location = event.location {
            ekEvent.location = location
        }

        // Set to default calendar
        ekEvent.calendar = eventStore.defaultCalendarForNewEvents

        try eventStore.save(ekEvent, span: .thisEvent)
    }

    func addAllToCalendar(_ events: [ExtractedEvent]) async throws -> Int {
        let hasAccess = await requestCalendarAccess()
        guard hasAccess else {
            throw CalendarError.accessDenied
        }

        var addedCount = 0

        for event in events {
            do {
                try await addToCalendar(event)
                addedCount += 1
            } catch {
                print("Failed to add event: \(error.localizedDescription)")
            }
        }

        return addedCount
    }

    // MARK: - Export

    func exportToICS(events: [ExtractedEvent]) -> String {
        var ics = "BEGIN:VCALENDAR\n"
        ics += "VERSION:2.0\n"
        ics += "PRODID:-//MBox Explorer//EN\n"

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"

        for event in events {
            ics += "BEGIN:VEVENT\n"
            ics += "UID:\(event.id.uuidString)@mboxexplorer\n"

            if let startDate = event.startDate {
                ics += "DTSTART:\(formatter.string(from: startDate))\n"

                let endDate = startDate.addingTimeInterval(event.duration ?? 3600)
                ics += "DTEND:\(formatter.string(from: endDate))\n"
            }

            ics += "SUMMARY:\(escapeICS(event.title))\n"

            if let description = event.description {
                ics += "DESCRIPTION:\(escapeICS(description))\n"
            }

            if let location = event.location {
                ics += "LOCATION:\(escapeICS(location))\n"
            }

            ics += "END:VEVENT\n"
        }

        ics += "END:VCALENDAR"
        return ics
    }

    private func escapeICS(_ text: String) -> String {
        text.replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    // MARK: - Parsing

    private func parseEvents(from response: String, email: Email) -> [ExtractedEvent] {
        var events: [ExtractedEvent] = []
        let blocks = response.components(separatedBy: "---")

        for block in blocks {
            guard !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            var title = ""
            var dateStr = ""
            var durationStr = ""
            var location: String?
            var attendees: [String] = []
            var description: String?

            let lines = block.components(separatedBy: .newlines)
            for line in lines {
                let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }

                let key = parts[0].uppercased()
                let value = parts[1]

                switch key {
                case "TITLE":
                    title = value
                case "DATE":
                    dateStr = value
                case "DURATION":
                    durationStr = value
                case "LOCATION":
                    if value.lowercased() != "tbd" {
                        location = value
                    }
                case "ATTENDEES":
                    if value.lowercased() != "tbd" {
                        attendees = value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                    }
                case "DESCRIPTION":
                    description = value
                default:
                    break
                }
            }

            guard !title.isEmpty else { continue }

            let event = ExtractedEvent(
                id: UUID(),
                title: title,
                startDate: parseDate(dateStr, referenceDate: email.dateObject ?? Date()),
                duration: parseDuration(durationStr),
                location: location,
                attendees: attendees,
                description: description,
                sourceEmailId: email.id,
                sourceSubject: email.subject,
                sourceFrom: email.from,
                extractedAt: Date()
            )
            events.append(event)
        }

        return events
    }

    private func parseDate(_ string: String, referenceDate: Date) -> Date? {
        let lowered = string.lowercased()

        if lowered == "tbd" || lowered.isEmpty {
            return nil
        }

        let calendar = Calendar.current

        if lowered.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: referenceDate)
        }
        if lowered.contains("next week") {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: referenceDate)
        }

        // Try standard date formats
        let formatters = [
            "MM/dd/yyyy HH:mm",
            "MM/dd/yyyy h:mm a",
            "MM/dd/yyyy",
            "yyyy-MM-dd HH:mm",
            "MMM d, yyyy h:mm a",
            "MMM d h:mm a",
            "EEEE h:mm a"
        ]

        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }

        return nil
    }

    private func parseDuration(_ string: String) -> TimeInterval? {
        let lowered = string.lowercased()

        if lowered.contains("hour") {
            if let num = extractNumber(from: lowered) {
                return TimeInterval(num * 3600)
            }
            return 3600
        }

        if lowered.contains("min") {
            if let num = extractNumber(from: lowered) {
                return TimeInterval(num * 60)
            }
            return 1800 // Default 30 min
        }

        return nil
    }

    private func extractNumber(from string: String) -> Int? {
        let pattern = "\\d+"
        if let range = string.range(of: pattern, options: .regularExpression) {
            return Int(string[range])
        }
        return nil
    }
}

// MARK: - Models

struct ExtractedEvent: Identifiable {
    let id: UUID
    let title: String
    let startDate: Date?
    let duration: TimeInterval?
    let location: String?
    let attendees: [String]
    let description: String?
    let sourceEmailId: UUID
    let sourceSubject: String
    let sourceFrom: String
    let extractedAt: Date

    var formattedDate: String {
        guard let date = startDate else { return "Date TBD" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var formattedDuration: String {
        guard let duration = duration else { return "" }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

enum CalendarError: Error, LocalizedError {
    case accessDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access denied. Please grant permission in System Preferences."
        case .saveFailed:
            return "Failed to save event to calendar."
        }
    }
}

// MARK: - Meeting Event View

struct MeetingEventView: View {
    @ObservedObject var viewModel: MboxViewModel
    @StateObject private var extractor = MeetingEventExtractor.shared
    @State private var showingExportSheet = false
    @State private var addToCalendarResult: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Meetings & Events")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if extractor.isExtracting {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("\(Int(extractor.progress * 100))%")
                        .foregroundColor(.secondary)
                } else if extractor.extractedEvents.isEmpty {
                    Button("Extract Events") {
                        Task {
                            try? await extractor.extractAllEvents(from: viewModel.emails)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    HStack(spacing: 12) {
                        Button("Add All to Calendar") {
                            addAllToCalendar()
                        }

                        Button("Export ICS") {
                            showingExportSheet = true
                        }
                    }
                }
            }
            .padding()

            if let result = addToCalendarResult {
                Text(result)
                    .padding()
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }

            Divider()

            // Events list
            if extractor.extractedEvents.isEmpty && !extractor.isExtracting {
                VStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No events extracted yet")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(extractor.extractedEvents) { event in
                    EventRow(event: event)
                }
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportICSView(events: extractor.extractedEvents)
        }
    }

    private func addAllToCalendar() {
        Task {
            do {
                let count = try await extractor.addAllToCalendar(extractor.extractedEvents)
                await MainActor.run {
                    addToCalendarResult = "Added \(count) events to Calendar"
                }

                // Clear message after delay
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    addToCalendarResult = nil
                }
            } catch {
                await MainActor.run {
                    addToCalendarResult = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct EventRow: View {
    let event: ExtractedEvent
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        Text(event.formattedDate)
                        if !event.formattedDuration.isEmpty {
                            Text("•")
                            Text(event.formattedDuration)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    addToCalendar(event)
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .help("Add to Calendar")

                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if let location = event.location {
                        Label(location, systemImage: "location")
                            .font(.caption)
                    }

                    if !event.attendees.isEmpty {
                        Label(event.attendees.joined(separator: ", "), systemImage: "person.2")
                            .font(.caption)
                    }

                    if let description = event.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("From: \(event.sourceSubject)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 24)
            }
        }
    }

    private func addToCalendar(_ event: ExtractedEvent) {
        Task {
            try? await MeetingEventExtractor.shared.addToCalendar(event)
        }
    }
}

struct ExportICSView: View {
    let events: [ExtractedEvent]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Export \(events.count) Events")
                .font(.headline)

            Text("Export events to an ICS file that can be imported into any calendar application.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Export") {
                    exportICS()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 350)
    }

    private func exportICS() {
        let ics = MeetingEventExtractor.shared.exportToICS(events: events)

        let panel = NSSavePanel()
        panel.title = "Export Events"
        panel.nameFieldStringValue = "events.ics"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                try ics.write(to: url, atomically: true, encoding: .utf8)
                dismiss()
            } catch {
                print("Failed to save ICS: \(error)")
            }
        }
    }
}

#Preview {
    MeetingEventView(viewModel: MboxViewModel())
}

//
//  ConversationView.swift
//  MBox Explorer
//
//  Multi-turn conversational AI interface for email exploration
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import SwiftUI

/// Main conversational interface for interacting with email archive
struct ConversationView: View {
    @ObservedObject var viewModel: MboxViewModel
    @StateObject private var conversationManager = ConversationManager.shared
    @StateObject private var vectorDB = VectorDatabase()
    @StateObject private var commitmentTracker = CommitmentTracker.shared
    @StateObject private var dailyBriefing = DailyBriefingEngine.shared
    @StateObject private var smartSuggestions = SmartSuggestionsEngine.shared
    @StateObject private var voiceConversation = VoiceConversation.shared

    @State private var messageInput = ""
    @State private var showConversationList = false
    @State private var showCitations = true
    @State private var selectedFeature: ConversationFeature = .chat
    @State private var showBriefing = false
    @State private var showCommitments = false

    var body: some View {
        HSplitView {
            // Sidebar - Conversation History
            if showConversationList {
                conversationSidebar
                    .frame(minWidth: 250, maxWidth: 300)
            }

            // Main Chat Area
            VStack(spacing: 0) {
                // Feature Tabs
                featureTabs

                // Content Area
                Group {
                    switch selectedFeature {
                    case .chat:
                        chatView
                    case .briefing:
                        briefingView
                    case .commitments:
                        commitmentsView
                    case .relationships:
                        relationshipsView
                    case .patterns:
                        patternsView
                    }
                }
            }

            // Citations Panel
            if showCitations && !conversationManager.currentCitations.isEmpty {
                citationsPanel
                    .frame(minWidth: 250, maxWidth: 350)
            }
        }
        .onAppear {
            conversationManager.setVectorDatabase(vectorDB)
            if !viewModel.emails.isEmpty && !vectorDB.isIndexed {
                Task {
                    await vectorDB.indexEmails(viewModel.emails) { _ in }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button(action: { showConversationList.toggle() }) {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle conversation history")

                Button(action: { conversationManager.startNewConversation() }) {
                    Image(systemName: "plus.bubble")
                }
                .help("New conversation")

                Button(action: { showCitations.toggle() }) {
                    Image(systemName: "link.circle")
                }
                .help("Toggle citations panel")

                if voiceConversation.isAvailable {
                    Button(action: toggleVoiceInput) {
                        Image(systemName: voiceConversation.isListening ? "mic.fill" : "mic")
                            .foregroundColor(voiceConversation.isListening ? .red : .primary)
                    }
                    .help("Voice input")
                }
            }
        }
    }

    // MARK: - Feature Tabs

    private var featureTabs: some View {
        HStack(spacing: 0) {
            ForEach(ConversationFeature.allCases, id: \.self) { feature in
                Button(action: { selectedFeature = feature }) {
                    VStack(spacing: 4) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 16))
                        Text(feature.rawValue)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedFeature == feature ? Color.accentColor.opacity(0.2) : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Chat View

    private var chatView: some View {
        VStack(spacing: 0) {
            // Chat Header
            chatHeader

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        // Suggestions for new conversations
                        if conversationManager.currentConversation?.messages.isEmpty ?? true {
                            suggestionCards
                        }

                        // Messages
                        ForEach(conversationManager.currentConversation?.messages ?? []) { message in
                            messageView(message)
                                .id(message.id)
                        }

                        // Streaming response
                        if conversationManager.isProcessing {
                            processingIndicator
                        }

                        // Suggested follow-ups
                        if !conversationManager.suggestedFollowUps.isEmpty && !conversationManager.isProcessing {
                            followUpSuggestions
                        }
                    }
                    .padding()
                }
                .onChange(of: conversationManager.currentConversation?.messages.count) { _ in
                    if let lastId = conversationManager.currentConversation?.messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input Area
            chatInputArea
        }
    }

    private var chatHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversationManager.currentConversation?.displayTitle ?? "New Conversation")
                    .font(.headline)

                HStack(spacing: 12) {
                    statusIndicator

                    if vectorDB.isIndexed {
                        Text("\(vectorDB.totalDocuments) emails indexed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if conversationManager.currentConversation != nil {
                Button(action: { conversationManager.toggleFavorite() }) {
                    Image(systemName: conversationManager.currentConversation?.isFavorite == true ? "star.fill" : "star")
                        .foregroundColor(conversationManager.currentConversation?.isFavorite == true ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var statusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(AIBackendManager.shared.activeBackend != nil ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            if let backend = AIBackendManager.shared.activeBackend {
                Text(backend.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("AI Unavailable")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private var suggestionCards: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What would you like to know about your emails?")
                .font(.title2)
                .fontWeight(.semibold)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                suggestionCard(
                    title: "Daily Briefing",
                    description: "Get a summary of your recent email activity",
                    icon: "sun.max.fill",
                    action: { sendMessage("Give me a daily briefing of my emails") }
                )

                suggestionCard(
                    title: "Find Commitments",
                    description: "What have I promised to do?",
                    icon: "checkmark.circle.fill",
                    action: { sendMessage("What commitments have I made?") }
                )

                suggestionCard(
                    title: "Search Topics",
                    description: "Find emails about specific subjects",
                    icon: "magnifyingglass",
                    action: { messageInput = "Find emails about " }
                )

                suggestionCard(
                    title: "Relationship Analysis",
                    description: "Analyze communication patterns",
                    icon: "person.2.fill",
                    action: { sendMessage("Who do I email most frequently?") }
                )
            }

            Text("Or type a question below...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.05))
        )
    }

    private func suggestionCard(title: String, description: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.blue)
                    Text(title)
                        .fontWeight(.medium)
                }

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }

    private func messageView(_ message: ConversationMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Image(systemName: message.role == .user ? "person.circle.fill" : "sparkles")
                .font(.system(size: 24))
                .foregroundColor(message.role == .user ? .blue : .purple)

            // Content
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(message.role == .user ? "You" : "AI Assistant")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(message.content)
                    .textSelection(.enabled)

                // Citations in message
                if !message.citations.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.citations.prefix(5)) { citation in
                            Text(citation.marker)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }

                        if message.citations.count > 5 {
                            Text("+\(message.citations.count - 5) more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()

            // Copy button
            Button(action: { copyToClipboard(message.content) }) {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .opacity(0.5)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(message.role == .user ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1))
        )
    }

    private var processingIndicator: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundColor(.purple)

            VStack(alignment: .leading) {
                Text("AI Assistant")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Thinking...")
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple.opacity(0.1))
        )
    }

    private var followUpSuggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested follow-ups:")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(conversationManager.suggestedFollowUps, id: \.self) { suggestion in
                    Button(action: { sendMessage(suggestion) }) {
                        Text(suggestion)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.blue.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var chatInputArea: some View {
        HStack(spacing: 12) {
            // Voice input indicator
            if voiceConversation.isListening {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text(voiceConversation.transcribedText.isEmpty ? "Listening..." : voiceConversation.transcribedText)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            TextField("Ask about your emails...", text: $messageInput)
                .textFieldStyle(.plain)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .onSubmit {
                    sendMessage(messageInput)
                }

            Button(action: { sendMessage(messageInput) }) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderedProminent)
            .disabled(messageInput.isEmpty || conversationManager.isProcessing)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Sidebar

    private var conversationSidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Conversations")
                    .font(.headline)
                Spacer()
                Button(action: { conversationManager.startNewConversation() }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            // Conversation List
            List(ConversationDatabase.shared.conversations) { conversation in
                Button(action: { conversationManager.loadConversation(conversation) }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if conversation.isFavorite {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundColor(.yellow)
                                }
                                Text(conversation.displayTitle)
                                    .lineLimit(1)
                            }

                            Text("\(conversation.messageCount) messages")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if conversationManager.currentConversation?.id == conversation.id {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Citations Panel

    private var citationsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Sources")
                    .font(.headline)
                Spacer()
                Text("\(conversationManager.currentCitations.count) citations")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Citations List
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(conversationManager.currentCitations) { citation in
                        citationCard(citation)
                    }
                }
                .padding()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func citationCard(_ citation: EmailCitation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(citation.marker)
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(4)

                Text(citation.confidence.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()
            }

            Text(citation.subject)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)

            Text("From: \(citation.from)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(citation.date)
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(citation.snippet)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(3)

            Button("View Email") {
                // Navigate to email
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Briefing View

    private var briefingView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Daily Briefing")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Refresh") {
                    Task {
                        await dailyBriefing.generateBriefing(emails: viewModel.emails)
                    }
                }
                .disabled(dailyBriefing.isGenerating)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            if dailyBriefing.isGenerating {
                ProgressView("Generating briefing...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let briefing = dailyBriefing.currentBriefing {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Summary
                        if !briefing.summary.isEmpty {
                            briefingSection(title: "Summary", icon: "doc.text.fill") {
                                Text(briefing.summary)
                            }
                        }

                        // Needs Response
                        if !briefing.needsResponse.isEmpty {
                            briefingSection(title: "Needs Response", icon: "exclamationmark.bubble.fill") {
                                ForEach(briefing.needsResponse) { item in
                                    briefingItemRow(item)
                                }
                            }
                        }

                        // Upcoming Deadlines
                        if !briefing.upcomingDeadlines.isEmpty {
                            briefingSection(title: "Upcoming Deadlines", icon: "calendar.badge.exclamationmark") {
                                ForEach(briefing.upcomingDeadlines) { item in
                                    briefingItemRow(item)
                                }
                            }
                        }

                        // Unusual Activity
                        if !briefing.unusualActivity.isEmpty {
                            briefingSection(title: "Unusual Activity", icon: "chart.line.uptrend.xyaxis") {
                                ForEach(briefing.unusualActivity) { item in
                                    briefingItemRow(item)
                                }
                            }
                        }

                        // Trending Topics
                        if !briefing.trendingTopics.isEmpty {
                            briefingSection(title: "Trending Topics", icon: "arrow.up.right") {
                                FlowLayout(spacing: 8) {
                                    ForEach(briefing.trendingTopics, id: \.self) { topic in
                                        Text(topic)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(12)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.yellow)

                    Text("No briefing yet")
                        .font(.headline)

                    Button("Generate Briefing") {
                        Task {
                            await dailyBriefing.generateBriefing(emails: viewModel.emails)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func briefingSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
            }

            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func briefingItemRow(_ item: BriefingItem) -> some View {
        HStack(spacing: 12) {
            if item.priority == .high {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(item.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if item.actionRequired {
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Commitments View

    private var commitmentsView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Commitments")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Scan Emails") {
                    Task {
                        await commitmentTracker.analyzeEmails(viewModel.emails)
                    }
                }
                .disabled(commitmentTracker.isAnalyzing)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            if commitmentTracker.isAnalyzing {
                ProgressView("Scanning for commitments...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if commitmentTracker.commitments.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.green)

                    Text("No commitments tracked yet")
                        .font(.headline)

                    Text("Scan your emails to extract commitments and action items")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Scan Emails") {
                        Task {
                            await commitmentTracker.analyzeEmails(viewModel.emails)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Overdue
                        let overdue = commitmentTracker.getOverdueCommitments()
                        if !overdue.isEmpty {
                            commitmentSection(title: "Overdue", color: .red, commitments: overdue)
                        }

                        // Upcoming
                        let upcoming = commitmentTracker.getCommitmentsWithUpcomingDeadlines()
                        if !upcoming.isEmpty {
                            commitmentSection(title: "Upcoming", color: .orange, commitments: upcoming)
                        }

                        // All Pending
                        let pending = commitmentTracker.getPendingCommitments()
                        if !pending.isEmpty {
                            commitmentSection(title: "Pending", color: .blue, commitments: pending)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func commitmentSection(title: String, color: Color, commitments: [Commitment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.headline)
                Text("(\(commitments.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(commitments) { commitment in
                commitmentRow(commitment)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func commitmentRow(_ commitment: Commitment) -> some View {
        HStack(spacing: 12) {
            Button(action: { commitmentTracker.markCommitmentComplete(commitment) }) {
                Image(systemName: commitment.status == .completed ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(commitment.status == .completed ? .green : .secondary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                Text(commitment.description)
                    .font(.subheadline)
                    .strikethrough(commitment.status == .completed)

                HStack(spacing: 8) {
                    Text(commitment.committer)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let deadline = commitment.deadline {
                        Text("Due: \(deadline, style: .date)")
                            .font(.caption)
                            .foregroundColor(commitment.isOverdue ? .red : .secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Relationships View

    private var relationshipsView: some View {
        VStack {
            Text("Relationship Mapper")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Analyze communication patterns and relationships")
                .foregroundColor(.secondary)

            Button("Analyze Relationships") {
                Task {
                    await RelationshipMapper.shared.analyzeEmails(viewModel.emails)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Patterns View

    private var patternsView: some View {
        VStack {
            Text("Pattern Detection")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Identify recurring patterns in your communications")
                .foregroundColor(.secondary)

            Button("Detect Patterns") {
                Task {
                    await PatternDetector.shared.analyzePatterns(in: viewModel.emails)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }
        messageInput = ""

        Task {
            await conversationManager.sendMessage(text)
        }
    }

    private func toggleVoiceInput() {
        if voiceConversation.isListening {
            voiceConversation.stopListening()
            if !voiceConversation.transcribedText.isEmpty {
                sendMessage(voiceConversation.transcribedText)
            }
        } else {
            voiceConversation.startListening()
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Supporting Types

enum ConversationFeature: String, CaseIterable {
    case chat = "Chat"
    case briefing = "Briefing"
    case commitments = "Commitments"
    case relationships = "Relationships"
    case patterns = "Patterns"

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .briefing: return "sun.max"
        case .commitments: return "checkmark.circle"
        case .relationships: return "person.2"
        case .patterns: return "chart.bar"
        }
    }
}

// MARK: - Flow Layout (for tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

#Preview {
    ConversationView(viewModel: MboxViewModel())
}

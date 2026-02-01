//
//  AskView.swift
//  MBox Explorer
//
//  Enhanced Chat interface with RAG Pipeline for querying emails with AI
//  Author: Jordan Koch
//  Date: 2025-12-03
//  Updated: 2025-01-30 - Added debug mode, conversation memory, export, sources display
//

import SwiftUI

struct AskView: View {
    @ObservedObject var viewModel: MboxViewModel
    @StateObject private var vectorDB = VectorDatabase()
    @StateObject private var llm = LocalLLM()

    @State private var question = ""
    @State private var currentRAGResult: RAGResult?
    @State private var queryHistory: [QueryHistoryItem] = []
    @State private var isQuerying = false
    @State private var showDebugPanel = false
    @State private var showSourcesPanel = false
    @State private var showExportSheet = false
    @State private var showSettingsSheet = false
    @State private var selectedSource: SearchResult?

    var body: some View {
        HSplitView {
            // Main chat area
            mainChatView

            // Debug panel (collapsible)
            if showDebugPanel {
                debugPanel
                    .frame(minWidth: 300, maxWidth: 400)
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportConversationSheet(llm: llm, isPresented: $showExportSheet)
        }
        .sheet(isPresented: $showSettingsSheet) {
            RAGSettingsSheet(llm: llm, isPresented: $showSettingsSheet)
        }
        .onChange(of: viewModel.currentFileURL) { oldValue, newValue in
            // Clear the RAG index when a new MBOX file is loaded to prevent cross-contamination
            if newValue != nil && newValue != oldValue {
                vectorDB.clearIndex()
                queryHistory.removeAll()
                currentRAGResult = nil
                llm.clearConversation()
            }
        }
    }

    // MARK: - Main Chat View

    private var mainChatView: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Chat area
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Query history
                    ForEach(queryHistory) { item in
                        queryHistoryCard(item)
                    }

                    // Examples (when empty)
                    if queryHistory.isEmpty {
                        examplesCard()
                    }
                }
                .padding()
            }

            Divider()

            // Input area
            inputArea
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ask About Your Emails")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)

                    // Status bar
                    HStack(spacing: 12) {
                        // AI Status
                        HStack(spacing: 4) {
                            Circle()
                                .fill(llm.isAvailable ? .green : .orange)
                                .frame(width: 8, height: 8)
                            Text(llm.isAvailable ? "AI Connected" : "AI Offline")
                                .font(.caption)
                                .foregroundColor(llm.isAvailable ? .green : .orange)

                            if let backend = llm.getActiveBackend() {
                                Text("(\(backend.rawValue))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Index status
                        if vectorDB.isIndexed {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("\(vectorDB.totalDocuments) emails indexed")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        } else if !viewModel.emails.isEmpty {
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text("Basic search mode")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                indexButton
                            }
                        }

                        // Conversation memory indicator
                        if llm.useConversationMemory && !llm.conversationHistory.isEmpty {
                            Text("• \(llm.conversationHistory.count / 2) turns in memory")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    // Debug toggle
                    Toggle(isOn: $showDebugPanel) {
                        Image(systemName: "ladybug")
                    }
                    .toggleStyle(.button)
                    .help("Show AI Debug Panel")

                    // Export button
                    Button(action: { showExportSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(queryHistory.isEmpty)
                    .help("Export Conversation")

                    // Clear conversation
                    Button(action: clearConversation) {
                        Image(systemName: "trash")
                    }
                    .disabled(queryHistory.isEmpty)
                    .help("Clear Conversation")

                    // Settings
                    Button(action: { showSettingsSheet = true }) {
                        Image(systemName: "gear")
                    }
                    .help("RAG Settings")
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var indexButton: some View {
        Button(action: {
            Task {
                // Clear any existing index first to prevent cross-contamination from previous MBOX files
                vectorDB.clearIndex()
                await vectorDB.indexEmails(viewModel.emails) { _ in }
            }
        }) {
            if vectorDB.indexProgress > 0 && vectorDB.indexProgress < 1.0 {
                HStack {
                    Text("Indexing... \(Int(vectorDB.indexProgress * 100))%")
                    ProgressView()
                        .scaleEffect(0.7)
                }
            } else {
                Text("Index Emails")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                TextField("Ask a question about your emails...", text: $question)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .onSubmit {
                        askQuestion()
                    }

                Button(action: askQuestion) {
                    HStack {
                        if isQuerying {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text("Ask")
                    }
                    .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(question.isEmpty || isQuerying)
            }

            // Quick questions
            HStack(spacing: 8) {
                Text("Try:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                quickQuestionButton("How many emails?")
                quickQuestionButton("Top senders?")
                quickQuestionButton("Date range?")
                quickQuestionButton("Summarize themes")
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Debug Panel

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AI Debug Panel")
                    .font(.headline)
                Spacer()
                Button(action: { showDebugPanel = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let result = currentRAGResult {
                        // Question Type
                        debugSection("Question Type") {
                            Text(questionTypeDescription(result.questionType))
                                .font(.system(.body, design: .monospaced))
                        }

                        // Processing Time
                        debugSection("Processing Time") {
                            Text(String(format: "%.2f seconds", result.processingTime))
                                .font(.system(.body, design: .monospaced))
                        }

                        // Sources Used
                        debugSection("Sources Used") {
                            Text("\(result.sourcesUsed.count) emails")
                                .font(.system(.body, design: .monospaced))
                        }

                        // System Prompt
                        debugSection("System Prompt") {
                            Text(result.systemPromptUsed)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }

                        // Full Prompt Sent
                        debugSection("Full Prompt Sent") {
                            Text(result.promptSent)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    } else {
                        Text("Ask a question to see debug info")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                }
                .padding()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func debugSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            content()
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
        }
    }

    private func questionTypeDescription(_ type: QuestionType) -> String {
        switch type {
        case .statistics: return "STATISTICS (count/total questions)"
        case .topList: return "TOP_LIST (ranking questions)"
        case .dateRange: return "DATE_RANGE (time-based questions)"
        case .contentSearch: return "CONTENT_SEARCH (find specific content)"
        case .summary: return "SUMMARY (overview/themes)"
        case .followUp: return "FOLLOW_UP (references previous Q&A)"
        }
    }

    // MARK: - Query History Card

    private func queryHistoryCard(_ item: QueryHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.blue)
                Text(item.question)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                // Question type badge
                if let type = item.questionType {
                    Text(questionTypeBadge(type))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.blue.opacity(0.2)))
                }

                Text(item.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Answer
            Text(item.answer)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.1))
                )

            // Sources section
            if !item.sources.isEmpty {
                sourcesSection(item.sources)
            }

            // Processing info
            if let time = item.processingTime {
                HStack {
                    Spacer()
                    Text("Processed in \(String(format: "%.2fs", time)) • \(item.sources.count) sources")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }

    private func sourcesSection(_ sources: [SearchResult]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sources (\(sources.count) emails)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { showSourcesPanel.toggle() }) {
                    Text(showSourcesPanel ? "Hide" : "Show All")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            // Show first 3 or all if expanded
            let displaySources = showSourcesPanel ? sources : Array(sources.prefix(3))

            ForEach(displaySources) { source in
                sourceRow(source)
            }
        }
    }

    private func sourceRow(_ source: SearchResult) -> some View {
        Button(action: {
            // TODO: Navigate to email in main view
            selectedSource = source
        }) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                    .font(.caption)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.subject)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text("\(source.from) • \(source.date)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }

    private func questionTypeBadge(_ type: QuestionType) -> String {
        switch type {
        case .statistics: return "Stats"
        case .topList: return "Ranking"
        case .dateRange: return "Dates"
        case .contentSearch: return "Search"
        case .summary: return "Summary"
        case .followUp: return "Follow-up"
        }
    }

    // MARK: - Examples Card

    private func examplesCard() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Example Questions")
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                exampleRow("How many emails are in this archive?", icon: "number", type: "Stats")
                exampleRow("Who are the top 5 senders?", icon: "person.3.fill", type: "Ranking")
                exampleRow("What's the date range of these emails?", icon: "calendar", type: "Dates")
                exampleRow("Find emails about project updates", icon: "magnifyingglass", type: "Search")
                exampleRow("Summarize the main themes", icon: "doc.text.fill", type: "Summary")
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Tips:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Text("• The AI uses statistics for count/date questions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("• Content searches look through email bodies")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("• Enable Debug Panel to see what's sent to the AI")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func exampleRow(_ text: String, icon: String, type: String) -> some View {
        Button(action: {
            question = text
            askQuestion()
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 20)

                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)

                Spacer()

                Text(type)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.gray.opacity(0.2)))

                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.blue)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func quickQuestionButton(_ text: String) -> some View {
        Button(action: {
            question = text
            askQuestion()
        }) {
            Text(text)
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func askQuestion() {
        guard !question.isEmpty else { return }

        isQuerying = true
        let currentQuestion = question
        question = ""

        Task {
            // Search for relevant emails
            var results: [SearchResult]

            if vectorDB.isIndexed {
                // Use indexed search (faster, semantic if available)
                results = await vectorDB.search(query: currentQuestion)
            } else {
                // Fallback to direct search through emails (no indexing required)
                results = await MainActor.run {
                    vectorDB.directSearch(query: currentQuestion, emails: viewModel.emails)
                }
            }

            // Gather metadata from viewModel for context
            let metadata = await MainActor.run {
                gatherMetadata()
            }

            // Get full RAG result
            let ragResult = await llm.askQuestionRAG(currentQuestion, context: results, metadata: metadata)

            await MainActor.run {
                currentRAGResult = ragResult

                // Add to history
                queryHistory.insert(
                    QueryHistoryItem(
                        question: currentQuestion,
                        answer: ragResult.answer,
                        sources: ragResult.sourcesUsed,
                        timestamp: Date(),
                        questionType: ragResult.questionType,
                        processingTime: ragResult.processingTime
                    ),
                    at: 0
                )

                isQuerying = false
            }
        }
    }

    private func gatherMetadata() -> EmailMetadata {
        let stats = viewModel.stats
        let topSenders = stats.topSenders.map { (name: $0.0, count: $0.1) }
        let uniqueSenders = Set(viewModel.emails.map { $0.from }).count

        return EmailMetadata(
            totalEmails: stats.totalEmails,
            dateRange: stats.dateRange,
            threadCount: stats.totalThreads,
            uniqueSenders: uniqueSenders,
            topSenders: topSenders
        )
    }

    private func clearConversation() {
        queryHistory.removeAll()
        currentRAGResult = nil
        llm.clearConversation()
    }
}

// MARK: - Query History Item

struct QueryHistoryItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
    let sources: [SearchResult]
    let timestamp: Date
    let questionType: QuestionType?
    let processingTime: TimeInterval?

    init(question: String, answer: String, sources: [SearchResult], timestamp: Date, questionType: QuestionType? = nil, processingTime: TimeInterval? = nil) {
        self.question = question
        self.answer = answer
        self.sources = sources
        self.timestamp = timestamp
        self.questionType = questionType
        self.processingTime = processingTime
    }
}

// MARK: - Export Conversation Sheet

struct ExportConversationSheet: View {
    @ObservedObject var llm: LocalLLM
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("Export Conversation")
                .font(.headline)

            Text("Save your Q&A session to a file")
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                Button("Export as Markdown") {
                    exportMarkdown()
                }
                .buttonStyle(.borderedProminent)

                Button("Export as JSON") {
                    exportJSON()
                }
                .buttonStyle(.bordered)
            }

            Button("Cancel") {
                isPresented = false
            }
            .buttonStyle(.borderless)
        }
        .padding(30)
        .frame(width: 400)
    }

    private func exportMarkdown() {
        let content = llm.exportConversation()
        saveFile(content: content, extension: "md")
    }

    private func exportJSON() {
        guard let data = llm.exportConversationJSON() else { return }
        guard let content = String(data: data, encoding: .utf8) else { return }
        saveFile(content: content, extension: "json")
    }

    private func saveFile(content: String, extension ext: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "email-qa-session.\(ext)"
        panel.allowedContentTypes = ext == "md" ? [.plainText] : [.json]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
            isPresented = false
        }
    }
}

// MARK: - RAG Settings Sheet

struct RAGSettingsSheet: View {
    @ObservedObject var llm: LocalLLM
    @Binding var isPresented: Bool
    @State private var editingPrompt: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("RAG Pipeline Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            Form {
                Section("Conversation Memory") {
                    Toggle("Enable Conversation Memory", isOn: $llm.useConversationMemory)

                    Stepper("History Length: \(llm.maxConversationHistory) turns",
                            value: $llm.maxConversationHistory, in: 2...20)

                    if !llm.conversationHistory.isEmpty {
                        Button("Clear Memory (\(llm.conversationHistory.count / 2) turns)") {
                            llm.clearConversation()
                        }
                        .foregroundColor(.red)
                    }
                }

                Section("Custom System Prompt") {
                    TextEditor(text: $llm.customSystemPrompt)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 200)

                    HStack {
                        Button("Reset to Default") {
                            llm.resetSystemPrompt()
                        }

                        Spacer()

                        Text("\(llm.customSystemPrompt.count) chars")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Debug") {
                    Toggle("Enable Debug Mode", isOn: $llm.debugMode)
                    Text("Shows the full prompt sent to the AI")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 600, height: 550)
    }
}

// MARK: - Preview

#Preview {
    AskView(viewModel: MboxViewModel())
}

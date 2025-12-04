//
//  AskView.swift
//  MBox Explorer
//
//  Chat interface for querying emails with AI
//  Author: Jordan Koch
//  Date: 2025-12-03
//

import SwiftUI

struct AskView: View {
    @ObservedObject var viewModel: MboxViewModel
    @StateObject private var vectorDB = VectorDatabase()
    @StateObject private var llm = LocalLLM()

    @State private var question = ""
    @State private var answer = ""
    @State private var sources: [SearchResult] = []
    @State private var queryHistory: [QueryHistoryItem] = []
    @State private var isQuerying = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("💬 Ask About Your Emails")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)

                    HStack(spacing: 12) {
                        if llm.isAvailable {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                Text("MLX AI Online")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 8, height: 8)
                                Text("Basic Search Mode")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }

                        if vectorDB.isIndexed {
                            Text("• \(vectorDB.totalDocuments) emails indexed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if !viewModel.emails.isEmpty {
                            Button("Index Emails") {
                                Task {
                                    await vectorDB.indexEmails(viewModel.emails) { progress in
                                        // Progress callback
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            // Chat area
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Query history
                    ForEach(queryHistory) { item in
                        queryHistoryCard(item)
                    }

                    // Current answer
                    if !answer.isEmpty {
                        answerCard()
                    }

                    // Examples (when empty)
                    if queryHistory.isEmpty && answer.isEmpty {
                        examplesCard()
                    }
                }
                .padding()
            }

            Divider()

            // Input area
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

                    quickQuestionButton("Who emailed me most?")
                    quickQuestionButton("Emails about budget")
                    quickQuestionButton("Summarize last week")
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

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

                Text(item.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Answer
            Text(item.answer)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.1))
                )

            // Sources
            if !item.sources.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sources:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(item.sources.prefix(3)) { source in
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
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
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

    private func answerCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("Answer")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button(action: { copyToClipboard(answer) }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }

            Text(answer)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.1))
                )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }

    private func examplesCard() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("💡 Example Questions")
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                exampleRow("Who emailed me most frequently?", icon: "person.fill")
                exampleRow("Find emails about Q4 budget", icon: "magnifyingglass")
                exampleRow("What did John say about the project?", icon: "bubble.left.fill")
                exampleRow("Summarize emails from last week", icon: "doc.text.fill")
                exampleRow("Action items from team meetings", icon: "checkmark.circle.fill")
                exampleRow("Emails with urgent requests", icon: "exclamationmark.triangle.fill")
            }

            Divider()

            Text("💡 Tip: Ask questions in natural language. The AI will search your emails and provide answers with sources.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
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

    private func exampleRow(_ text: String, icon: String) -> some View {
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

    private func askQuestion() {
        guard !question.isEmpty else { return }

        isQuerying = true
        let currentQuestion = question
        question = ""

        Task {
            // Search for relevant emails
            let results = await vectorDB.search(query: currentQuestion)

            // Get LLM answer
            let response = await llm.askQuestion(currentQuestion, context: results)

            await MainActor.run {
                answer = response
                sources = results

                // Add to history
                queryHistory.insert(
                    QueryHistoryItem(
                        question: currentQuestion,
                        answer: response,
                        sources: results,
                        timestamp: Date()
                    ),
                    at: 0
                )

                isQuerying = false
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct QueryHistoryItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
    let sources: [SearchResult]
    let timestamp: Date
}

#Preview {
    AskView(viewModel: MboxViewModel())
}

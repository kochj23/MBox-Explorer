//
//  BackgroundIndexer.swift
//  MBox Explorer
//
//  Background indexing with progress in menu bar
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation
import Combine

/// Manages background indexing operations
class BackgroundIndexer: ObservableObject {
    static let shared = BackgroundIndexer()

    @Published var isIndexing = false
    @Published var isPaused = false
    @Published var progress: Double = 0
    @Published var currentTask = ""
    @Published var indexedCount = 0
    @Published var totalCount = 0
    @Published var estimatedTimeRemaining: TimeInterval?

    private var indexTask: Task<Void, Never>?
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    private var startTime: Date?
    private var processedCount = 0

    private let vectorDB = VectorDatabase()
    private let embeddingManager = EmbeddingManager.shared

    // MARK: - Start Indexing

    func startIndexing(emails: [Email], priority: IndexingPriority = .normal) {
        guard !isIndexing else { return }

        isIndexing = true
        isPaused = false
        progress = 0
        indexedCount = 0
        totalCount = emails.count
        processedCount = 0
        startTime = Date()

        indexTask = Task(priority: priority.taskPriority) {
            await performIndexing(emails: emails)
        }
    }

    // MARK: - Control

    func pause() {
        guard isIndexing && !isPaused else { return }
        isPaused = true
        currentTask = "Paused"
    }

    func resume() {
        guard isIndexing && isPaused else { return }
        isPaused = false
        pauseContinuation?.resume()
        pauseContinuation = nil
    }

    func stop() {
        indexTask?.cancel()
        indexTask = nil
        isIndexing = false
        isPaused = false
        currentTask = "Stopped"
    }

    // MARK: - Indexing Implementation

    private func performIndexing(emails: [Email]) async {
        let batchSize = 20

        for startIndex in stride(from: 0, to: emails.count, by: batchSize) {
            // Check for cancellation
            if Task.isCancelled {
                await MainActor.run {
                    isIndexing = false
                    currentTask = "Cancelled"
                }
                return
            }

            // Handle pause
            if isPaused {
                await MainActor.run {
                    currentTask = "Paused - Click Resume to continue"
                }

                await withCheckedContinuation { continuation in
                    pauseContinuation = continuation
                }
            }

            // Process batch
            let endIndex = min(startIndex + batchSize, emails.count)
            let batch = Array(emails[startIndex..<endIndex])

            await MainActor.run {
                currentTask = "Indexing emails \(startIndex + 1) - \(endIndex)..."
            }

            // Generate embeddings for batch
            await indexBatch(batch)

            // Update progress
            processedCount += batch.count

            await MainActor.run {
                self.indexedCount = processedCount
                self.progress = Double(processedCount) / Double(emails.count)
                self.updateTimeEstimate()
            }

            // Small delay to prevent overwhelming the system
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        await MainActor.run {
            isIndexing = false
            isPaused = false
            currentTask = "Indexing complete"
            progress = 1.0
        }
    }

    private func indexBatch(_ emails: [Email]) async {
        // Generate embeddings if available
        if embeddingManager.useSemanticSearch {
            let texts = emails.map { email in
                let bodyPrefix = String(email.body.prefix(500))
                return "\(email.subject) \(bodyPrefix)"
            }

            do {
                let embeddings = try await embeddingManager.generateBatchEmbeddings(for: texts)

                // Store in vector database
                for (index, email) in emails.enumerated() {
                    let embedding = embeddings.count > index ? embeddings[index] : nil
                    await storeEmail(email, embedding: embedding)
                }
            } catch {
                print("Embedding error: \(error.localizedDescription)")
                // Store without embeddings
                for email in emails {
                    await storeEmail(email, embedding: nil)
                }
            }
        } else {
            // Store without embeddings
            for email in emails {
                await storeEmail(email, embedding: nil)
            }
        }
    }

    private func storeEmail(_ email: Email, embedding: [Float]?) async {
        // This would integrate with VectorDatabase
        // Simplified for now
    }

    private func updateTimeEstimate() {
        guard let start = startTime, processedCount > 0 else {
            estimatedTimeRemaining = nil
            return
        }

        let elapsed = Date().timeIntervalSince(start)
        let rate = Double(processedCount) / elapsed
        let remaining = Double(totalCount - processedCount)

        estimatedTimeRemaining = remaining / rate
    }

    // MARK: - Status

    var statusText: String {
        if !isIndexing {
            return "Ready"
        }

        if isPaused {
            return "Paused (\(indexedCount)/\(totalCount))"
        }

        let percent = Int(progress * 100)
        if let remaining = estimatedTimeRemaining {
            return "Indexing: \(percent)% - \(formatTime(remaining)) remaining"
        }

        return "Indexing: \(percent)%"
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return "\(Int(interval))s"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m"
        } else {
            return "\(Int(interval / 3600))h \(Int((interval.truncatingRemainder(dividingBy: 3600)) / 60))m"
        }
    }
}

// MARK: - Menu Bar Integration

class IndexingMenuBarManager: ObservableObject {
    static let shared = IndexingMenuBarManager()

    private let indexer = BackgroundIndexer.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Observe indexing state changes
        indexer.$isIndexing
            .sink { [weak self] isIndexing in
                self?.updateMenuBarStatus()
            }
            .store(in: &cancellables)

        indexer.$progress
            .sink { [weak self] _ in
                self?.updateMenuBarStatus()
            }
            .store(in: &cancellables)
    }

    func updateMenuBarStatus() {
        // Update menu bar extra or dock badge
        // This would integrate with NSApplication for actual implementation
    }
}

// MARK: - Models

enum IndexingPriority {
    case low
    case normal
    case high

    var taskPriority: TaskPriority {
        switch self {
        case .low: return .utility
        case .normal: return .medium
        case .high: return .high
        }
    }
}

struct IndexingStats {
    let totalEmails: Int
    let indexedEmails: Int
    let withEmbeddings: Int
    let withoutEmbeddings: Int
    let indexSize: Int
    let lastIndexed: Date?
}

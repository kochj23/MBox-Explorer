//
//  SpotlightIntegration.swift
//  MBox Explorer
//
//  Integrate MBOX emails with macOS Spotlight search
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation
import SwiftUI
import CoreSpotlight
import UniformTypeIdentifiers

class SpotlightIntegration: ObservableObject {
    static let shared = SpotlightIntegration()

    @Published var isIndexing = false
    @Published var indexedCount = 0
    @Published var totalToIndex = 0

    private let searchableIndex = CSSearchableIndex.default()
    private let domainIdentifier = "com.mboxexplorer.emails"
    private let batchSize = 100

    // MARK: - Index Emails

    func indexEmails(_ emails: [Email], from mboxPath: String, progressCallback: ((Double) -> Void)? = nil) async throws {
        await MainActor.run {
            isIndexing = true
            indexedCount = 0
            totalToIndex = emails.count
        }

        defer {
            Task { @MainActor in
                isIndexing = false
            }
        }

        // Process in batches
        var searchableItems: [CSSearchableItem] = []
        let mboxName = URL(fileURLWithPath: mboxPath).deletingPathExtension().lastPathComponent

        for (index, email) in emails.enumerated() {
            let item = createSearchableItem(for: email, mboxName: mboxName)
            searchableItems.append(item)

            // Index in batches
            if searchableItems.count >= batchSize || index == emails.count - 1 {
                try await indexBatch(searchableItems)
                searchableItems.removeAll()

                let progress = Double(index + 1) / Double(emails.count)
                await MainActor.run {
                    indexedCount = index + 1
                }
                progressCallback?(progress)
            }
        }
    }

    private func createSearchableItem(for email: Email, mboxName: String) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .emailMessage)

        // Basic attributes
        attributeSet.title = email.subject
        attributeSet.contentDescription = String(email.body.prefix(500))
        attributeSet.displayName = email.subject

        // Email-specific attributes
        attributeSet.authorNames = [extractName(from: email.from)]
        attributeSet.authorEmailAddresses = [extractEmail(from: email.from)]

        if let to = email.to {
            attributeSet.recipientNames = [extractName(from: to)]
            attributeSet.recipientEmailAddresses = [extractEmail(from: to)]
        }

        // Date
        if let date = email.dateObject {
            attributeSet.contentCreationDate = date
            attributeSet.contentModificationDate = date
        }

        // Additional metadata
        attributeSet.keywords = extractKeywords(from: email)
        attributeSet.containerTitle = mboxName
        attributeSet.containerDisplayName = mboxName

        // Attachments
        if let attachments = email.attachments, !attachments.isEmpty {
            attributeSet.hasAlphaChannel = NSNumber(value: true) // Using this to indicate has attachments
            let attachmentNames = attachments.map { $0.filename }
            attributeSet.keywords = (attributeSet.keywords ?? []) + attachmentNames
        }

        // Create the searchable item
        let uniqueID = "\(domainIdentifier).\(email.id.uuidString)"
        let item = CSSearchableItem(
            uniqueIdentifier: uniqueID,
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )

        // Set expiration (never expire indexed emails)
        item.expirationDate = .distantFuture

        return item
    }

    private func indexBatch(_ items: [CSSearchableItem]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            searchableIndex.indexSearchableItems(items) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Remove Index

    func removeAllIndexes() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            searchableIndex.deleteAllSearchableItems { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func removeIndex(for mboxPath: String) async throws {
        let mboxName = URL(fileURLWithPath: mboxPath).deletingPathExtension().lastPathComponent

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            searchableIndex.deleteSearchableItems(withDomainIdentifiers: ["\(domainIdentifier).\(mboxName)"]) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func removeIndex(for emailIds: [UUID]) async throws {
        let identifiers = emailIds.map { "\(domainIdentifier).\($0.uuidString)" }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            searchableIndex.deleteSearchableItems(withIdentifiers: identifiers) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Search

    func search(query: String, limit: Int = 50) async throws -> [SpotlightSearchResult] {
        let queryString = "title == \"*\(query)*\"cd || textContent == \"*\(query)*\"cd || authorNames == \"*\(query)*\"cd"

        return try await withCheckedThrowingContinuation { continuation in
            let searchQuery = CSSearchQuery(queryString: queryString, attributes: [
                "title",
                "contentDescription",
                "authorNames",
                "authorEmailAddresses",
                "recipientNames",
                "contentCreationDate"
            ])

            var results: [SpotlightSearchResult] = []

            searchQuery.foundItemsHandler = { items in
                for item in items {
                    let result = SpotlightSearchResult(
                        identifier: item.uniqueIdentifier,
                        title: item.attributeSet.title ?? "No Subject",
                        snippet: item.attributeSet.contentDescription ?? "",
                        sender: item.attributeSet.authorNames?.first ?? "",
                        date: item.attributeSet.contentCreationDate
                    )
                    results.append(result)
                }
            }

            searchQuery.completionHandler = { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: results)
                }
            }

            searchQuery.start()
        }
    }

    // MARK: - Helpers

    private func extractName(from address: String) -> String {
        if let range = address.range(of: "<") {
            return String(address[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return address
    }

    private func extractEmail(from address: String) -> String {
        if let startRange = address.range(of: "<"),
           let endRange = address.range(of: ">") {
            return String(address[startRange.upperBound..<endRange.lowerBound])
        }
        return address
    }

    private func extractKeywords(from email: Email) -> [String] {
        var keywords: [String] = []

        // Extract from subject
        let subjectWords = email.subject
            .components(separatedBy: .whitespaces)
            .filter { $0.count > 3 }
        keywords.append(contentsOf: subjectWords)

        // Add sender domain
        if let domain = extractEmail(from: email.from).split(separator: "@").last {
            keywords.append(String(domain))
        }

        return Array(Set(keywords))
    }

    // MARK: - Status

    func getIndexStatus() async -> SpotlightIndexStatus {
        // This is a simplified status check
        return SpotlightIndexStatus(
            isEnabled: true,
            indexedCount: indexedCount,
            lastIndexed: nil
        )
    }
}

// MARK: - Models

struct SpotlightSearchResult: Identifiable {
    let id = UUID()
    let identifier: String
    let title: String
    let snippet: String
    let sender: String
    let date: Date?

    var emailId: UUID? {
        // Extract UUID from identifier
        let prefix = "com.mboxexplorer.emails."
        guard identifier.hasPrefix(prefix) else { return nil }
        let uuidString = String(identifier.dropFirst(prefix.count))
        return UUID(uuidString: uuidString)
    }
}

struct SpotlightIndexStatus {
    let isEnabled: Bool
    let indexedCount: Int
    let lastIndexed: Date?
}

// MARK: - Spotlight Settings View

struct SpotlightSettingsView: View {
    @ObservedObject var spotlight = SpotlightIntegration.shared
    @State private var isEnabled = true
    @State private var showingClearConfirmation = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable Spotlight Indexing", isOn: $isEnabled)

                HStack {
                    Text("Indexed Emails")
                    Spacer()
                    Text("\(spotlight.indexedCount)")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Spotlight Integration")
            }

            Section {
                Button("Clear Spotlight Index") {
                    showingClearConfirmation = true
                }
                .foregroundColor(.red)
            } footer: {
                Text("Removing the Spotlight index will prevent finding emails from system search until they are re-indexed.")
            }
        }
        .formStyle(.grouped)
        .alert("Clear Spotlight Index?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                Task {
                    try? await spotlight.removeAllIndexes()
                }
            }
        } message: {
            Text("This will remove all MBox Explorer emails from Spotlight search.")
        }
    }
}

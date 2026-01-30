//
//  TagManager.swift
//  MBox Explorer
//
//  Manages tags, labels, and collections for emails
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation
import SwiftUI

/// Manages tags, labels, and smart collections
class TagManager: ObservableObject {
    static let shared = TagManager()

    @Published var tags: [EmailTag] = []
    @Published var collections: [EmailCollection] = []
    @Published var emailTags: [UUID: Set<UUID>] = [:] // emailId -> tagIds
    @Published var favorites: Set<UUID> = []
    @Published var notes: [UUID: String] = [:] // emailId -> note
    @Published var linkedEmails: [UUID: Set<UUID>] = [:] // emailId -> linked emailIds

    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("MBoxExplorer", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        storageURL = appFolder.appendingPathComponent("tags.json")

        loadData()
        createDefaultTags()
    }

    // MARK: - Tags

    func createTag(name: String, color: TagColor, icon: String = "tag") -> EmailTag {
        let tag = EmailTag(
            id: UUID(),
            name: name,
            color: color,
            icon: icon,
            createdAt: Date()
        )
        tags.append(tag)
        saveData()
        return tag
    }

    func deleteTag(_ tag: EmailTag) {
        tags.removeAll { $0.id == tag.id }

        // Remove tag from all emails
        for emailId in emailTags.keys {
            emailTags[emailId]?.remove(tag.id)
        }

        saveData()
    }

    func updateTag(_ tag: EmailTag, name: String? = nil, color: TagColor? = nil, icon: String? = nil) {
        guard let index = tags.firstIndex(where: { $0.id == tag.id }) else { return }

        tags[index] = EmailTag(
            id: tag.id,
            name: name ?? tag.name,
            color: color ?? tag.color,
            icon: icon ?? tag.icon,
            createdAt: tag.createdAt
        )
        saveData()
    }

    // MARK: - Email Tagging

    func addTag(_ tag: EmailTag, to emailId: UUID) {
        if emailTags[emailId] == nil {
            emailTags[emailId] = []
        }
        emailTags[emailId]?.insert(tag.id)
        saveData()
    }

    func removeTag(_ tag: EmailTag, from emailId: UUID) {
        emailTags[emailId]?.remove(tag.id)
        saveData()
    }

    func toggleTag(_ tag: EmailTag, for emailId: UUID) {
        if emailTags[emailId]?.contains(tag.id) == true {
            removeTag(tag, from: emailId)
        } else {
            addTag(tag, to: emailId)
        }
    }

    func getTags(for emailId: UUID) -> [EmailTag] {
        guard let tagIds = emailTags[emailId] else { return [] }
        return tags.filter { tagIds.contains($0.id) }
    }

    func getEmails(with tag: EmailTag, from emails: [Email]) -> [Email] {
        return emails.filter { email in
            emailTags[email.id]?.contains(tag.id) == true
        }
    }

    // MARK: - Favorites

    func toggleFavorite(_ emailId: UUID) {
        if favorites.contains(emailId) {
            favorites.remove(emailId)
        } else {
            favorites.insert(emailId)
        }
        saveData()
    }

    func isFavorite(_ emailId: UUID) -> Bool {
        favorites.contains(emailId)
    }

    func getFavorites(from emails: [Email]) -> [Email] {
        emails.filter { favorites.contains($0.id) }
    }

    // MARK: - Notes

    func setNote(_ note: String, for emailId: UUID) {
        if note.isEmpty {
            notes.removeValue(forKey: emailId)
        } else {
            notes[emailId] = note
        }
        saveData()
    }

    func getNote(for emailId: UUID) -> String? {
        notes[emailId]
    }

    // MARK: - Email Linking

    func linkEmails(_ emailId1: UUID, _ emailId2: UUID) {
        if linkedEmails[emailId1] == nil {
            linkedEmails[emailId1] = []
        }
        if linkedEmails[emailId2] == nil {
            linkedEmails[emailId2] = []
        }

        linkedEmails[emailId1]?.insert(emailId2)
        linkedEmails[emailId2]?.insert(emailId1)
        saveData()
    }

    func unlinkEmails(_ emailId1: UUID, _ emailId2: UUID) {
        linkedEmails[emailId1]?.remove(emailId2)
        linkedEmails[emailId2]?.remove(emailId1)
        saveData()
    }

    func getLinkedEmails(_ emailId: UUID, from emails: [Email]) -> [Email] {
        guard let linkedIds = linkedEmails[emailId] else { return [] }
        return emails.filter { linkedIds.contains($0.id) }
    }

    // MARK: - Collections

    func createCollection(name: String, icon: String, rules: [CollectionRule]) -> EmailCollection {
        let collection = EmailCollection(
            id: UUID(),
            name: name,
            icon: icon,
            rules: rules,
            isSmartCollection: !rules.isEmpty,
            manualEmailIds: [],
            createdAt: Date()
        )
        collections.append(collection)
        saveData()
        return collection
    }

    func deleteCollection(_ collection: EmailCollection) {
        collections.removeAll { $0.id == collection.id }
        saveData()
    }

    func addToCollection(_ emailId: UUID, collection: EmailCollection) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        var updated = collections[index]
        updated.manualEmailIds.insert(emailId)
        collections[index] = updated
        saveData()
    }

    func removeFromCollection(_ emailId: UUID, collection: EmailCollection) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        var updated = collections[index]
        updated.manualEmailIds.remove(emailId)
        collections[index] = updated
        saveData()
    }

    func getEmails(in collection: EmailCollection, from emails: [Email]) -> [Email] {
        if collection.isSmartCollection {
            return emails.filter { email in
                evaluateRules(collection.rules, for: email)
            }
        } else {
            return emails.filter { collection.manualEmailIds.contains($0.id) }
        }
    }

    private func evaluateRules(_ rules: [CollectionRule], for email: Email) -> Bool {
        for rule in rules {
            let matches: Bool
            let value = rule.value.lowercased()

            switch rule.field {
            case .from:
                matches = email.from.lowercased().contains(value)
            case .to:
                matches = email.to?.lowercased().contains(value) ?? false
            case .subject:
                matches = email.subject.lowercased().contains(value)
            case .body:
                matches = email.body.lowercased().contains(value)
            case .hasAttachment:
                matches = (email.attachments?.isEmpty == false) == (value == "true")
            case .date:
                // Date rules would need more complex parsing
                matches = email.date.contains(value)
            }

            switch rule.operator_ {
            case .contains:
                if !matches { return false }
            case .notContains:
                if matches { return false }
            case .equals:
                // Exact match
                break
            case .startsWith:
                // Prefix match
                break
            }
        }

        return true
    }

    // MARK: - Persistence

    private func saveData() {
        let data = TagData(
            tags: tags,
            collections: collections,
            emailTags: emailTags.mapValues { Array($0) },
            favorites: Array(favorites),
            notes: notes,
            linkedEmails: linkedEmails.mapValues { Array($0) }
        )

        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: storageURL)
        }
    }

    private func loadData() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode(TagData.self, from: data) else {
            return
        }

        tags = decoded.tags
        collections = decoded.collections
        emailTags = decoded.emailTags.mapValues { Set($0) }
        favorites = Set(decoded.favorites)
        notes = decoded.notes
        linkedEmails = decoded.linkedEmails.mapValues { Set($0) }
    }

    private func createDefaultTags() {
        if tags.isEmpty {
            _ = createTag(name: "Important", color: .red, icon: "exclamationmark")
            _ = createTag(name: "Work", color: .blue, icon: "briefcase")
            _ = createTag(name: "Personal", color: .green, icon: "person")
            _ = createTag(name: "Finance", color: .yellow, icon: "dollarsign")
            _ = createTag(name: "Follow Up", color: .orange, icon: "arrow.uturn.right")
            _ = createTag(name: "Read Later", color: .purple, icon: "book")
        }
    }
}

// MARK: - Models

struct EmailTag: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: TagColor
    var icon: String
    let createdAt: Date
}

enum TagColor: String, Codable, CaseIterable {
    case red, orange, yellow, green, blue, purple, pink, gray

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .gray: return .gray
        }
    }
}

struct EmailCollection: Identifiable, Codable {
    let id: UUID
    var name: String
    var icon: String
    var rules: [CollectionRule]
    var isSmartCollection: Bool
    var manualEmailIds: Set<UUID>
    let createdAt: Date
}

struct CollectionRule: Codable {
    let field: CollectionField
    let operator_: CollectionOperator
    let value: String
}

enum CollectionField: String, Codable, CaseIterable {
    case from = "From"
    case to = "To"
    case subject = "Subject"
    case body = "Body"
    case hasAttachment = "Has Attachment"
    case date = "Date"
}

enum CollectionOperator: String, Codable, CaseIterable {
    case contains = "contains"
    case notContains = "does not contain"
    case equals = "equals"
    case startsWith = "starts with"
}

struct TagData: Codable {
    let tags: [EmailTag]
    let collections: [EmailCollection]
    let emailTags: [UUID: [UUID]]
    let favorites: [UUID]
    let notes: [UUID: String]
    let linkedEmails: [UUID: [UUID]]
}

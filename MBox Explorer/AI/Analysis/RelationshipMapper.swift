//
//  RelationshipMapper.swift
//  MBox Explorer
//
//  Analyzes email relationships and builds social graph
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation

/// Maps relationships between email participants
@MainActor
class RelationshipMapper: ObservableObject {
    static let shared = RelationshipMapper()

    @Published var relationships: [EmailRelationship] = []
    @Published var socialGraph: SocialGraph = SocialGraph()
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0

    private let database = ConversationDatabase.shared
    private let aiBackend = AIBackendManager.shared

    private init() {}

    // MARK: - Analysis

    /// Analyze all emails to build relationship map
    func analyzeEmails(_ emails: [Email]) async {
        isAnalyzing = true
        analysisProgress = 0

        // Build participant pairs
        var pairCounts: [String: (count: Int, dates: [Date], subjects: [String])] = [:]

        for (index, email) in emails.enumerated() {
            let from = normalizeEmail(email.from)

            // Get recipients
            var recipients: [String] = []
            if let to = email.to {
                recipients = to.components(separatedBy: ",").map { normalizeEmail($0) }
            }

            // Create pairs between sender and recipients
            for recipient in recipients {
                let pair = makePairKey(from, recipient)

                if var existing = pairCounts[pair] {
                    existing.count += 1
                    if let date = email.dateObject {
                        existing.dates.append(date)
                    }
                    existing.subjects.append(email.subject)
                    pairCounts[pair] = existing
                } else {
                    pairCounts[pair] = (
                        count: 1,
                        dates: email.dateObject.map { [$0] } ?? [],
                        subjects: [email.subject]
                    )
                }
            }

            analysisProgress = Double(index + 1) / Double(emails.count)
        }

        // Convert to relationships
        var newRelationships: [EmailRelationship] = []
        let maxCount = pairCounts.values.map { $0.count }.max() ?? 1

        for (pairKey, data) in pairCounts {
            let participants = pairKey.components(separatedBy: "|||")
            guard participants.count == 2 else { continue }

            let firstContact = data.dates.min() ?? Date()
            let lastContact = data.dates.max() ?? Date()

            // Extract topics from subjects
            let topics = extractTopics(from: data.subjects)

            let relationship = EmailRelationship(
                person1: participants[0],
                person2: participants[1],
                emailCount: data.count,
                firstContact: firstContact,
                lastContact: lastContact,
                averageSentiment: 0, // Will be updated by SentimentAnalyzer
                topics: topics,
                relationshipStrength: Double(data.count) / Double(maxCount)
            )

            newRelationships.append(relationship)
            database.saveRelationship(relationship)
        }

        relationships = newRelationships
        buildSocialGraph()

        isAnalyzing = false
    }

    /// Get relationships for a specific person
    func getRelationships(for email: String) -> [EmailRelationship] {
        let normalized = normalizeEmail(email)
        return relationships.filter { relationship in
            normalizeEmail(relationship.person1) == normalized ||
            normalizeEmail(relationship.person2) == normalized
        }
    }

    /// Find who a person communicates with most
    func getTopContacts(for email: String, limit: Int = 10) -> [(person: String, emailCount: Int)] {
        let personRelationships = getRelationships(for: email)
        let normalized = normalizeEmail(email)

        return personRelationships
            .sorted { $0.emailCount > $1.emailCount }
            .prefix(limit)
            .map { relationship in
                let otherPerson = normalizeEmail(relationship.person1) == normalized ?
                    relationship.person2 : relationship.person1
                return (person: otherPerson, emailCount: relationship.emailCount)
            }
    }

    /// Detect cliques (groups that frequently communicate together)
    func detectCliques(minSize: Int = 3) -> [[String]] {
        var cliques: [[String]] = []

        // Group relationships by participants
        var personConnections: [String: Set<String>] = [:]

        for relationship in relationships where relationship.emailCount >= 3 {
            let p1 = normalizeEmail(relationship.person1)
            let p2 = normalizeEmail(relationship.person2)

            personConnections[p1, default: Set()].insert(p2)
            personConnections[p2, default: Set()].insert(p1)
        }

        // Find cliques using simple algorithm
        var processedCliques: Set<String> = []

        for (person, connections) in personConnections {
            // Check if all connections also connect to each other
            let potentialClique = connections.union([person])

            if potentialClique.count >= minSize {
                // Verify it's a clique (everyone connected to everyone)
                var isClique = true
                for member in potentialClique {
                    let memberConnections = personConnections[member] ?? Set()
                    let otherMembers = potentialClique.subtracting([member])
                    if !otherMembers.isSubset(of: memberConnections) {
                        isClique = false
                        break
                    }
                }

                if isClique {
                    let cliqueKey = potentialClique.sorted().joined(separator: ",")
                    if !processedCliques.contains(cliqueKey) {
                        processedCliques.insert(cliqueKey)
                        cliques.append(Array(potentialClique).sorted())
                    }
                }
            }
        }

        return cliques
    }

    /// Find introduction brokers (people who connect different groups)
    func findIntroductionBrokers() -> [(person: String, bridgeScore: Double, connectedGroups: [[String]])] {
        var brokers: [(person: String, bridgeScore: Double, connectedGroups: [[String]])] = []

        // Calculate betweenness centrality (simplified)
        let cliques = detectCliques(minSize: 2)

        var personCliques: [String: [[String]]] = [:]
        for clique in cliques {
            for person in clique {
                personCliques[person, default: []].append(clique)
            }
        }

        // People who appear in multiple cliques are potential brokers
        for (person, memberCliques) in personCliques {
            if memberCliques.count > 1 {
                // Find distinct groups this person connects
                var distinctGroups: [[String]] = []
                for clique in memberCliques {
                    let otherMembers = clique.filter { $0 != person }
                    if !distinctGroups.contains(where: { Set($0).intersection(Set(otherMembers)).count > 0 }) {
                        distinctGroups.append(otherMembers)
                    }
                }

                if distinctGroups.count > 1 {
                    let bridgeScore = Double(distinctGroups.count) * 0.5
                    brokers.append((person: person, bridgeScore: bridgeScore, connectedGroups: distinctGroups))
                }
            }
        }

        return brokers.sorted { $0.bridgeScore > $1.bridgeScore }
    }

    /// Ask AI about relationships
    func askAboutRelationship(person1: String, person2: String, emails: [Email]) async -> String {
        let relevantEmails = emails.filter { email in
            let from = normalizeEmail(email.from)
            let to = email.to.map { normalizeEmail($0) } ?? ""
            let p1 = normalizeEmail(person1)
            let p2 = normalizeEmail(person2)

            return (from.contains(p1) && to.contains(p2)) ||
                   (from.contains(p2) && to.contains(p1))
        }

        guard !relevantEmails.isEmpty else {
            return "No direct communication found between \(person1) and \(person2)."
        }

        let emailContext = relevantEmails.prefix(10).map { email in
            "From: \(email.from)\nTo: \(email.to ?? "Unknown")\nSubject: \(email.subject)\nDate: \(email.date)\n\(email.body.prefix(300))"
        }.joined(separator: "\n---\n")

        let prompt = """
        Analyze the communication relationship between these two people based on their email exchanges:

        EMAILS:
        \(emailContext)

        Please describe:
        1. The nature of their relationship (professional, collaborative, etc.)
        2. Main topics they discuss
        3. Tone of communication (formal, casual, etc.)
        4. Any notable patterns or changes over time
        """

        do {
            return try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You are an expert at analyzing professional relationships from email communication."
            )
        } catch {
            return "Error analyzing relationship: \(error.localizedDescription)"
        }
    }

    // MARK: - Social Graph

    private func buildSocialGraph() {
        var nodes: [SocialGraphNode] = []
        var edges: [SocialGraphEdge] = []

        // Create nodes for each unique person
        var personSet: Set<String> = []
        for relationship in relationships {
            personSet.insert(relationship.person1)
            personSet.insert(relationship.person2)
        }

        // Calculate node sizes based on total connections
        var connectionCounts: [String: Int] = [:]
        for relationship in relationships {
            connectionCounts[relationship.person1, default: 0] += relationship.emailCount
            connectionCounts[relationship.person2, default: 0] += relationship.emailCount
        }

        let maxConnections = connectionCounts.values.max() ?? 1

        for person in personSet {
            let count = connectionCounts[person] ?? 1
            let size = 20 + (Double(count) / Double(maxConnections)) * 40

            nodes.append(SocialGraphNode(
                id: UUID(),
                email: person,
                displayName: extractName(from: person),
                size: size,
                connectionCount: count
            ))
        }

        // Create edges
        for relationship in relationships {
            if let sourceNode = nodes.first(where: { $0.email == relationship.person1 }),
               let targetNode = nodes.first(where: { $0.email == relationship.person2 }) {
                edges.append(SocialGraphEdge(
                    id: UUID(),
                    sourceId: sourceNode.id,
                    targetId: targetNode.id,
                    weight: Double(relationship.emailCount),
                    sentiment: relationship.averageSentiment
                ))
            }
        }

        socialGraph = SocialGraph(nodes: nodes, edges: edges)
    }

    // MARK: - Helpers

    private func normalizeEmail(_ email: String) -> String {
        // Extract email address from "Name <email@domain.com>" format
        if let emailMatch = email.range(of: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, options: .regularExpression) {
            return String(email[emailMatch]).lowercased()
        }
        return email.lowercased().trimmingCharacters(in: .whitespaces)
    }

    private func makePairKey(_ email1: String, _ email2: String) -> String {
        let sorted = [email1, email2].sorted()
        return sorted.joined(separator: "|||")
    }

    private func extractTopics(from subjects: [String]) -> [String] {
        // Simple topic extraction based on common words
        var wordCounts: [String: Int] = [:]
        let stopWords = Set(["re:", "fw:", "fwd:", "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by"])

        for subject in subjects {
            let words = subject.lowercased()
                .components(separatedBy: .whitespaces)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count > 2 && !stopWords.contains($0) }

            for word in words {
                wordCounts[word, default: 0] += 1
            }
        }

        return wordCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }

    private func extractName(from email: String) -> String {
        // Extract name from "Name <email@domain.com>" format
        if let nameMatch = email.range(of: #"^[^<]+"#, options: .regularExpression) {
            let name = String(email[nameMatch]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !name.contains("@") {
                return name
            }
        }

        // Extract from email address
        if let atIndex = email.firstIndex(of: "@") {
            let localPart = String(email[..<atIndex])
            return localPart.replacingOccurrences(of: ".", with: " ").capitalized
        }

        return email
    }
}

// MARK: - Social Graph Types

struct SocialGraph {
    var nodes: [SocialGraphNode] = []
    var edges: [SocialGraphEdge] = []

    var isEmpty: Bool { nodes.isEmpty }
}

struct SocialGraphNode: Identifiable {
    let id: UUID
    let email: String
    let displayName: String
    var size: Double
    var connectionCount: Int
    var x: Double = 0
    var y: Double = 0
}

struct SocialGraphEdge: Identifiable {
    let id: UUID
    let sourceId: UUID
    let targetId: UUID
    let weight: Double
    var sentiment: Double // -1 to 1
}

//
//  NetworkVisualizationView.swift
//  MBox Explorer
//
//  Email communication network visualization
//  Author: Jordan Koch
//  Date: 2025-12-03
//

import SwiftUI

struct NetworkVisualizationView: View {
    let emails: [Email]
    @State private var nodes: [NetworkNode] = []
    @State private var edges: [NetworkEdge] = []
    @State private var selectedNode: NetworkNode?

    var body: some View {
        VStack {
            Text("📊 Email Communication Network")
                .font(.title)
                .padding()

            ZStack {
                // Network visualization (simplified - full implementation would use force-directed graph)
                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        // Draw edges
                        ForEach(edges) { edge in
                            networkEdge(edge)
                        }

                        // Draw nodes
                        ForEach(nodes) { node in
                            networkNode(node)
                        }
                    }
                    .frame(width: 1000, height: 800)
                }

                // Stats overlay
                VStack {
                    Spacer()
                    networkStats()
                        .padding()
                }
            }
        }
        .onAppear {
            analyzeNetwork()
        }
    }

    private func networkNode(_ node: NetworkNode) -> some View {
        VStack {
            Circle()
                .fill(node == selectedNode ? Color.blue : Color.green)
                .frame(width: CGFloat(node.emailCount / 2 + 20), height: CGFloat(node.emailCount / 2 + 20))
                .overlay(
                    Text(node.initials)
                        .font(.caption)
                        .foregroundColor(.white)
                )

            Text(node.name)
                .font(.caption2)
                .lineLimit(1)
        }
        .position(x: node.x, y: node.y)
        .onTapGesture {
            selectedNode = node
        }
    }

    private func networkEdge(_ edge: NetworkEdge) -> some View {
        Path { path in
            path.move(to: edge.from)
            path.addLine(to: edge.to)
        }
        .stroke(Color.gray.opacity(0.3), lineWidth: CGFloat(edge.weight / 5))
    }

    private func networkStats() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Network Statistics")
                .font(.headline)

            if let selected = selectedNode {
                Text("\(selected.name): \(selected.emailCount) emails")
                    .font(.caption)
            } else {
                Text("\(nodes.count) participants")
                    .font(.caption)
                Text("\(edges.count) connections")
                    .font(.caption)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func analyzeNetwork() {
        // Build network from emails
        var emailCounts: [String: Int] = [:]
        var connections: [String: [String: Int]] = [:]

        for email in emails {
            emailCounts[email.from, default: 0] += 1

            // Track to addresses (simplified)
            let toAddresses = email.to.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for to in toAddresses where !to.isEmpty {
                connections[email.from, default: [:]][to, default: 0] += 1
            }
        }

        // Create nodes
        let sortedPeople = emailCounts.sorted { $0.value > $1.value }
        nodes = sortedPeople.enumerated().map { index, item in
            let angle = (Double(index) / Double(sortedPeople.count)) * 2 * .pi
            let radius = 300.0

            return NetworkNode(
                name: item.key,
                emailCount: item.value,
                x: 500 + cos(angle) * radius,
                y: 400 + sin(angle) * radius
            )
        }

        // Create edges
        for (from, tos) in connections {
            guard let fromNode = nodes.first(where: { $0.name == from }) else { continue }

            for (to, count) in tos {
                guard let toNode = nodes.first(where: { $0.name == to }) else { continue }

                edges.append(NetworkEdge(
                    from: CGPoint(x: fromNode.x, y: fromNode.y),
                    to: CGPoint(x: toNode.x, y: toNode.y),
                    weight: count
                ))
            }
        }
    }
}

struct NetworkNode: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let emailCount: Int
    var x: Double
    var y: Double

    var initials: String {
        let components = name.components(separatedBy: " ")
        return components.compactMap { $0.first }.prefix(2).map { String($0) }.joined()
    }
}

struct NetworkEdge: Identifiable {
    let id = UUID()
    let from: CGPoint
    let to: CGPoint
    let weight: Int
}

//
//  CommandPaletteView.swift
//  MBox Explorer
//
//  Quick command palette (⌘K) for power users
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var viewModel: MboxViewModel
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            searchField

            Divider()

            // Results
            if filteredCommands.isEmpty {
                emptyState
            } else {
                commandList
            }

            // Footer
            footerHints
        }
        .frame(width: 500, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Type a command or search...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isSearchFocused)
                .onSubmit {
                    executeSelectedCommand()
                }
                .onChange(of: searchText) { _ in
                    selectedIndex = 0
                }

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
    }

    // MARK: - Command List

    private var commandList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                        CommandRow(
                            command: command,
                            isSelected: index == selectedIndex
                        )
                        .id(index)
                        .onTapGesture {
                            selectedIndex = index
                            executeCommand(command)
                        }
                    }
                }
            }
            .onChange(of: selectedIndex) { newIndex in
                withAnimation {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .onKeyPress(.upArrow) {
            moveSelection(-1)
            return KeyPress.Result.handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(1)
            return KeyPress.Result.handled
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("No matching commands")
                .font(.headline)

            Text("Try a different search term")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Footer

    private var footerHints: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                KeyboardKey(key: "↑↓")
                Text("Navigate")
            }

            HStack(spacing: 4) {
                KeyboardKey(key: "↵")
                Text("Execute")
            }

            HStack(spacing: 4) {
                KeyboardKey(key: "esc")
                Text("Close")
            }

            Spacer()

            Text("\(filteredCommands.count) commands")
                .foregroundColor(.secondary)
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Commands

    private var allCommands: [PaletteCommand] {
        var commands: [PaletteCommand] = []

        // File commands
        commands.append(contentsOf: [
            PaletteCommand(
                id: "open",
                name: "Open MBOX File",
                category: .file,
                icon: "doc",
                shortcut: "⌘O",
                action: { viewModel.showOpenPanel = true }
            ),
            PaletteCommand(
                id: "export",
                name: "Export Emails",
                category: .file,
                icon: "square.and.arrow.up",
                shortcut: "⌘E",
                action: { viewModel.showExportPanel = true }
            ),
            PaletteCommand(
                id: "import",
                name: "Import Emails",
                category: .file,
                icon: "square.and.arrow.down",
                action: { /* Import action */ }
            )
        ])

        // Navigation commands
        commands.append(contentsOf: [
            PaletteCommand(
                id: "ask-ai",
                name: "Ask AI",
                category: .navigation,
                icon: "bubble.left.and.bubble.right",
                action: { viewModel.currentView = .ask }
            ),
            PaletteCommand(
                id: "timeline",
                name: "View Timeline",
                category: .navigation,
                icon: "calendar",
                action: { viewModel.currentView = .timeline }
            ),
            PaletteCommand(
                id: "heatmap",
                name: "View Heatmap",
                category: .navigation,
                icon: "chart.bar.fill",
                action: { viewModel.currentView = .heatmap }
            ),
            PaletteCommand(
                id: "network",
                name: "View Network",
                category: .navigation,
                icon: "person.3",
                action: { viewModel.currentView = .network }
            ),
            PaletteCommand(
                id: "attachments",
                name: "View Attachments",
                category: .navigation,
                icon: "paperclip",
                action: { viewModel.currentView = .attachments }
            )
        ])

        // Search commands
        commands.append(contentsOf: [
            PaletteCommand(
                id: "search",
                name: "Search Emails",
                category: .search,
                icon: "magnifyingglass",
                shortcut: "⌘F",
                action: { viewModel.isSearching = true }
            ),
            PaletteCommand(
                id: "filter-unread",
                name: "Show Unread",
                category: .search,
                icon: "envelope.badge",
                action: { /* Filter action */ }
            ),
            PaletteCommand(
                id: "filter-attachments",
                name: "Show with Attachments",
                category: .search,
                icon: "paperclip",
                action: { /* Filter action */ }
            ),
            PaletteCommand(
                id: "filter-today",
                name: "Show Today's Emails",
                category: .search,
                icon: "clock",
                action: { /* Filter action */ }
            )
        ])

        // AI commands
        commands.append(contentsOf: [
            PaletteCommand(
                id: "summarize",
                name: "Summarize Selected",
                category: .ai,
                icon: "text.alignleft",
                action: { /* Summarize action */ }
            ),
            PaletteCommand(
                id: "extract-actions",
                name: "Extract Action Items",
                category: .ai,
                icon: "checklist",
                action: { /* Extract action */ }
            ),
            PaletteCommand(
                id: "generate-profile",
                name: "Generate Contact Profile",
                category: .ai,
                icon: "person.crop.circle",
                action: { /* Profile action */ }
            ),
            PaletteCommand(
                id: "detect-threats",
                name: "Scan for Threats",
                category: .ai,
                icon: "shield.checkered",
                action: { /* Threat scan */ }
            )
        ])

        // Tools commands
        commands.append(contentsOf: [
            PaletteCommand(
                id: "index",
                name: "Index Emails",
                category: .tools,
                icon: "arrow.triangle.2.circlepath",
                action: { /* Index action */ }
            ),
            PaletteCommand(
                id: "duplicates",
                name: "Find Duplicates",
                category: .tools,
                icon: "doc.on.doc",
                action: { viewModel.currentView = .duplicates }
            ),
            PaletteCommand(
                id: "forensics",
                name: "Email Forensics",
                category: .tools,
                icon: "magnifyingglass.circle",
                action: { /* Forensics action */ }
            ),
            PaletteCommand(
                id: "merge",
                name: "Merge Mailboxes",
                category: .tools,
                icon: "arrow.triangle.merge",
                action: { /* Merge action */ }
            )
        ])

        // Settings commands
        commands.append(contentsOf: [
            PaletteCommand(
                id: "settings",
                name: "Open Settings",
                category: .settings,
                icon: "gear",
                shortcut: "⌘,",
                action: { viewModel.showSettings = true }
            ),
            PaletteCommand(
                id: "ai-settings",
                name: "AI Settings",
                category: .settings,
                icon: "cpu",
                action: { viewModel.showAISettings = true }
            ),
            PaletteCommand(
                id: "theme",
                name: "Change Theme",
                category: .settings,
                icon: "paintpalette",
                action: { /* Theme action */ }
            )
        ])

        return commands
    }

    private var filteredCommands: [PaletteCommand] {
        if searchText.isEmpty {
            return allCommands
        }

        let query = searchText.lowercased()
        return allCommands.filter { command in
            command.name.lowercased().contains(query) ||
            command.category.rawValue.lowercased().contains(query)
        }
    }

    // MARK: - Actions

    private func moveSelection(_ delta: Int) {
        let newIndex = selectedIndex + delta
        if newIndex >= 0 && newIndex < filteredCommands.count {
            selectedIndex = newIndex
        }
    }

    private func executeSelectedCommand() {
        guard filteredCommands.indices.contains(selectedIndex) else { return }
        executeCommand(filteredCommands[selectedIndex])
    }

    private func executeCommand(_ command: PaletteCommand) {
        command.action()
        isPresented = false
    }
}

// MARK: - Command Row

struct CommandRow: View {
    let command: PaletteCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.icon)
                .frame(width: 20)
                .foregroundColor(isSelected ? .white : command.category.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(command.name)
                    .font(.body)

                Text(command.category.rawValue)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }

            Spacer()

            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.2))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor : Color.clear)
        .foregroundColor(isSelected ? .white : .primary)
    }
}

// MARK: - Keyboard Key

struct KeyboardKey: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.caption)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.2))
            )
    }
}

// MARK: - Models

struct PaletteCommand: Identifiable {
    let id: String
    let name: String
    let category: CommandCategory
    let icon: String
    var shortcut: String? = nil
    let action: () -> Void
}

enum CommandCategory: String {
    case file = "File"
    case navigation = "Navigation"
    case search = "Search"
    case ai = "AI"
    case tools = "Tools"
    case settings = "Settings"

    var color: Color {
        switch self {
        case .file: return .blue
        case .navigation: return .green
        case .search: return .orange
        case .ai: return .purple
        case .tools: return .cyan
        case .settings: return .gray
        }
    }
}

// MARK: - Command Palette Manager

class CommandPaletteManager: ObservableObject {
    static let shared = CommandPaletteManager()

    @Published var isShowing = false

    func toggle() {
        isShowing.toggle()
    }

    func show() {
        isShowing = true
    }

    func hide() {
        isShowing = false
    }
}

#Preview {
    CommandPaletteView(
        viewModel: MboxViewModel(),
        isPresented: .constant(true)
    )
}

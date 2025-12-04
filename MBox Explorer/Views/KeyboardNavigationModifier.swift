//
//  KeyboardNavigationModifier.swift
//  MBox Explorer
//
//  Gmail-style keyboard navigation
//

import SwiftUI
import AppKit

struct KeyboardNavigationModifier: ViewModifier {
    @ObservedObject var viewModel: MboxViewModel
    @FocusState.Binding var searchFocused: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    return handleKeyEvent(event) ? nil : event
                }
            }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Don't intercept if text field is focused
        if searchFocused {
            return false
        }

        // Don't intercept if modifier keys are pressed (except Shift for X)
        if event.modifierFlags.contains(.command) ||
           event.modifierFlags.contains(.option) ||
           event.modifierFlags.contains(.control) {
            return false
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch characters {
        case "j":
            // Next email (Gmail-style)
            viewModel.selectNextEmail()
            return true

        case "k":
            // Previous email (Gmail-style)
            viewModel.selectPreviousEmail()
            return true

        case "/":
            // Focus search
            searchFocused = true
            return true

        case "x":
            // Toggle selection
            if let selected = viewModel.selectedEmail {
                if viewModel.selectedEmails.contains(selected.id) {
                    viewModel.selectedEmails.remove(selected.id)
                } else {
                    viewModel.selectedEmails.insert(selected.id)
                }
            }
            return true

        case "a":
            // Select all (if Shift is pressed, deselect all)
            if event.modifierFlags.contains(.shift) {
                viewModel.deselectAll()
            } else {
                viewModel.selectAllInCurrentView()
            }
            return true

        case "e":
            // Export selected
            if !viewModel.selectedEmails.isEmpty {
                // Trigger export dialog
                NotificationCenter.default.post(name: .exportSelected, object: nil)
            }
            return true

        case "d", "\u{7F}": // 'd' or Delete key
            // Delete selected email(s)
            if !viewModel.selectedEmails.isEmpty {
                viewModel.deleteSelectedEmails()
            } else if viewModel.selectedEmail != nil {
                viewModel.deleteSelectedEmail()
            }
            return true

        case "r":
            // Refresh/reload (if needed)
            return false

        case "?":
            // Show keyboard shortcuts help
            NotificationCenter.default.post(name: .showKeyboardHelp, object: nil)
            return true

        default:
            return false
        }
    }
}

// Notification names
extension Notification.Name {
    static let exportSelected = Notification.Name("exportSelected")
    static let showKeyboardHelp = Notification.Name("showKeyboardHelp")
}

// Keyboard shortcuts help view
struct KeyboardShortcutsView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .bold()
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Shortcuts list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ShortcutSection(title: "Navigation") {
                        ShortcutRow(key: "J", description: "Next email")
                        ShortcutRow(key: "K", description: "Previous email")
                        ShortcutRow(key: "↑ / ↓", description: "Navigate up/down in detail view")
                    }

                    ShortcutSection(title: "Selection") {
                        ShortcutRow(key: "X", description: "Toggle selection of current email")
                        ShortcutRow(key: "A", description: "Select all visible emails")
                        ShortcutRow(key: "Shift + A", description: "Deselect all")
                    }

                    ShortcutSection(title: "Actions") {
                        ShortcutRow(key: "E", description: "Export selected emails")
                        ShortcutRow(key: "D or Delete", description: "Delete selected email(s)")
                        ShortcutRow(key: "/", description: "Focus search field")
                    }

                    ShortcutSection(title: "General") {
                        ShortcutRow(key: "⌘ + O", description: "Open MBOX file")
                        ShortcutRow(key: "⌘ + F", description: "Focus search")
                        ShortcutRow(key: "⌘ + A", description: "Select all (system)")
                        ShortcutRow(key: "?", description: "Show this help")
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
    }
}

struct ShortcutSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                content
            }
        }
    }
}

struct ShortcutRow: View {
    let key: String
    let description: String

    var body: some View {
        HStack {
            Text(key)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .frame(width: 100, alignment: .leading)

            Text(description)
                .font(.body)

            Spacer()
        }
    }
}

//
//  MultiWindowManager.swift
//  MBox Explorer
//
//  Manage multiple windows and detachable panels
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation
import SwiftUI
import AppKit

/// Manages multiple windows for email comparison and detached panels
class MultiWindowManager: ObservableObject {
    static let shared = MultiWindowManager()

    @Published var openWindows: [MBoxWindow] = []

    fileprivate var windowControllers: [UUID: NSWindowController] = [:]

    // MARK: - Window Operations

    func openEmailInNewWindow(_ email: Email) {
        let windowId = UUID()
        let window = MBoxWindow(
            id: windowId,
            type: .emailDetail,
            title: email.subject,
            emailIds: [email.id]
        )

        openWindows.append(window)
        createNSWindow(for: window, content: AnyView(EmailWindowView(email: email)))
    }

    func openComparisonWindow(emails: [Email]) {
        let windowId = UUID()
        let window = MBoxWindow(
            id: windowId,
            type: .comparison,
            title: "Email Comparison",
            emailIds: emails.map { $0.id }
        )

        openWindows.append(window)
        createNSWindow(for: window, content: AnyView(ComparisonWindowView(emails: emails)))
    }

    func openSearchWindow(viewModel: MboxViewModel) {
        let windowId = UUID()
        let window = MBoxWindow(
            id: windowId,
            type: .search,
            title: "Search",
            emailIds: []
        )

        openWindows.append(window)
        createNSWindow(for: window, content: AnyView(SearchWindowView(viewModel: viewModel)))
    }

    func openTimelineWindow(viewModel: MboxViewModel) {
        let windowId = UUID()
        let window = MBoxWindow(
            id: windowId,
            type: .timeline,
            title: "Timeline",
            emailIds: []
        )

        openWindows.append(window)
        createNSWindow(for: window, content: AnyView(TimelineView(viewModel: viewModel)))
    }

    func closeWindow(_ windowId: UUID) {
        windowControllers[windowId]?.close()
        windowControllers.removeValue(forKey: windowId)
        openWindows.removeAll { $0.id == windowId }
    }

    func closeAllWindows() {
        for (_, controller) in windowControllers {
            controller.close()
        }
        windowControllers.removeAll()
        openWindows.removeAll()
    }

    // MARK: - NSWindow Creation

    private func createNSWindow<Content: View>(for window: MBoxWindow, content: Content) {
        let contentView = NSHostingView(rootView: content)

        let nsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: window.type.defaultSize.width, height: window.type.defaultSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        nsWindow.title = window.title
        nsWindow.contentView = contentView
        nsWindow.center()
        nsWindow.setFrameAutosaveName(window.type.rawValue + "_" + window.id.uuidString)

        // Set minimum size
        nsWindow.minSize = window.type.minSize

        let controller = NSWindowController(window: nsWindow)
        windowControllers[window.id] = controller

        // Handle window close
        nsWindow.delegate = WindowDelegate(windowId: window.id, manager: self)

        controller.showWindow(nil)
    }

    // MARK: - Window State

    func bringToFront(_ windowId: UUID) {
        windowControllers[windowId]?.window?.makeKeyAndOrderFront(nil)
    }

    func isWindowOpen(_ windowId: UUID) -> Bool {
        windowControllers[windowId]?.window?.isVisible == true
    }
}

// MARK: - Window Delegate

class WindowDelegate: NSObject, NSWindowDelegate {
    let windowId: UUID
    weak var manager: MultiWindowManager?

    init(windowId: UUID, manager: MultiWindowManager) {
        self.windowId = windowId
        self.manager = manager
    }

    func windowWillClose(_ notification: Notification) {
        manager?.openWindows.removeAll { $0.id == windowId }
        manager?.windowControllers.removeValue(forKey: windowId)
    }
}

// MARK: - Window Views

struct EmailWindowView: View {
    let email: Email

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(email.subject)
                        .font(.title2)
                        .fontWeight(.bold)

                    HStack {
                        Text("From:")
                            .foregroundColor(.secondary)
                        Text(email.from)
                    }

                    HStack {
                        Text("To:")
                            .foregroundColor(.secondary)
                        Text(email.to ?? "")
                    }

                    HStack {
                        Text("Date:")
                            .foregroundColor(.secondary)
                        Text(email.date)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                Divider()

                // Body
                Text(email.body)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct ComparisonWindowView: View {
    let emails: [Email]

    var body: some View {
        HSplitView {
            ForEach(emails) { email in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(email.subject)
                            .font(.headline)

                        Text(email.from)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text(email.date)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        Text(email.body)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding()
                }
                .frame(minWidth: 300)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct SearchWindowView: View {
    @ObservedObject var viewModel: MboxViewModel
    @State private var searchText = ""

    var body: some View {
        VStack {
            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()

            List {
                ForEach(filteredEmails) { email in
                    VStack(alignment: .leading) {
                        Text(email.subject)
                            .fontWeight(.medium)
                        Text(email.from)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private var filteredEmails: [Email] {
        if searchText.isEmpty {
            return viewModel.emails
        }
        let query = searchText.lowercased()
        return viewModel.emails.filter {
            $0.subject.lowercased().contains(query) ||
            $0.from.lowercased().contains(query) ||
            $0.body.lowercased().contains(query)
        }
    }
}

// MARK: - Models

struct MBoxWindow: Identifiable {
    let id: UUID
    let type: WindowType
    let title: String
    let emailIds: [UUID]
    var createdAt = Date()
}

enum WindowType: String {
    case emailDetail = "EmailDetail"
    case comparison = "Comparison"
    case search = "Search"
    case timeline = "Timeline"
    case heatmap = "Heatmap"
    case network = "Network"

    var defaultSize: CGSize {
        switch self {
        case .emailDetail: return CGSize(width: 600, height: 500)
        case .comparison: return CGSize(width: 1000, height: 600)
        case .search: return CGSize(width: 500, height: 600)
        case .timeline: return CGSize(width: 800, height: 500)
        case .heatmap: return CGSize(width: 700, height: 600)
        case .network: return CGSize(width: 800, height: 700)
        }
    }

    var minSize: CGSize {
        switch self {
        case .emailDetail: return CGSize(width: 400, height: 300)
        case .comparison: return CGSize(width: 600, height: 400)
        case .search: return CGSize(width: 300, height: 400)
        case .timeline: return CGSize(width: 500, height: 300)
        case .heatmap: return CGSize(width: 400, height: 400)
        case .network: return CGSize(width: 500, height: 400)
        }
    }
}

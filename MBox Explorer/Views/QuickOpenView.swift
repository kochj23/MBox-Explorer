//
//  QuickOpenView.swift
//  MBox Explorer
//
//  Quick open dialog for recent files (⌘⇧O)
//

import SwiftUI

struct QuickOpenView: View {
    @EnvironmentObject var recentFilesViewModel: RecentFilesViewModel
    @Binding var isPresented: Bool
    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    let onSelect: (URL) -> Void

    var filteredFiles: [RecentFilesViewModel.RecentFileInfo] {
        if searchText.isEmpty {
            return recentFilesViewModel.recentFiles
        }

        return recentFilesViewModel.recentFiles.filter { fileInfo in
            fileInfo.url.lastPathComponent.localizedCaseInsensitiveContains(searchText) ||
            fileInfo.url.path.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.title3)

                TextField("Search recent files...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit {
                        openSelectedFile()
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Recent files list
            if filteredFiles.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Recent Files" : "No Matching Files",
                    systemImage: "clock",
                    description: Text(searchText.isEmpty ? "Open an MBOX file to see it here" : "Try a different search term")
                )
                .frame(minHeight: 300)
            } else {
                ScrollViewReader { proxy in
                    List(Array(filteredFiles.enumerated()), id: \.offset, selection: $selectedIndex) { index, fileInfo in
                        QuickOpenRow(
                            fileInfo: fileInfo,
                            isSelected: index == selectedIndex
                        )
                        .tag(index)
                        .onTapGesture {
                            selectedIndex = index
                            openSelectedFile()
                        }
                        .id(index)
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 300, maxHeight: 500)
                    .onChange(of: selectedIndex) { oldValue, newValue in
                        withAnimation {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            // Footer with keyboard shortcuts
            HStack {
                Label("↑↓ Navigate", systemImage: "arrow.up.arrow.down")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Label("↵ Open", systemImage: "return")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Label("⎋ Close", systemImage: "escape")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .frame(width: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
        .onAppear {
            // Focus on search field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApplication.shared.keyWindow?.makeFirstResponder(nil)
            }
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return KeyPress.Result.handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredFiles.count - 1 {
                selectedIndex += 1
            }
            return KeyPress.Result.handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return KeyPress.Result.handled
        }
    }

    private func openSelectedFile() {
        guard selectedIndex < filteredFiles.count else { return }
        let fileInfo = filteredFiles[selectedIndex]
        isPresented = false
        onSelect(fileInfo.url)
    }
}

struct QuickOpenRow: View {
    let fileInfo: RecentFilesViewModel.RecentFileInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundColor(isSelected ? .white : .blue)
                .frame(width: 40)

            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(fileInfo.url.lastPathComponent)
                    .font(.body)
                    .bold()
                    .foregroundColor(isSelected ? .white : .primary)

                HStack(spacing: 8) {
                    Text(fileInfo.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)

                    if let date = fileInfo.lastOpened {
                        Text("•")
                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    }
                }
            }

            Spacer()

            // File size badge
            if let size = fileInfo.fileSize {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.blue.opacity(0.1))
                    .foregroundColor(isSelected ? .white : .blue)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor : Color.clear)
        .cornerRadius(8)
    }
}

// MARK: - Keyboard Shortcut Extension

extension View {
    func onKeyPress(_ key: KeyEquivalent, action: @escaping () -> KeyPress.Result) -> some View {
        self.onKeyPress(keys: [key], action: action)
    }

    func onKeyPress(keys: [KeyEquivalent], action: @escaping () -> KeyPress.Result) -> some View {
        self.background(
            KeyPressHandlerView(keys: keys, action: action)
        )
    }
}

private struct KeyPressHandlerView: NSViewRepresentable {
    let keys: [KeyEquivalent]
    let action: () -> KeyPress.Result

    func makeNSView(context: Context) -> NSView {
        let view = KeyHandlerNSView()
        view.keys = keys
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class KeyHandlerNSView: NSView {
        var keys: [KeyEquivalent] = []
        var action: (() -> KeyPress.Result)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            // Check for special keys
            if event.keyCode == 53 { // Escape
                if keys.contains(KeyEquivalent.escape) {
                    if action?() == .handled {
                        return
                    }
                }
            } else if event.keyCode == 126 { // Up arrow
                if keys.contains(KeyEquivalent.upArrow) {
                    if action?() == .handled {
                        return
                    }
                }
            } else if event.keyCode == 125 { // Down arrow
                if keys.contains(KeyEquivalent.downArrow) {
                    if action?() == .handled {
                        return
                    }
                }
            }

            super.keyDown(with: event)
        }
    }
}

enum KeyPress {
    enum Result {
        case handled
        case ignored
    }
}

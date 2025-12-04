//
//  EmailListView.swift
//  MBox Explorer
//
//  Email list with search and filtering
//

import SwiftUI

struct EmailListView: View {
    @ObservedObject var viewModel: MboxViewModel
    let selectedView: SidebarItem
    @FocusState private var searchFieldFocused: Bool
    @State private var showingKeyboardHelp = false

    var body: some View {
        VStack(spacing: 0) {
            // Search and filter bar
            SearchFilterBar(viewModel: viewModel, searchFieldFocused: $searchFieldFocused)

            // Column headers and batch actions
            if !viewModel.emails.isEmpty {
                ColumnHeaders(viewModel: viewModel)

                // Batch selection toolbar
                if !viewModel.selectedEmails.isEmpty {
                    BatchSelectionToolbar(viewModel: viewModel)
                }
            }

            // Email list
            List(viewModel.filteredEmails, selection: $viewModel.selectedEmail) { email in
                EmailRow(email: email, viewModel: viewModel)
                    .tag(email)
                    .contextMenu {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(email.from, forType: .string)
                        } label: {
                            Label("Copy Email Address", systemImage: "envelope")
                        }

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(email.subject, forType: .string)
                        } label: {
                            Label("Copy Subject", systemImage: "doc.on.doc")
                        }

                        if let messageId = email.messageId {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(messageId, forType: .string)
                            } label: {
                                Label("Copy Message ID", systemImage: "number")
                            }
                        }

                        Divider()

                        Button(role: .destructive) {
                            viewModel.selectedEmail = email
                            viewModel.deleteSelectedEmail()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .listStyle(.sidebar)
            .overlay(alignment: .bottom) {
                if viewModel.isLoading {
                    LoadingOverlay()
                }
            }

            // Status bar
            if !viewModel.statusMessage.isEmpty {
                StatusBar(message: viewModel.statusMessage)
            } else if !viewModel.filteredEmails.isEmpty {
                StatusBar(message: "Showing \(viewModel.filteredEmails.count) of \(viewModel.emails.count) emails")
            }
        }
        .navigationTitle(selectedView.rawValue)
        .onChange(of: viewModel.searchText) {
            Task { @MainActor in
                viewModel.applyFilters()
            }
        }
        .onChange(of: viewModel.filterSender) {
            Task { @MainActor in
                viewModel.applyFilters()
            }
        }
        .onChange(of: viewModel.startDate) {
            Task { @MainActor in
                viewModel.applyFilters()
            }
        }
        .onChange(of: viewModel.endDate) {
            Task { @MainActor in
                viewModel.applyFilters()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            searchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showKeyboardHelp)) { _ in
            showingKeyboardHelp = true
        }
        .modifier(KeyboardNavigationModifier(viewModel: viewModel, searchFocused: $searchFieldFocused))
        .sheet(isPresented: $showingKeyboardHelp) {
            KeyboardShortcutsView(isPresented: $showingKeyboardHelp)
        }
    }
}

struct StatusBar: View {
    let message: String

    var body: some View {
        HStack {
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Divider(), alignment: .top)
    }
}

struct LoadingOverlay: View {
    var body: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.95))
        .cornerRadius(8)
        .shadow(radius: 4)
        .padding(.bottom, 60)
    }
}

struct SearchFilterBar: View {
    @ObservedObject var viewModel: MboxViewModel
    @FocusState.Binding var searchFieldFocused: Bool
    @State private var showingDatePicker = false
    @State private var showingSearchHistory = false
    @State private var showingSavedSearches = false
    @State private var showingAdvancedFilters = false
    @StateObject private var searchManager = SearchHistoryManager.shared

    var body: some View {
        VStack(spacing: 8) {
            // Search field with history and saved searches
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search emails...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFieldFocused)
                    .onSubmit {
                        // Add to history when user presses enter
                        let filters = SearchFilters(
                            sender: viewModel.filterSender,
                            startDate: viewModel.startDate,
                            endDate: viewModel.endDate
                        )
                        searchManager.addToHistory(viewModel.searchText, filters: filters)
                    }

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Search history button
                Button {
                    showingSearchHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Search History")
                .popover(isPresented: $showingSearchHistory) {
                    SearchHistoryPopover(
                        searchManager: searchManager,
                        viewModel: viewModel,
                        isPresented: $showingSearchHistory
                    )
                }

                // Saved searches button
                Button {
                    showingSavedSearches = true
                } label: {
                    Image(systemName: "star.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Saved Searches")
                .sheet(isPresented: $showingSavedSearches) {
                    SavedSearchesView(
                        searchManager: searchManager,
                        viewModel: viewModel,
                        isPresented: $showingSavedSearches
                    )
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)

            // Sender filter
            HStack {
                Image(systemName: "person")
                    .foregroundColor(.secondary)
                TextField("Filter by sender...", text: $viewModel.filterSender)
                    .textFieldStyle(.plain)
                if !viewModel.filterSender.isEmpty {
                    Button {
                        viewModel.filterSender = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)

            // Date filter
            HStack {
                Button {
                    showingDatePicker.toggle()
                } label: {
                    Label("Date Range", systemImage: "calendar")
                }
                Spacer()
                if viewModel.startDate != nil || viewModel.endDate != nil {
                    Button("Clear") {
                        viewModel.startDate = nil
                        viewModel.endDate = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
            }

            // Date range presets
            if showingDatePicker {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        DatePresetButton(title: "Today", viewModel: viewModel) {
                            let calendar = Calendar.current
                            let today = calendar.startOfDay(for: Date())
                            viewModel.startDate = today
                            viewModel.endDate = calendar.date(byAdding: .day, value: 1, to: today)
                        }

                        DatePresetButton(title: "Yesterday", viewModel: viewModel) {
                            let calendar = Calendar.current
                            let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
                            viewModel.startDate = calendar.startOfDay(for: yesterday)
                            viewModel.endDate = calendar.startOfDay(for: Date())
                        }

                        DatePresetButton(title: "Last 7 Days", viewModel: viewModel) {
                            let calendar = Calendar.current
                            viewModel.startDate = calendar.date(byAdding: .day, value: -7, to: Date())
                            viewModel.endDate = Date()
                        }

                        DatePresetButton(title: "Last 30 Days", viewModel: viewModel) {
                            let calendar = Calendar.current
                            viewModel.startDate = calendar.date(byAdding: .day, value: -30, to: Date())
                            viewModel.endDate = Date()
                        }

                        DatePresetButton(title: "This Month", viewModel: viewModel) {
                            let calendar = Calendar.current
                            let components = calendar.dateComponents([.year, .month], from: Date())
                            viewModel.startDate = calendar.date(from: components)
                            viewModel.endDate = Date()
                        }

                        DatePresetButton(title: "Last Month", viewModel: viewModel) {
                            let calendar = Calendar.current
                            let lastMonth = calendar.date(byAdding: .month, value: -1, to: Date())!
                            let components = calendar.dateComponents([.year, .month], from: lastMonth)
                            viewModel.startDate = calendar.date(from: components)
                            if let start = viewModel.startDate {
                                viewModel.endDate = calendar.date(byAdding: .month, value: 1, to: start)
                            }
                        }

                        DatePresetButton(title: "This Year", viewModel: viewModel) {
                            let calendar = Calendar.current
                            let components = calendar.dateComponents([.year], from: Date())
                            viewModel.startDate = calendar.date(from: components)
                            viewModel.endDate = Date()
                        }
                    }
                    .padding(.vertical, 4)
                }

                DatePicker("From:", selection: Binding(
                    get: { viewModel.startDate ?? Date() },
                    set: { viewModel.startDate = $0 }
                ), displayedComponents: .date)
                DatePicker("To:", selection: Binding(
                    get: { viewModel.endDate ?? Date() },
                    set: { viewModel.endDate = $0 }
                ), displayedComponents: .date)
            }

            // Advanced filters
            DisclosureGroup("Advanced Filters", isExpanded: $showingAdvancedFilters) {
                VStack(spacing: 12) {
                    // Domain filter
                    HStack {
                        Image(systemName: "at")
                            .foregroundColor(.secondary)
                        TextField("Filter by domain (e.g., company.com)", text: $viewModel.filterDomain)
                            .textFieldStyle(.plain)
                        if !viewModel.filterDomain.isEmpty {
                            Button {
                                viewModel.filterDomain = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Size filter with presets
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email Size")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button("< 1KB") {
                                viewModel.filterSizeMin = nil
                                viewModel.filterSizeMax = 1024
                            }.buttonStyle(.bordered).controlSize(.small)

                            Button("1-10KB") {
                                viewModel.filterSizeMin = 1024
                                viewModel.filterSizeMax = 10240
                            }.buttonStyle(.bordered).controlSize(.small)

                            Button("10-100KB") {
                                viewModel.filterSizeMin = 10240
                                viewModel.filterSizeMax = 102400
                            }.buttonStyle(.bordered).controlSize(.small)

                            Button("> 100KB") {
                                viewModel.filterSizeMin = 102400
                                viewModel.filterSizeMax = nil
                            }.buttonStyle(.bordered).controlSize(.small)

                            Button("Clear") {
                                viewModel.filterSizeMin = nil
                                viewModel.filterSizeMax = nil
                            }.buttonStyle(.bordered).controlSize(.small).foregroundColor(.red)
                        }

                        if viewModel.filterSizeMin != nil || viewModel.filterSizeMax != nil {
                            HStack {
                                if let min = viewModel.filterSizeMin {
                                    Text("Min: \(ByteCountFormatter.string(fromByteCount: Int64(min), countStyle: .file))")
                                        .font(.caption2)
                                }
                                if let max = viewModel.filterSizeMax {
                                    Text("Max: \(ByteCountFormatter.string(fromByteCount: Int64(max), countStyle: .file))")
                                        .font(.caption2)
                                }
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
    }
}

struct ColumnHeaders: View {
    @ObservedObject var viewModel: MboxViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Sender column
            Button {
                viewModel.toggleSort(by: .sender)
            } label: {
                HStack(spacing: 4) {
                    Text("From")
                        .font(.caption)
                        .bold()
                    if viewModel.sortField == .sender {
                        Image(systemName: viewModel.sortOrder == .ascending ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)

            // Subject column
            Button {
                viewModel.toggleSort(by: .subject)
            } label: {
                HStack(spacing: 4) {
                    Text("Subject")
                        .font(.caption)
                        .bold()
                    if viewModel.sortField == .subject {
                        Image(systemName: viewModel.sortOrder == .ascending ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)

            // Date column
            Button {
                viewModel.toggleSort(by: .date)
            } label: {
                HStack(spacing: 4) {
                    Text("Date")
                        .font(.caption)
                        .bold()
                    if viewModel.sortField == .date {
                        Image(systemName: viewModel.sortOrder == .ascending ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                }
                .frame(width: 100, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)

            // Size column
            Button {
                viewModel.toggleSort(by: .size)
            } label: {
                HStack(spacing: 4) {
                    Text("Size")
                        .font(.caption)
                        .bold()
                    if viewModel.sortField == .size {
                        Image(systemName: viewModel.sortOrder == .ascending ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                }
                .frame(width: 60, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }
}

struct BatchSelectionToolbar: View {
    @ObservedObject var viewModel: MboxViewModel
    @State private var showingExportDialog = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(viewModel.selectedEmails.count) selected")
                .font(.caption)
                .bold()
                .foregroundColor(.blue)

            Spacer()

            Button {
                if viewModel.selectedEmails.count == viewModel.filteredEmails.count {
                    viewModel.deselectAll()
                } else {
                    viewModel.selectAllInCurrentView()
                }
            } label: {
                Text(viewModel.selectedEmails.count == viewModel.filteredEmails.count ? "Deselect All" : "Select All")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                showingExportDialog = true
            } label: {
                Label("Export Selected", systemImage: "square.and.arrow.up")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(role: .destructive) {
                viewModel.deleteSelectedEmails()
            } label: {
                Label("Delete Selected", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
        .overlay(Divider(), alignment: .bottom)
        .sheet(isPresented: $showingExportDialog) {
            ExportSelectedDialog(viewModel: viewModel, isPresented: $showingExportDialog)
        }
    }
}

struct ExportSelectedDialog: View {
    @ObservedObject var viewModel: MboxViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Export Selected Emails")
                .font(.title2)
                .bold()

            Text("Export \(viewModel.selectedEmails.count) selected emails to a folder")
                .font(.body)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Export...") {
                    isPresented = false
                    let panel = NSSavePanel()
                    panel.canCreateDirectories = true
                    panel.nameFieldStringValue = "Selected_Export"
                    panel.message = "Choose location to export selected emails"

                    panel.begin { (response: NSApplication.ModalResponse) in
                        if response == .OK, let url = panel.url {
                            Task {
                                await viewModel.exportSelectedEmails(to: url)
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

struct DatePresetButton: View {
    let title: String
    @ObservedObject var viewModel: MboxViewModel
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct SearchHistoryPopover: View {
    @ObservedObject var searchManager: SearchHistoryManager
    @ObservedObject var viewModel: MboxViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Search History")
                    .font(.headline)
                Spacer()
                if !searchManager.searchHistory.isEmpty {
                    Button("Clear") {
                        searchManager.clearHistory()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
            .padding()

            Divider()

            // History list
            if searchManager.searchHistory.isEmpty {
                Text("No recent searches")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(searchManager.searchHistory.prefix(10)) { item in
                            Button {
                                applySearch(item)
                                isPresented = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.displayText)
                                            .font(.body)
                                            .lineLimit(2)
                                            .foregroundColor(.primary)

                                        Text(item.relativeTime)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()

                                    Button {
                                        searchManager.removeFromHistory(item)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.001))

                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        .frame(width: 350)
    }

    private func applySearch(_ item: SearchHistoryItem) {
        viewModel.searchText = item.query
        viewModel.filterSender = item.filters.sender
        viewModel.startDate = item.filters.startDate
        viewModel.endDate = item.filters.endDate
    }
}

struct EmailRow: View {
    let email: Email
    @ObservedObject var viewModel: MboxViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox for batch selection
            Button {
                toggleSelection()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: densitySpacing) {
                HStack {
                    Text(email.from)
                        .font(densityFont)
                        .lineLimit(1)
                    Spacer()
                    if email.hasAttachments {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    Text(email.displayDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if showSubject {
                    HStack {
                        if !viewModel.searchText.isEmpty {
                            Text.highlighted(
                                email.subject,
                                searchTerms: [viewModel.searchText]
                            )
                            .font(.subheadline)
                            .lineLimit(1)
                        } else {
                            Text(email.subject)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        if email.hasAttachments {
                            Text("(\(email.attachmentCount))")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                }

                if showPreview {
                    if !viewModel.searchText.isEmpty {
                        Text.highlighted(
                            String(email.body.prefix(100)),
                            searchTerms: [viewModel.searchText]
                        )
                        .font(.caption)
                        .lineLimit(densityPreviewLines)
                    } else {
                        Text(email.body.prefix(100))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(densityPreviewLines)
                    }
                }
            }
        }
        .padding(.vertical, densityPadding)
    }

    private var densitySpacing: CGFloat {
        switch viewModel.listDensity {
        case .compact: return 2
        case .comfortable: return 4
        case .spacious: return 6
        }
    }

    private var densityPadding: CGFloat {
        switch viewModel.listDensity {
        case .compact: return 2
        case .comfortable: return 4
        case .spacious: return 8
        }
    }

    private var densityFont: Font {
        switch viewModel.listDensity {
        case .compact: return .subheadline
        case .comfortable: return .headline
        case .spacious: return .headline
        }
    }

    private var showSubject: Bool {
        viewModel.listDensity != .compact
    }

    private var showPreview: Bool {
        viewModel.listDensity == .comfortable || viewModel.listDensity == .spacious
    }

    private var densityPreviewLines: Int {
        switch viewModel.listDensity {
        case .compact: return 0
        case .comfortable: return 2
        case .spacious: return 3
        }
    }

    private var isSelected: Bool {
        viewModel.selectedEmails.contains(email.id)
    }

    private func toggleSelection() {
        if isSelected {
            viewModel.selectedEmails.remove(email.id)
        } else {
            viewModel.selectedEmails.insert(email.id)
        }
    }
}

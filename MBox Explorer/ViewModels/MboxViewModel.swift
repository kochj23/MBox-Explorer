//
//  MboxViewModel.swift
//  MBox Explorer
//
//  Main view model managing app state
//

import Foundation
import Combine
import AppKit

@MainActor
class MboxViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var emails: [Email] = []
    @Published var threads: [EmailThread] = []
    @Published var filteredEmails: [Email] = []
    @Published var selectedEmail: Email?
    @Published var selectedEmails: Set<Email.ID> = []
    @Published var searchText: String = ""
    @Published var filterSender: String = ""
    @Published var filterDomain: String = ""
    @Published var filterSizeMin: Int?
    @Published var filterSizeMax: Int?
    @Published var startDate: Date?
    @Published var endDate: Date?
    @Published var showingExportOptions = false
    @Published var exportOptions = ExportEngine.ExportOptions()
    @Published var statusMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var showingProgressSheet: Bool = false
    @Published var showingExportProgress: Bool = false
    @Published var showingSmartFilters: Bool = false
    @Published var showingDuplicates: Bool = false
    @Published var smartFilters = SmartFilters()
    @Published var sortField: WindowStateManager.SortField = .date
    @Published var sortOrder: WindowStateManager.SortOrder = .descending
    @Published var lastExportURL: URL?
    @Published var currentFileURL: URL?
    @Published var listDensity: WindowStateManager.ListDensity = WindowStateManager.shared.loadListDensity()
    @Published var showingEmailComparison: Bool = false
    @Published var comparisonEmail: Email?
    @Published var showingRegexSearch: Bool = false
    @Published var showingRedactionTool: Bool = false
    @Published var showingThemeSettings: Bool = false
    @Published var layoutMode: WindowStateManager.LayoutMode = WindowStateManager.shared.loadLayoutMode()
    @Published var showOpenPanel: Bool = false
    @Published var showExportPanel: Bool = false
    @Published var currentView: ViewMode = .list
    @Published var isSearching: Bool = false
    @Published var showSettings: Bool = false
    @Published var showAISettings: Bool = false
    var loadStartTime: Date?

    enum ViewMode {
        case list, ask, timeline, heatmap, network, attachments, duplicates
    }

    // Alert manager (injected from ContentView)
    var alertManager: AlertManager?

    // MARK: - Computed Properties

    var stats: Stats {
        Stats(
            totalEmails: emails.count,
            totalThreads: threads.count,
            dateRange: dateRangeString,
            topSenders: topSenders(limit: 5)
        )
    }

    private var dateRangeString: String {
        guard let earliest = emails.compactMap({ $0.dateObject }).min(),
              let latest = emails.compactMap({ $0.dateObject }).max() else {
            return "No emails"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: earliest)) - \(formatter.string(from: latest))"
    }

    private func topSenders(limit: Int) -> [(String, Int)] {
        Dictionary(grouping: emails, by: { $0.from })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }

    // MARK: - Services

    let parser = MboxParser()
    let exporter = ExportEngine()

    // MARK: - Methods

    func loadMboxFile(url: URL) async {
        isLoading = true
        loadStartTime = Date()
        showingProgressSheet = true
        statusMessage = "Loading MBOX file..."
        currentFileURL = url

        do {
            emails = try await parser.parse(fileURL: url)
            statusMessage = "Detecting threads..."
            threads = parser.detectThreads(emails: emails)
            applyFilters()
            showingProgressSheet = false
            statusMessage = "Loaded \(emails.count) emails, \(threads.count) threads"

            // Clear status after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            statusMessage = ""
        } catch {
            showingProgressSheet = false
            if let mboxError = error as? MboxError, mboxError == .cancelled {
                statusMessage = "Loading cancelled"
            } else {
                statusMessage = "Error loading MBOX: \(error.localizedDescription)"
                alertManager?.showError("Failed to Load MBOX",
                                       message: "An error occurred while loading the MBOX file",
                                       details: error.localizedDescription)
            }
        }

        isLoading = false
    }

    func applyFilters() {
        var results = emails

        // Search text filter
        if !searchText.isEmpty {
            results = results.filter { email in
                email.from.localizedCaseInsensitiveContains(searchText) ||
                email.subject.localizedCaseInsensitiveContains(searchText) ||
                email.body.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sender filter
        if !filterSender.isEmpty {
            results = results.filter { $0.from.localizedCaseInsensitiveContains(filterSender) }
        }

        // Domain filter
        if !filterDomain.isEmpty {
            results = results.filter { email in
                email.from.localizedCaseInsensitiveContains("@\(filterDomain)") ||
                (email.to?.localizedCaseInsensitiveContains("@\(filterDomain)") ?? false)
            }
        }

        // Size filter
        if let minSize = filterSizeMin {
            results = results.filter { $0.body.count >= minSize }
        }

        if let maxSize = filterSizeMax {
            results = results.filter { $0.body.count <= maxSize }
        }

        // Date range filter
        if let startDate = startDate {
            results = results.filter { email in
                guard let emailDate = email.dateObject else { return false }
                return emailDate >= startDate
            }
        }

        if let endDate = endDate {
            results = results.filter { email in
                guard let emailDate = email.dateObject else { return false }
                return emailDate <= endDate
            }
        }

        // Smart filters
        results = applySmartFilters(to: results)

        // Apply sorting
        filteredEmails = applySorting(to: results)
    }

    private func applySorting(to emails: [Email]) -> [Email] {
        switch sortField {
        case .date:
            return emails.sorted {
                let date1 = $0.dateObject ?? .distantPast
                let date2 = $1.dateObject ?? .distantPast
                return sortOrder == .ascending ? date1 < date2 : date1 > date2
            }
        case .sender:
            return emails.sorted {
                sortOrder == .ascending ? $0.from < $1.from : $0.from > $1.from
            }
        case .subject:
            return emails.sorted {
                sortOrder == .ascending ? $0.subject < $1.subject : $0.subject > $1.subject
            }
        case .size:
            return emails.sorted {
                sortOrder == .ascending ? $0.body.count < $1.body.count : $0.body.count > $1.body.count
            }
        }
    }

    func toggleSort(by field: WindowStateManager.SortField) {
        if sortField == field {
            sortOrder = sortOrder == .ascending ? .descending : .ascending
        } else {
            sortField = field
            sortOrder = .descending
        }
        WindowStateManager.shared.saveSortPreferences(field: sortField, order: sortOrder)
        applyFilters()
    }

    private func applySmartFilters(to emails: [Email]) -> [Email] {
        var results = emails

        // Attachment filters
        if smartFilters.hasAttachments {
            results = results.filter { $0.hasAttachments }
        }
        if smartFilters.hasNoAttachments {
            results = results.filter { !$0.hasAttachments }
        }

        // Exclude automated
        if smartFilters.excludeAutomated {
            results = results.filter { email in
                !email.from.lowercased().contains("noreply") &&
                !email.from.lowercased().contains("no-reply") &&
                !email.from.lowercased().contains("donotreply") &&
                !email.from.lowercased().contains("automated") &&
                !email.from.lowercased().contains("notification") &&
                !email.subject.lowercased().contains("[automated]")
            }
        }

        // Length filter
        if smartFilters.enableLengthFilter {
            results = results.filter { email in
                let length = email.body.count
                return length >= smartFilters.minLength && length <= smartFilters.maxLength
            }
        }

        // Regex filter
        if smartFilters.useRegex && smartFilters.isValidRegex {
            var options: NSRegularExpression.Options = []
            if !smartFilters.regexCaseSensitive {
                options.insert(.caseInsensitive)
            }

            if let regex = try? NSRegularExpression(pattern: smartFilters.regexPattern, options: options) {
                results = results.filter { email in
                    let searchText = "\(email.from) \(email.subject) \(email.body)"
                    let range = NSRange(searchText.startIndex..., in: searchText)
                    return regex.firstMatch(in: searchText, options: [], range: range) != nil
                }
            }
        }

        // Thread filters
        if smartFilters.onlyThreadRoots {
            results = results.filter { $0.inReplyTo == nil }
        }
        if smartFilters.onlyReplies {
            results = results.filter { $0.inReplyTo != nil }
        }

        return results
    }

    func countMatchingSmartFilters() -> Int {
        return applySmartFilters(to: emails).count
    }

    func exportAll(to directory: URL) async {
        isLoading = true
        statusMessage = "Exporting \(emails.count) emails..."

        do {
            try await exporter.exportEmails(
                emails,
                threads: threads,
                to: directory,
                options: exportOptions
            )
            lastExportURL = directory
            statusMessage = "Successfully exported to \(directory.lastPathComponent)"

            // Clear status after 5 seconds
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            statusMessage = ""
        } catch {
            statusMessage = "Error exporting: \(error.localizedDescription)"
            alertManager?.showError("Export Failed",
                                   message: "An error occurred while exporting emails",
                                   details: error.localizedDescription)
        }

        isLoading = false
    }

    func revealLastExportInFinder() {
        guard let url = lastExportURL else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    func exportFiltered(to directory: URL, filename: String) async {
        isLoading = true
        showingExportProgress = true
        statusMessage = "Exporting \(filteredEmails.count) filtered emails..."

        do {
            // Filter threads to only include those with emails in filtered results
            let filteredThreads = threads.filter { thread in
                thread.emails.contains(where: { email in
                    filteredEmails.contains(email)
                })
            }

            try await exporter.exportEmails(
                filteredEmails,
                threads: filteredThreads,
                to: directory,
                options: exportOptions
            )
            showingExportProgress = false
            statusMessage = "Successfully exported \(filteredEmails.count) emails to \(directory.lastPathComponent)"

            // Clear status after 5 seconds
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            statusMessage = ""
        } catch {
            showingExportProgress = false
            if let mboxError = error as? MboxError, mboxError == .cancelled {
                statusMessage = "Export cancelled"
            } else {
                statusMessage = "Error exporting: \(error.localizedDescription)"
                alertManager?.showError("Export Failed",
                                       message: "An error occurred while exporting filtered emails",
                                       details: error.localizedDescription)
            }
        }

        isLoading = false
    }

    var hasActiveFilters: Bool {
        !searchText.isEmpty || !filterSender.isEmpty || startDate != nil || endDate != nil
    }

    var isFiltered: Bool {
        hasActiveFilters && filteredEmails.count < emails.count
    }

    func selectNextEmail() {
        guard !filteredEmails.isEmpty else { return }

        if let current = selectedEmail,
           let index = filteredEmails.firstIndex(of: current),
           index < filteredEmails.count - 1 {
            selectedEmail = filteredEmails[index + 1]
        } else {
            selectedEmail = filteredEmails.first
        }
    }

    func selectPreviousEmail() {
        guard !filteredEmails.isEmpty else { return }

        if let current = selectedEmail,
           let index = filteredEmails.firstIndex(of: current),
           index > 0 {
            selectedEmail = filteredEmails[index - 1]
        } else {
            selectedEmail = filteredEmails.last
        }
    }

    func clearAllFilters() {
        searchText = ""
        filterSender = ""
        startDate = nil
        endDate = nil
        applyFilters()
    }

    func deleteSelectedEmail() {
        guard let email = selectedEmail else { return }

        // Find next email to select
        if let index = filteredEmails.firstIndex(of: email) {
            let nextIndex = index < filteredEmails.count - 1 ? index + 1 : max(0, index - 1)
            selectedEmail = filteredEmails.indices.contains(nextIndex) ? filteredEmails[nextIndex] : nil
        }

        // Remove from both lists
        emails.removeAll { $0.id == email.id }
        applyFilters()
    }

    func deleteSelectedEmails() {
        guard !selectedEmails.isEmpty else { return }

        emails.removeAll { selectedEmails.contains($0.id) }
        selectedEmails.removeAll()
        selectedEmail = nil
        applyFilters()
    }

    func selectAllInCurrentView() {
        selectedEmails = Set(filteredEmails.map { $0.id })
    }

    func deselectAll() {
        selectedEmails.removeAll()
    }

    func exportSelectedEmails(to directory: URL) async {
        let emailsToExport = emails.filter { selectedEmails.contains($0.id) }
        guard !emailsToExport.isEmpty else { return }

        isLoading = true
        showingExportProgress = true
        statusMessage = "Exporting \(emailsToExport.count) selected emails..."

        do {
            try await exporter.exportEmails(
                emailsToExport,
                threads: [],
                to: directory,
                options: exportOptions
            )
            showingExportProgress = false
            statusMessage = "Successfully exported \(emailsToExport.count) emails"

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            statusMessage = ""
        } catch {
            showingExportProgress = false
            statusMessage = "Error exporting: \(error.localizedDescription)"
            alertManager?.showError("Export Failed",
                                   message: "An error occurred while exporting selected emails",
                                   details: error.localizedDescription)
        }

        isLoading = false
    }

    func detectDuplicates() -> [(String, [Email])] {
        // Group emails by Message-ID
        var emailsByMessageId: [String: [Email]] = [:]

        for email in emails {
            if let messageId = email.messageId, !messageId.isEmpty {
                emailsByMessageId[messageId, default: []].append(email)
            }
        }

        // Filter to only groups with duplicates
        let duplicates = emailsByMessageId.filter { $0.value.count > 1 }
            .sorted { $0.value.count > $1.value.count }

        return duplicates.map { ($0.key, $0.value) }
    }

    func removeDuplicates(keepFirst: Bool = true) -> Int {
        var seen: Set<String> = []
        var toRemove: [UUID] = []

        let sorted = keepFirst
            ? emails.sorted { ($0.dateObject ?? .distantPast) < ($1.dateObject ?? .distantPast) }
            : emails.sorted { ($0.dateObject ?? .distantPast) > ($1.dateObject ?? .distantPast) }

        for email in sorted {
            if let messageId = email.messageId, !messageId.isEmpty {
                if seen.contains(messageId) {
                    toRemove.append(email.id)
                } else {
                    seen.insert(messageId)
                }
            }
        }

        emails.removeAll { toRemove.contains($0.id) }
        applyFilters()

        return toRemove.count
    }

    func exportThread(_ thread: EmailThread, to directory: URL) async {
        do {
            try await exporter.exportEmails(
                thread.emails,
                threads: [thread],
                to: directory,
                options: exportOptions
            )
        } catch {
            print("Error exporting thread: \(error)")
        }
    }

    func exportFromSender(_ sender: String, to directory: URL) async {
        let senderEmails = emails.filter { $0.from == sender }
        do {
            try await exporter.exportFiltered(
                senderEmails,
                to: directory,
                filename: "emails_from_\(TextProcessor.safeFilename(from: sender)).txt",
                options: exportOptions
            )
        } catch {
            print("Error exporting sender emails: \(error)")
        }
    }

    struct Stats {
        let totalEmails: Int
        let totalThreads: Int
        let dateRange: String
        let topSenders: [(String, Int)]
    }
}

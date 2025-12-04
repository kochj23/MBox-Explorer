//
//  RegexSearchView.swift
//  MBox Explorer
//
//  Advanced regex search and filter interface
//

import SwiftUI

struct RegexSearchView: View {
    @ObservedObject var viewModel: MboxViewModel
    @Binding var isPresented: Bool
    @State private var pattern: String = ""
    @State private var searchIn: SearchScope = .all
    @State private var caseSensitive: Bool = false
    @State private var multiline: Bool = false
    @State private var matchCount: Int = 0
    @State private var isValidPattern: Bool = true
    @State private var patternError: String = ""
    @State private var showingPresets: Bool = false
    @State private var recentPatterns: [RegexPattern] = []

    enum SearchScope: String, CaseIterable {
        case all = "Everywhere"
        case subject = "Subject Only"
        case body = "Body Only"
        case from = "From Only"
        case headers = "Headers Only"
    }

    struct RegexPattern: Identifiable, Codable {
        var id = UUID()
        var name: String
        var pattern: String
        var description: String
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Regex Search & Filter")
                    .font(.title2)
                    .bold()

                Spacer()

                Button {
                    showingPresets = true
                } label: {
                    Label("Pattern Library", systemImage: "book")
                }
                .buttonStyle(.bordered)

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Pattern input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Regex Pattern")
                            .font(.headline)

                        TextField("Enter regex pattern (e.g., \\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b)", text: $pattern)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: pattern) {
                                validatePattern()
                                updateMatchCount()
                            }

                        HStack {
                            if isValidPattern {
                                Label("Valid pattern", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Label(patternError, systemImage: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }

                            Spacer()

                            if isValidPattern && !pattern.isEmpty {
                                Text("\(matchCount) matches")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .bold()
                            }
                        }
                    }

                    // Options
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Search Options")
                            .font(.headline)

                        Picker("Search In", selection: $searchIn) {
                            ForEach(SearchScope.allCases, id: \.self) { scope in
                                Text(scope.rawValue).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: searchIn) {
                            updateMatchCount()
                        }

                        HStack(spacing: 20) {
                            Toggle("Case Sensitive", isOn: $caseSensitive)
                                .onChange(of: caseSensitive) {
                                    validatePattern()
                                    updateMatchCount()
                                }

                            Toggle("Multiline Mode", isOn: $multiline)
                                .onChange(of: multiline) {
                                    validatePattern()
                                    updateMatchCount()
                                }
                        }
                    }

                    Divider()

                    // Common patterns
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pattern Library")
                            .font(.headline)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            PatternButton(
                                title: "Email Address",
                                pattern: "\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b",
                                icon: "envelope"
                            ) { pattern = $0 }

                            PatternButton(
                                title: "Phone Number",
                                pattern: "\\b\\d{3}[-.]?\\d{3}[-.]?\\d{4}\\b",
                                icon: "phone"
                            ) { pattern = $0 }

                            PatternButton(
                                title: "URL",
                                pattern: "https?://[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}[/\\w.-]*",
                                icon: "link"
                            ) { pattern = $0 }

                            PatternButton(
                                title: "IP Address",
                                pattern: "\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\\b",
                                icon: "network"
                            ) { pattern = $0 }

                            PatternButton(
                                title: "Date (YYYY-MM-DD)",
                                pattern: "\\b\\d{4}-\\d{2}-\\d{2}\\b",
                                icon: "calendar"
                            ) { pattern = $0 }

                            PatternButton(
                                title: "Credit Card",
                                pattern: "\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b",
                                icon: "creditcard"
                            ) { pattern = $0 }

                            PatternButton(
                                title: "SSN",
                                pattern: "\\b\\d{3}-\\d{2}-\\d{4}\\b",
                                icon: "person.text.rectangle"
                            ) { pattern = $0 }

                            PatternButton(
                                title: "Quoted Text",
                                pattern: "^>.*$",
                                icon: "text.quote"
                            ) { pattern = $0 }
                        }
                    }

                    Divider()

                    // Regex guide
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quick Reference")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 4) {
                            RegexTipRow(pattern: "\\d", description: "Any digit (0-9)")
                            RegexTipRow(pattern: "\\w", description: "Any word character (a-z, A-Z, 0-9, _)")
                            RegexTipRow(pattern: "\\s", description: "Any whitespace")
                            RegexTipRow(pattern: ".", description: "Any character")
                            RegexTipRow(pattern: "*", description: "Zero or more")
                            RegexTipRow(pattern: "+", description: "One or more")
                            RegexTipRow(pattern: "?", description: "Zero or one")
                            RegexTipRow(pattern: "^", description: "Start of line")
                            RegexTipRow(pattern: "$", description: "End of line")
                            RegexTipRow(pattern: "\\b", description: "Word boundary")
                            RegexTipRow(pattern: "[abc]", description: "Any of a, b, or c")
                            RegexTipRow(pattern: "[^abc]", description: "Not a, b, or c")
                            RegexTipRow(pattern: "(ab|cd)", description: "Either ab or cd")
                        }
                        .font(.caption)
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Clear Pattern") {
                    pattern = ""
                    viewModel.smartFilters.regexPattern = ""
                    viewModel.smartFilters.useRegex = false
                    viewModel.applyFilters()
                }
                .disabled(pattern.isEmpty)

                Button("Save Pattern") {
                    savePattern()
                }
                .disabled(pattern.isEmpty || !isValidPattern)
                .buttonStyle(.bordered)

                Button("Apply Filter") {
                    applyRegexFilter()
                    isPresented = false
                }
                .disabled(pattern.isEmpty || !isValidPattern)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 700, height: 650)
        .onAppear {
            loadRecentPatterns()
            if !viewModel.smartFilters.regexPattern.isEmpty {
                pattern = viewModel.smartFilters.regexPattern
                caseSensitive = viewModel.smartFilters.regexCaseSensitive
            }
        }
        .sheet(isPresented: $showingPresets) {
            SavedPatternsView(
                patterns: $recentPatterns,
                isPresented: $showingPresets,
                onSelect: { selectedPattern in
                    pattern = selectedPattern.pattern
                }
            )
        }
    }

    private func validatePattern() {
        guard !pattern.isEmpty else {
            isValidPattern = true
            patternError = ""
            return
        }

        do {
            var options: NSRegularExpression.Options = []
            if !caseSensitive {
                options.insert(.caseInsensitive)
            }
            if multiline {
                options.insert(.anchorsMatchLines)
            }

            _ = try NSRegularExpression(pattern: pattern, options: options)
            isValidPattern = true
            patternError = ""
        } catch {
            isValidPattern = false
            patternError = "Invalid regex pattern"
        }
    }

    private func updateMatchCount() {
        guard isValidPattern && !pattern.isEmpty else {
            matchCount = 0
            return
        }

        do {
            var options: NSRegularExpression.Options = []
            if !caseSensitive {
                options.insert(.caseInsensitive)
            }
            if multiline {
                options.insert(.anchorsMatchLines)
            }

            let regex = try NSRegularExpression(pattern: pattern, options: options)

            var count = 0
            for email in viewModel.emails {
                let searchText = getSearchText(for: email)
                let range = NSRange(searchText.startIndex..., in: searchText)
                if regex.firstMatch(in: searchText, options: [], range: range) != nil {
                    count += 1
                }
            }

            matchCount = count
        } catch {
            matchCount = 0
        }
    }

    private func getSearchText(for email: Email) -> String {
        switch searchIn {
        case .all:
            return "\(email.from) \(email.subject) \(email.body) \(email.to ?? "")"
        case .subject:
            return email.subject
        case .body:
            return email.body
        case .from:
            return email.from
        case .headers:
            return "\(email.from) \(email.to ?? "") \(email.subject)"
        }
    }

    private func applyRegexFilter() {
        viewModel.smartFilters.regexPattern = pattern
        viewModel.smartFilters.useRegex = true
        viewModel.smartFilters.regexCaseSensitive = caseSensitive
        viewModel.applyFilters()

        // Save to recent patterns
        addToRecentPatterns()
    }

    private func savePattern() {
        // Show dialog to name the pattern
        let alert = NSAlert()
        alert.messageText = "Save Regex Pattern"
        alert.informativeText = "Enter a name for this pattern:"
        alert.alertStyle = .informational

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.placeholderString = "Pattern name"
        alert.accessoryView = input

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let name = input.stringValue
            if !name.isEmpty {
                let newPattern = RegexPattern(
                    name: name,
                    pattern: pattern,
                    description: "Custom pattern"
                )
                recentPatterns.insert(newPattern, at: 0)
                saveRecentPatterns()
            }
        }
    }

    private func loadRecentPatterns() {
        if let data = UserDefaults.standard.data(forKey: "RegexPatterns"),
           let decoded = try? JSONDecoder().decode([RegexPattern].self, from: data) {
            recentPatterns = decoded
        }
    }

    private func saveRecentPatterns() {
        if let encoded = try? JSONEncoder().encode(recentPatterns) {
            UserDefaults.standard.set(encoded, forKey: "RegexPatterns")
        }
    }

    private func addToRecentPatterns() {
        // Add pattern to recents if it's not already there
        if !recentPatterns.contains(where: { $0.pattern == pattern }) {
            let newPattern = RegexPattern(
                name: "Untitled Pattern",
                pattern: pattern,
                description: "Search in \(searchIn.rawValue)"
            )
            recentPatterns.insert(newPattern, at: 0)

            // Keep only last 20
            if recentPatterns.count > 20 {
                recentPatterns = Array(recentPatterns.prefix(20))
            }

            saveRecentPatterns()
        }
    }
}

// MARK: - Supporting Views

struct PatternButton: View {
    let title: String
    let pattern: String
    let icon: String
    let action: (String) -> Void

    var body: some View {
        Button {
            action(pattern)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .bold()
                    Text(pattern)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct RegexTipRow: View {
    let pattern: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Text(pattern)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.blue)
                .frame(width: 80, alignment: .leading)

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct SavedPatternsView: View {
    @Binding var patterns: [RegexSearchView.RegexPattern]
    @Binding var isPresented: Bool
    let onSelect: (RegexSearchView.RegexPattern) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Saved Patterns")
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

            if patterns.isEmpty {
                ContentUnavailableView(
                    "No Saved Patterns",
                    systemImage: "tray",
                    description: Text("Save patterns to reuse them later")
                )
            } else {
                List {
                    ForEach(patterns) { pattern in
                        Button {
                            onSelect(pattern)
                            isPresented = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pattern.name)
                                    .font(.headline)
                                Text(pattern.pattern)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        patterns.remove(atOffsets: indexSet)
                        savePatterns()
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
    }

    private func savePatterns() {
        if let encoded = try? JSONEncoder().encode(patterns) {
            UserDefaults.standard.set(encoded, forKey: "RegexPatterns")
        }
    }
}

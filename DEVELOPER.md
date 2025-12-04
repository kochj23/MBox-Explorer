# MBox Explorer - Developer Documentation

This document provides comprehensive technical documentation for developers working on or extending MBox Explorer.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Project Structure](#project-structure)
3. [Design Patterns](#design-patterns)
4. [Core Components](#core-components)
5. [Data Flow](#data-flow)
6. [State Management](#state-management)
7. [Performance Considerations](#performance-considerations)
8. [Adding New Features](#adding-new-features)
9. [Testing](#testing)
10. [Build and Deployment](#build-and-deployment)
11. [Contributing Guidelines](#contributing-guidelines)
12. [Code Style](#code-style)
13. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

MBox Explorer follows a clean, modular architecture built on SwiftUI and modern Swift patterns.

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    SwiftUI Views                         │
│  (ContentView, EmailListView, EmailDetailView, etc.)   │
└───────────────────┬─────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────┐
│                  ViewModels                              │
│         (MboxViewModel - @ObservedObject)               │
│         Manages application state and logic              │
└───────────────────┬─────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────┐
│                   Models                                 │
│       (Email, MboxParser, AnalyticsEngine)              │
│         Pure Swift data structures                       │
└───────────────────┬─────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────┐
│                 Utilities                                │
│   (ExportEngine, TextProcessor, PIIRedactor, etc.)      │
│         Helper functions and algorithms                  │
└─────────────────────────────────────────────────────────┘
```

### Architecture Principles

1. **MVVM Pattern**: Separation of View, ViewModel, and Model
2. **Unidirectional Data Flow**: State flows down, events flow up
3. **Single Source of Truth**: `MboxViewModel` owns app state
4. **Reactive Updates**: SwiftUI `@Published` for automatic UI updates
5. **Async/Await**: Modern concurrency for I/O operations
6. **Immutability**: Data structures are immutable where possible
7. **Protocol-Oriented**: Use protocols for extensibility

---

## Project Structure

```
MBox Explorer/
├── MBox_ExplorerApp.swift       # App entry point, menu commands
│
├── Models/
│   ├── Email.swift               # Email data structure
│   ├── MboxParser.swift          # MBOX file parser
│   ├── AnalyticsEngine.swift     # Analytics calculations
│   └── ExportPresetManager.swift # Export presets management
│
├── ViewModels/
│   └── MboxViewModel.swift       # Main app state manager
│
├── Views/
│   ├── ContentView.swift         # Main 3-column layout
│   ├── SidebarView.swift         # Navigation sidebar
│   ├── EmailListView.swift       # Email list with search
│   ├── EmailDetailView.swift    # Email detail pane
│   ├── ExportOptionsView.swift   # Export configuration sheet
│   ├── ExportPreviewView.swift   # Export preview
│   ├── AnalyticsView.swift       # Analytics dashboard
│   ├── DuplicatesView.swift      # Duplicate detection UI
│   ├── SmartFiltersView.swift    # Smart filter interface
│   ├── QuickOpenView.swift       # Recent files dialog
│   ├── RegexSearchView.swift     # Regex search UI
│   ├── RedactionToolView.swift   # PII redaction interface
│   ├── EmailComparisonView.swift # Side-by-side comparison
│   ├── ThemeSettingsView.swift   # Theme customization
│   ├── ThreeColumnLayoutView.swift # 3-column layout
│   ├── MboxOperationsView.swift  # Merge/split operations
│   ├── ThreadVisualizationView.swift # Thread diagrams
│   ├── ToolbarCommands.swift     # Toolbar button handlers
│   ├── ExportPresetsView.swift   # Presets management UI
│   └── ProgressView.swift        # Progress indicators
│
├── Utilities/
│   ├── TextProcessor.swift       # Text cleaning and chunking
│   ├── TextHighlighter.swift     # Search highlighting
│   ├── MboxFileOperations.swift  # Merge/split operations
│   ├── DuplicateDetector.swift   # Duplicate finding
│   ├── SmartFilters.swift        # Filter logic
│   ├── SyntaxHighlighter.swift   # Code highlighting
│   ├── PIIRedactor.swift         # PII detection/redaction
│   ├── ThemeManager.swift        # Theme management
│   ├── WindowStateManager.swift  # Window state persistence
│   ├── AttachmentManager.swift   # Attachment handling
│   ├── RecentFilesManager.swift  # Recent files tracking
│   ├── SearchHistoryManager.swift # Search history
│   ├── AlertManager.swift        # Alert dialogs
│   └── KeyboardNavigationModifier.swift # Keyboard handling
│
├── Exporters/
│   ├── ExportEngine.swift        # Main export coordinator
│   ├── CSVExporter.swift         # CSV export implementation
│   ├── JSONExporter.swift        # JSON export implementation
│   └── MarkdownExporter.swift    # Markdown export implementation
│
└── Assets.xcassets/              # Images, colors, app icon
    └── AppIcon.appiconset/
```

### File Responsibilities

| File | Purpose | Lines | Complexity |
|------|---------|-------|------------|
| MboxViewModel.swift | Central state management | ~400 | High |
| Email.swift | Data model | ~100 | Low |
| MboxParser.swift | File parsing | ~200 | Medium |
| ExportEngine.swift | Export coordinator | ~300 | Medium |
| AnalyticsEngine.swift | Statistics | ~400 | Medium |
| PIIRedactor.swift | PII detection | ~250 | Medium |

---

## Design Patterns

### 1. MVVM (Model-View-ViewModel)

**Model**: Pure Swift structs
```swift
struct Email: Identifiable, Codable {
    let id: UUID
    let from: String
    let to: String?
    let subject: String
    let body: String
    // ...
}
```

**ViewModel**: ObservableObject managing state
```swift
class MboxViewModel: ObservableObject {
    @Published var emails: [Email] = []
    @Published var filteredEmails: [Email] = []
    @Published var searchText: String = ""
    // ...
}
```

**View**: SwiftUI views
```swift
struct EmailListView: View {
    @ObservedObject var viewModel: MboxViewModel

    var body: some View {
        List(viewModel.filteredEmails) { email in
            EmailRow(email: email)
        }
    }
}
```

### 2. Repository Pattern

Isolate data access logic:

```swift
class MboxRepository {
    func loadMbox(from url: URL) async throws -> [Email] {
        let parser = MboxParser()
        return try await parser.parse(fileURL: url)
    }
}
```

### 3. Strategy Pattern

For export formats:

```swift
protocol Exporter {
    func export(emails: [Email], to url: URL) throws
}

class CSVExporter: Exporter { ... }
class JSONExporter: Exporter { ... }
class MarkdownExporter: Exporter { ... }
```

### 4. Observer Pattern

SwiftUI's Combine framework:

```swift
viewModel.$searchText
    .sink { searchText in
        // React to search text changes
    }
    .store(in: &cancellables)
```

### 5. Factory Pattern

For creating exporters:

```swift
enum ExporterFactory {
    static func makeExporter(for format: FileFormat) -> Exporter {
        switch format {
        case .csv: return CSVExporter()
        case .json: return JSONExporter()
        case .markdown: return MarkdownExporter()
        case .txt: return TXTExporter()
        }
    }
}
```

---

## Core Components

### MboxParser

**Purpose**: Parse MBOX files efficiently

**Algorithm**:
1. Open file with `FileHandle`
2. Read line by line
3. Detect `From ` separator lines
4. Extract headers until blank line
5. Read body until next `From ` line
6. Create `Email` struct
7. Yield email (async sequence)

**Key Methods**:
```swift
func parse(fileURL: URL) async throws -> [Email] {
    var emails: [Email] = []

    guard let fileHandle = FileHandle(forReadingAtPath: fileURL.path) else {
        throw MboxParserError.fileNotFound
    }

    defer { fileHandle.closeFile() }

    var currentEmail: [String: String] = [:]
    var currentBody = ""
    var inBody = false

    while let line = try? fileHandle.readLine() {
        if line.hasPrefix("From ") {
            // Start of new email
            if !currentEmail.isEmpty {
                emails.append(createEmail(from: currentEmail, body: currentBody))
            }
            currentEmail = [:]
            currentBody = ""
            inBody = false
        } else if !inBody && line.contains(":") {
            // Header line
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                currentEmail[String(parts[0])] = String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        } else if line.isEmpty && !inBody {
            // Blank line = start of body
            inBody = true
        } else if inBody {
            // Body content
            currentBody += line + "\n"
        }
    }

    // Don't forget last email
    if !currentEmail.isEmpty {
        emails.append(createEmail(from: currentEmail, body: currentBody))
    }

    return emails
}
```

**Performance**:
- Memory: O(n) where n = number of emails
- Time: O(m) where m = file size
- Streaming: Reads file once, doesn't load entire file into memory

### MboxViewModel

**Purpose**: Central state management and business logic

**State Properties**:
```swift
class MboxViewModel: ObservableObject {
    // Core data
    @Published var emails: [Email] = []
    @Published var currentFileURL: URL?

    // Search & filters
    @Published var searchText: String = ""
    @Published var senderFilter: String = ""
    @Published var startDate: Date?
    @Published var endDate: Date?

    // UI state
    @Published var selectedEmail: Email?
    @Published var showingExportOptions: Bool = false
    @Published var showingAnalytics: Bool = false
    @Published var isLoading: Bool = false
    @Published var loadingProgress: Double = 0.0

    // Computed properties
    var filteredEmails: [Email] {
        emails.filter { email in
            matchesSearch(email) && matchesFilters(email)
        }
    }
}
```

**Key Methods**:
- `loadMboxFile(url: URL)`: Load MBOX file
- `performSearch()`: Filter emails by search text
- `applyFilters()`: Apply smart filters
- `exportEmails()`: Export to various formats
- `selectNextEmail()` / `selectPreviousEmail()`: Navigation

### ExportEngine

**Purpose**: Coordinate export operations

**Responsibilities**:
1. Validate export options
2. Select appropriate exporter (CSV, JSON, Markdown, TXT)
3. Apply text cleaning if enabled
4. Chunk text if enabled
5. Generate metadata if enabled
6. Create directory structure
7. Export emails
8. Generate INDEX.txt summary
9. Track progress

**Example**:
```swift
class ExportEngine {
    static func export(
        emails: [Email],
        format: FileFormat,
        options: ExportOptions,
        to destination: URL,
        progressHandler: @escaping (Int, Int) -> Void
    ) async throws {
        // Create output directory
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        // Get appropriate exporter
        let exporter = ExporterFactory.makeExporter(for: format)

        // Process emails
        for (index, email) in emails.enumerated() {
            var processedEmail = email

            // Apply text cleaning if enabled
            if options.cleanText {
                processedEmail = TextProcessor.clean(email)
            }

            // Chunk if enabled
            if options.enableChunking {
                let chunks = TextProcessor.chunk(processedEmail.body, size: options.chunkSize)
                for (chunkIndex, chunk) in chunks.enumerated() {
                    try exporter.export(chunk, to: destination)
                }
            } else {
                try exporter.export(processedEmail, to: destination)
            }

            // Report progress
            progressHandler(index + 1, emails.count)
        }

        // Generate INDEX.txt
        try generateIndex(emails: emails, at: destination)
    }
}
```

### AnalyticsEngine

**Purpose**: Calculate email statistics

**Capabilities**:
- Date range analysis
- Top senders/recipients
- Time-based patterns (hour, day, month)
- Attachment statistics
- Thread statistics
- Domain analysis

**Example**:
```swift
struct EmailAnalytics {
    let totalCount: Int
    let totalSize: Int
    let dateRange: DateRange
    let topSenders: [(email: String, count: Int)]
    let emailsByHour: [Int: Int]
    let emailsByDay: [Int: Int]
    let attachmentStats: AttachmentStatistics
    // ...
}

class AnalyticsEngine {
    static func analyze(_ emails: [Email]) -> EmailAnalytics {
        // Calculate all statistics
        return EmailAnalytics(
            totalCount: emails.count,
            totalSize: emails.reduce(0) { $0 + $1.body.count },
            dateRange: calculateDateRange(emails),
            topSenders: calculateTopSenders(emails, limit: 10),
            // ...
        )
    }
}
```

---

## Data Flow

### Loading MBOX File

```
User Action (⌘O)
    ↓
ContentView receives notification
    ↓
MboxViewModel.loadMboxFile(url)
    ↓
MboxParser.parse(fileURL: url) [async]
    ↓
Parser yields Email structs
    ↓
MboxViewModel.emails = parsedEmails [@Published]
    ↓
SwiftUI View updates automatically
    ↓
EmailListView displays emails
```

### Search Flow

```
User types in search field
    ↓
MboxViewModel.searchText changes [@Published]
    ↓
Computed property filteredEmails recalculates
    ↓
SwiftUI View observes change
    ↓
EmailListView re-renders with filtered list
```

### Export Flow

```
User clicks Export (⌘E)
    ↓
ExportOptionsView sheet opens
    ↓
User configures options
    ↓
User clicks "Export..."
    ↓
NSSavePanel chooses destination
    ↓
ExportEngine.export() [async]
    ↓
Progress updates via @Published property
    ↓
ProgressView displays progress
    ↓
Export completes
    ↓
Success alert shown
    ↓
History updated in ExportPresetManager
```

---

## State Management

### Published Properties

Use `@Published` for properties that trigger UI updates:

```swift
class MboxViewModel: ObservableObject {
    @Published var emails: [Email] = []  // ✅ UI depends on this
    @Published var searchText: String = ""  // ✅ UI binds to this

    private var cancellables = Set<AnyCancellable>()  // ❌ Internal state
}
```

### State vs. Derived State

**Stored State** (use @Published):
- Raw email list
- Search text
- Selected email

**Derived State** (use computed properties):
- Filtered emails
- Email count
- Search result count

```swift
// ✅ Good: Derived from stored state
var filteredEmails: [Email] {
    emails.filter { matchesSearch($0) }
}

// ❌ Bad: Duplicates data
@Published var filteredEmails: [Email] = []  // Don't do this!
```

### UserDefaults for Persistence

Store user preferences:

```swift
extension UserDefaults {
    var recentFiles: [URL] {
        get {
            guard let data = data(forKey: "recentFiles"),
                  let urls = try? JSONDecoder().decode([URL].self, from: data) else {
                return []
            }
            return urls
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, forKey: "recentFiles")
            }
        }
    }
}
```

### Combine for Reactive Programming

React to property changes:

```swift
viewModel.$searchText
    .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
    .sink { [weak self] searchText in
        self?.performSearch(searchText)
    }
    .store(in: &cancellables)
```

---

## Performance Considerations

### 1. Lazy Loading

Don't load all email bodies immediately:

```swift
// ✅ Good: Only load what's visible
List(viewModel.filteredEmails) { email in
    EmailRow(email: email)
        .onAppear {
            viewModel.loadEmailBodyIfNeeded(email)
        }
}

// ❌ Bad: Loads everything upfront
let allBodies = emails.map { $0.body }
```

### 2. Background Processing

Use async/await for heavy operations:

```swift
func loadMboxFile(url: URL) {
    Task {
        isLoading = true
        defer { isLoading = false }

        do {
            // Runs on background thread
            let parsedEmails = try await parser.parse(fileURL: url)

            // Update UI on main thread
            await MainActor.run {
                self.emails = parsedEmails
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
```

### 3. Efficient Search

Use efficient string matching:

```swift
// ✅ Good: Native string search
func matchesSearch(_ email: Email) -> Bool {
    let searchLower = searchText.lowercased()
    return email.from.lowercased().contains(searchLower) ||
           email.subject.lowercased().contains(searchLower)
}

// ❌ Bad: Regex for simple search (overkill)
func matchesSearch(_ email: Email) -> Bool {
    let regex = try! NSRegularExpression(pattern: searchText)
    return regex.firstMatch(in: email.body, range: NSRange(location: 0, length: email.body.count)) != nil
}
```

### 4. Memory Management

Avoid retain cycles:

```swift
// ✅ Good: Weak self in closures
Task { [weak self] in
    guard let self = self else { return }
    let emails = try await parser.parse(fileURL: url)
    self.emails = emails
}

// ❌ Bad: Strong self creates cycle
Task {
    let emails = try await parser.parse(fileURL: url)
    self.emails = emails  // Potential leak
}
```

### 5. View Optimization

Use `id()` for efficient list updates:

```swift
// ✅ Good: SwiftUI knows what changed
List(emails, id: \.id) { email in
    EmailRow(email: email)
}

// ❌ Bad: Re-renders everything on change
List(emails.indices, id: \.self) { index in
    EmailRow(email: emails[index])
}
```

---

## Adding New Features

### Step-by-Step Guide

#### 1. Define Feature Requirements

Document:
- User story
- Acceptance criteria
- UI mockups
- Technical approach

#### 2. Create Model (if needed)

Add data structures:

```swift
// Models/NewFeature.swift
struct NewFeatureData: Codable, Identifiable {
    let id: UUID
    let property1: String
    let property2: Int
}
```

#### 3. Add ViewModel Properties

Extend `MboxViewModel`:

```swift
extension MboxViewModel {
    @Published var newFeatureData: [NewFeatureData] = []
    @Published var showingNewFeature: Bool = false

    func loadNewFeatureData() {
        // Implementation
    }
}
```

#### 4. Create View

Add SwiftUI view:

```swift
// Views/NewFeatureView.swift
struct NewFeatureView: View {
    @ObservedObject var viewModel: MboxViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack {
            // UI implementation
        }
    }
}
```

#### 5. Add Menu Command (if needed)

In `MBox_ExplorerApp.swift`:

```swift
CommandGroup(replacing: .appInfo) {
    Button("New Feature") {
        NotificationCenter.default.post(name: .showNewFeature, object: nil)
    }
    .keyboardShortcut("N", modifiers: [.command, .option])
}

// Define notification
extension Notification.Name {
    static let showNewFeature = Notification.Name("showNewFeature")
}
```

#### 6. Handle Notification

In `ContentView.swift`:

```swift
.onReceive(NotificationCenter.default.publisher(for: .showNewFeature)) { _ in
    viewModel.showingNewFeature = true
}
```

#### 7. Add Sheet Presentation

In `ContentView.swift`:

```swift
.sheet(isPresented: $viewModel.showingNewFeature) {
    NewFeatureView(viewModel: viewModel, isPresented: $viewModel.showingNewFeature)
}
```

#### 8. Test Feature

- Manual testing
- Edge cases
- Performance testing
- Accessibility testing

#### 9. Document Feature

Update:
- README.md
- FEATURES.md
- USER_GUIDE.md
- CHANGELOG.md

### Example: Adding Email Templates Feature

```swift
// 1. Model
struct EmailTemplate: Codable, Identifiable {
    let id: UUID
    let name: String
    let subject: String
    let body: String
}

// 2. ViewModel
extension MboxViewModel {
    @Published var templates: [EmailTemplate] = []
    @Published var showingTemplates: Bool = false

    func loadTemplates() {
        if let data = UserDefaults.standard.data(forKey: "emailTemplates"),
           let decoded = try? JSONDecoder().decode([EmailTemplate].self, from: data) {
            templates = decoded
        }
    }

    func saveTemplate(_ template: EmailTemplate) {
        templates.append(template)
        if let encoded = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(encoded, forKey: "emailTemplates")
        }
    }
}

// 3. View
struct EmailTemplatesView: View {
    @ObservedObject var viewModel: MboxViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack {
            Text("Email Templates")
                .font(.title)

            List(viewModel.templates) { template in
                VStack(alignment: .leading) {
                    Text(template.name).font(.headline)
                    Text(template.subject).font(.caption)
                }
            }

            Button("Close") {
                isPresented = false
            }
        }
        .padding()
        .frame(width: 600, height: 400)
    }
}

// 4. Integration in ContentView
.sheet(isPresented: $viewModel.showingTemplates) {
    EmailTemplatesView(viewModel: viewModel, isPresented: $viewModel.showingTemplates)
}
```

---

## Testing

### Unit Testing

Test business logic in isolation:

```swift
// MboxViewModelTests.swift
import XCTest
@testable import MBox_Explorer

class MboxViewModelTests: XCTestCase {
    var viewModel: MboxViewModel!

    override func setUp() {
        super.setUp()
        viewModel = MboxViewModel()
    }

    func testSearchFiltering() {
        // Given
        viewModel.emails = [
            Email(from: "test@example.com", subject: "Test", body: "Body"),
            Email(from: "other@example.com", subject: "Other", body: "Body")
        ]

        // When
        viewModel.searchText = "test"

        // Then
        XCTAssertEqual(viewModel.filteredEmails.count, 1)
        XCTAssertEqual(viewModel.filteredEmails.first?.from, "test@example.com")
    }
}
```

### Integration Testing

Test component interactions:

```swift
func testExportFlow() async throws {
    // Given
    let viewModel = MboxViewModel()
    let testEmails = createTestEmails(count: 10)
    viewModel.emails = testEmails

    // When
    let exportURL = try await ExportEngine.export(
        emails: testEmails,
        format: .csv,
        options: ExportOptions(),
        to: temporaryDirectory
    ) { _, _ in }

    // Then
    XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
    let contents = try String(contentsOf: exportURL)
    XCTAssertTrue(contents.contains("test@example.com"))
}
```

### UI Testing

Test user interactions:

```swift
func testSearchInteraction() throws {
    let app = XCUIApplication()
    app.launch()

    // Given
    app.buttons["Open"].tap()
    // Select test MBOX file

    // When
    let searchField = app.textFields["Search"]
    searchField.tap()
    searchField.typeText("test")

    // Then
    XCTAssertTrue(app.staticTexts["1 of 10 emails"].exists)
}
```

### Performance Testing

Measure performance:

```swift
func testParsingPerformance() {
    let testFile = createLargeMboxFile(emailCount: 10000)

    measure {
        let parser = MboxParser()
        _ = try? await parser.parse(fileURL: testFile)
    }
}
```

---

## Build and Deployment

### Development Build

```bash
# Open in Xcode
open "MBox Explorer.xcodeproj"

# Build from command line
xcodebuild -project "MBox Explorer.xcodeproj" \
           -scheme "MBox Explorer" \
           -configuration Debug \
           build

# Run from command line
xcodebuild -project "MBox Explorer.xcodeproj" \
           -scheme "MBox Explorer" \
           -configuration Debug \
           run
```

### Release Build

```bash
# Clean build folder
xcodebuild -project "MBox Explorer.xcodeproj" \
           -scheme "MBox Explorer" \
           -configuration Release \
           clean

# Build for release
xcodebuild -project "MBox Explorer.xcodeproj" \
           -scheme "MBox Explorer" \
           -configuration Release \
           build

# Archive
xcodebuild -project "MBox Explorer.xcodeproj" \
           -scheme "MBox Explorer" \
           -configuration Release \
           archive \
           -archivePath "MBox Explorer.xcarchive"

# Export
xcodebuild -exportArchive \
           -archivePath "MBox Explorer.xcarchive" \
           -exportPath "Export" \
           -exportOptionsPlist ExportOptions.plist
```

### Code Signing

Ensure proper entitlements:

```xml
<!-- MBox Explorer.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.bookmarks.app-scope</key>
    <true/>
</dict>
</plist>
```

### Distribution

1. **Mac App Store**:
   - Submit via App Store Connect
   - Include screenshots
   - Write app description
   - Set pricing

2. **Direct Download**:
   - Notarize app with Apple
   - Create DMG installer
   - Host on website
   - Provide update mechanism

---

## Contributing Guidelines

### Getting Started

1. Fork the repository
2. Clone your fork
3. Create feature branch
4. Make changes
5. Test thoroughly
6. Submit pull request

### Branch Naming

- `feature/description` - New features
- `bugfix/description` - Bug fixes
- `refactor/description` - Code refactoring
- `docs/description` - Documentation updates

### Commit Messages

Follow conventional commits:

```
feat: Add email templates feature
fix: Resolve search crash on empty query
refactor: Extract export logic to separate class
docs: Update README with new screenshots
test: Add unit tests for MboxParser
perf: Optimize search filtering performance
style: Format code according to Swift style guide
```

### Pull Request Process

1. Update documentation
2. Add tests for new features
3. Ensure all tests pass
4. Update CHANGELOG.md
5. Request review
6. Address feedback
7. Squash commits if requested

### Code Review Checklist

- [ ] Code follows style guide
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] No performance regressions
- [ ] Accessibility considered
- [ ] No memory leaks
- [ ] Error handling appropriate

---

## Code Style

### Swift Style Guide

Follow Apple's Swift API Design Guidelines:

**Naming**:
```swift
// ✅ Good: Clear, descriptive names
func parseEmails(from fileURL: URL) -> [Email]
let filteredEmails: [Email]
var isLoading: Bool

// ❌ Bad: Unclear, abbreviated names
func parse(url: URL) -> [Email]
let filtered: [Email]
var loading: Bool
```

**Functions**:
```swift
// ✅ Good: Verb phrases for functions
func loadMboxFile()
func exportEmails()
func applyFilters()

// ❌ Bad: Noun phrases
func mboxFileLoader()
func emailExporter()
```

**Types**:
```swift
// ✅ Good: Noun phrases for types
struct Email
class MboxViewModel
enum FileFormat

// ❌ Bad: Verb phrases
struct EmailData
class ViewModelForMbox
```

**Formatting**:
```swift
// Use 4 spaces for indentation
func example() {
    if condition {
        doSomething()
    }
}

// Line length: 120 characters max
func longFunctionName(parameter1: String, parameter2: Int, parameter3: Bool) -> String {
    // ...
}

// Vertical spacing
func first() {
    // ...
}

func second() {  // One blank line between functions
    // ...
}
```

### SwiftUI Patterns

**View Structure**:
```swift
struct ExampleView: View {
    // 1. Properties
    @ObservedObject var viewModel: MboxViewModel
    @State private var isExpanded: Bool = false

    // 2. Body
    var body: some View {
        content
    }

    // 3. View builders
    private var content: some View {
        VStack {
            header
            list
            footer
        }
    }

    private var header: some View {
        Text("Header")
    }

    // 4. Helper methods
    private func handleAction() {
        // ...
    }
}
```

### Documentation

Use doc comments for public APIs:

```swift
/// Parses an MBOX file and returns an array of emails.
///
/// This method reads the file asynchronously and returns
/// individual email messages parsed from the MBOX format.
///
/// - Parameter fileURL: The URL of the MBOX file to parse
/// - Returns: An array of `Email` objects
/// - Throws: `MboxParserError` if file cannot be read or parsed
///
/// # Example
/// ```swift
/// let parser = MboxParser()
/// let emails = try await parser.parse(fileURL: url)
/// print("Parsed \(emails.count) emails")
/// ```
func parse(fileURL: URL) async throws -> [Email] {
    // Implementation
}
```

---

## Troubleshooting

### Common Development Issues

#### Issue: Build Fails with "Cannot find X in scope"

**Solution**:
```bash
# Clean build folder
⌘⇧K in Xcode

# Or command line
xcodebuild clean

# Delete DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData/MBox_Explorer-*
```

#### Issue: SwiftUI Preview Crashes

**Solution**:
- Ensure all @ObservedObject have default values
- Check for force unwraps that might fail
- Provide preview data

```swift
struct ExampleView_Previews: PreviewProvider {
    static var previews: some View {
        ExampleView(viewModel: MboxViewModel())  // ✅ Provide real instance
    }
}
```

#### Issue: Memory Leaks

**Solution**:
- Use Instruments to profile
- Check for retain cycles
- Use `[weak self]` in closures
- Properly cancel Combine subscriptions

```swift
// ✅ Good: Stores cancellables
private var cancellables = Set<AnyCancellable>()

viewModel.$property
    .sink { value in ... }
    .store(in: &cancellables)  // Important!
```

#### Issue: Type-Checking Timeout

**Solution**:
- Break up complex expressions
- Extract subviews
- Use explicit types

```swift
// ❌ Bad: Too complex for compiler
.onReceive(...)
.onReceive(...)
.onReceive(...)
// ... 20 more modifiers

// ✅ Good: Split into smaller view modifiers
.modifier(Notifications1())
.modifier(Notifications2())
.modifier(Notifications3())
```

---

## Resources

### Documentation
- [Swift Language Guide](https://docs.swift.org/swift-book/)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui/)
- [Combine Framework](https://developer.apple.com/documentation/combine)
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)

### Tools
- Xcode 15+
- Instruments (profiling)
- SF Symbols (icons)
- Sketch/Figma (design)

### Community
- Swift Forums
- Stack Overflow
- GitHub Discussions

---

## License

Copyright © 2025. All rights reserved.

See LICENSE file for details.

---

**Questions?** Open an issue on GitHub or contact support@mboxexplorer.app

Happy coding! 🚀

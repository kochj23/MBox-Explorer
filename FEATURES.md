# MBox Explorer - Complete Feature Documentation

This document provides comprehensive documentation for all 22 features implemented in MBox Explorer.

## Table of Contents

### Core Features (1-5)
1. [MBOX File Parsing](#1-mbox-file-parsing)
2. [Search & Filter System](#2-search--filter-system)
3. [Thread Detection & Grouping](#3-thread-detection--grouping)
4. [Smart Filters](#4-smart-filters)
5. [Analytics Dashboard](#5-analytics-dashboard)

### Advanced Features (6-13)
6. [Export Engine](#6-export-engine)
7. [Attachment Manager](#7-attachment-manager)
8. [MBOX File Operations](#8-mbox-file-operations)
9. [Duplicate Detection](#9-duplicate-detection)
10. [Syntax Highlighting](#10-syntax-highlighting)
11. [Window State Management](#11-window-state-management)
12. [Keyboard Navigation](#12-keyboard-navigation)
13. [Thread Visualization](#13-thread-visualization)

### Premium Features (14-22)
14. [Search Term Highlighting](#14-search-term-highlighting)
15. [Recent Files & Quick Open](#15-recent-files--quick-open)
16. [Export Presets & History](#16-export-presets--history)
17. [Email Comparison](#17-email-comparison)
18. [Regex Search & Filter](#18-regex-search--filter)
19. [PII Redaction Tool](#19-pii-redaction-tool)
20. [Dark Mode Optimization](#20-dark-mode-optimization)
21. [Drag & Drop](#21-drag--drop)
22. [Email Preview Pane](#22-email-preview-pane)

---

## Core Features (1-5)

### 1. MBOX File Parsing

**Purpose**: Efficiently parse and load MBOX email archive files of any size.

**Key Features**:
- **Streaming Parser**: Reads files incrementally without loading entire file into memory
- **Async Processing**: Non-blocking parsing keeps UI responsive
- **RFC 4155 Compliant**: Properly handles `From ` separator lines
- **Multiple Date Formats**: Parses various email date formats with fallback
- **Progress Tracking**: Real-time progress indicator during parsing
- **Error Handling**: Gracefully handles malformed emails

**Technical Details**:
- Implementation: `MboxParser.swift`
- Uses Swift async/await for concurrent processing
- Supports UTF-8 encoding
- Extracts headers: From, To, Subject, Date, Message-ID, In-Reply-To, References
- Handles attachments (base64-encoded)

**Usage**:
1. File → Open (⌘O)
2. Select MBOX file
3. Wait for parsing progress bar
4. Emails appear in list view

**Performance**:
- ~1000 emails/second on Apple Silicon
- Tested with files up to 5GB
- Memory efficient with lazy loading

---

### 2. Search & Filter System

**Purpose**: Find emails quickly using full-text search with advanced filtering options.

**Key Features**:
- **Real-Time Search**: Instant filtering as you type
- **Multi-Field Search**: Searches sender, subject, and body content
- **Case-Insensitive**: Smart matching regardless of case
- **Search History**: Remembers recent search terms
- **Clear Filters**: One-click filter reset
- **Status Bar**: Shows filtered count vs. total

**Technical Details**:
- Implementation: `MboxViewModel.swift` - searchText property
- Uses SwiftUI `@Published` for reactive updates
- Filters applied with `localizedCaseInsensitiveContains`
- Search history stored in UserDefaults

**Usage**:
1. Type in search field (⌘F)
2. Results filter instantly
3. Click X to clear search
4. Access recent searches via dropdown

**Keyboard Shortcuts**:
- ⌘F: Focus search field
- ⌘⌥C: Clear all filters

---

### 3. Thread Detection & Grouping

**Purpose**: Automatically organize related emails into conversation threads.

**Key Features**:
- **Message-ID Linking**: Uses email headers for accurate threading
- **Subject Normalization**: Groups by subject when Message-ID unavailable
- **Thread Statistics**: Shows email count per thread
- **Chronological Order**: Emails sorted by date within threads
- **Thread Expansion**: Collapse/expand threads in list view

**Technical Details**:
- Implementation: `MboxViewModel.swift` - groupByThreads()
- Algorithm:
  1. Remove `Re:`, `Fwd:`, `FW:` prefixes from subjects
  2. Group by normalized subject
  3. Link via `In-Reply-To` and `References` headers
  4. Sort by date within threads

**Usage**:
1. View → Group by Threads
2. Click thread to see all emails
3. Emails indented to show hierarchy
4. Thread count badge shows message count

---

### 4. Smart Filters

**Purpose**: Advanced filtering with multiple criteria and saved filter sets.

**Key Features**:
- **Sender Filter**: Show emails from specific senders
- **Date Range Filter**: Filter by date range (start/end dates)
- **Attachment Filter**: Show only emails with/without attachments
- **Size Filter**: Filter by email size (KB, MB)
- **Domain Filter**: Filter by sender domain
- **Unread Filter**: Filter by read/unread status
- **Starred Filter**: Filter by starred/flagged emails
- **Saved Filters**: Create and reuse filter combinations

**Technical Details**:
- Implementation: `SmartFilters.swift`, `SmartFiltersView.swift`
- Filter types stored as enum
- Filters applied in sequence (AND logic)
- Saved to UserDefaults for persistence

**Usage**:
1. Click "Smart Filters" in sidebar
2. Add filters using + button
3. Configure filter criteria
4. Save filter set with name
5. Apply saved filters from dropdown

**Available Filters**:
- Sender contains/equals
- Subject contains/equals
- Date before/after/between
- Has attachments
- Size greater/less than
- Domain matches
- Body contains keyword

---

### 5. Analytics Dashboard

**Purpose**: Visualize email patterns and statistics with interactive charts.

**Key Features**:
- **Overview Statistics**:
  - Total email count
  - Date range (first to last email)
  - Total archive size
  - Average email size

- **Sender Analysis**:
  - Top 10 senders with email counts
  - Bar chart visualization
  - Percentage breakdown

- **Time-Based Analysis**:
  - Emails by hour of day (24-hour histogram)
  - Emails by day of week
  - Emails by month (time series)
  - Peak activity times

- **Attachment Statistics**:
  - Total attachment count
  - Total attachment size
  - Emails with attachments percentage
  - Most common file types
  - Average attachments per email

- **Thread Statistics**:
  - Total conversation threads
  - Longest thread (email count)
  - Average thread length
  - Single-email threads count

- **Domain Statistics**:
  - Top 10 email domains
  - Unique domain count
  - Internal vs. external emails
  - Domain distribution chart

**Technical Details**:
- Implementation: `AnalyticsEngine.swift`, `AnalyticsView.swift`
- Charts built with SwiftUI shapes
- Real-time updates when filters applied
- Export analytics report to text file

**Usage**:
1. Click "Analytics" in sidebar
2. Scroll through statistics sections
3. Click "Export Report" to save
4. Charts update when filters applied

**Export Report**:
```
Email Analytics Report
=====================

Overview:
  Total Emails: 1,234
  Date Range: 2020-01-01 - 2024-12-31
  Total Size: 45.6 MB
  Average Email Size: 38 KB

Top 10 Senders:
  1. john@example.com: 234 emails
  2. jane@company.com: 189 emails
  ...
```

---

## Advanced Features (6-13)

### 6. Export Engine

**Purpose**: Export emails to various formats for external processing, archiving, or RAG workflows.

**Key Features**:

**Export Formats**:
- **CSV**: Spreadsheet-compatible format
  - Columns: From, To, Subject, Date, Body, Attachments
  - Quoted values with escape handling

- **JSON**: Structured data format
  - Individual JSON objects per email
  - Nested metadata structure
  - Array of attachments

- **Markdown**: Human-readable format
  - Headers with metadata
  - Formatted body text
  - Code blocks for technical content

- **TXT**: Plain text format
  - Simple key-value pairs
  - Separator lines between emails
  - No special formatting

**Export Options**:
- **Per Email**: One file per message
- **Per Thread**: One file per conversation
- **Both**: Generate individual + thread files
- **Selected Only**: Export filtered/selected emails
- **All Emails**: Export entire archive

**RAG Optimization Features**:
- **Text Cleaning**:
  - Remove email signatures
  - Strip quoted text (> lines)
  - Remove footers and disclaimers
  - Normalize whitespace
  - Remove non-ASCII characters (optional)

- **Text Chunking**:
  - Configurable chunk size (default: 1000 chars)
  - Overlap between chunks (default: 100 chars)
  - Sentence boundary detection
  - Each chunk tagged with index

- **Metadata Generation**:
  - Separate JSON files per email
  - Thread linking information
  - Chunk metadata (index, total)
  - Body length statistics

- **Directory Structure**:
  ```
  Export/
  ├── emails/           # Individual emails
  │   ├── 123456_sender_subject.txt
  │   ├── 123456_sender_subject.json
  │   └── ...
  ├── threads/          # Conversation threads
  │   ├── thread_subject.txt
  │   ├── thread_subject.json
  │   └── ...
  └── INDEX.txt         # Export summary
  ```

**Technical Details**:
- Implementation: `ExportEngine.swift`, `ExportOptionsView.swift`
- Async export with progress tracking
- Memory-efficient streaming for large exports
- Supports date format customization

**Usage**:
1. Select File → Export (⌘E)
2. Choose export format
3. Configure options:
   - Clean text for RAG
   - Include metadata JSON
   - Enable text chunking
   - Chunk size
4. Click "Export..." and choose destination
5. Wait for progress bar
6. View INDEX.txt for summary

**Metadata Schema** (JSON):
```json
{
  "from": "sender@example.com",
  "to": "recipient@example.com",
  "subject": "Email subject",
  "date": "2024-01-01 12:00:00",
  "message_id": "<abc123@example.com>",
  "body_length": 1234,
  "in_reply_to": "<previous@example.com>",
  "references": ["<ref1@example.com>"],
  "chunk_index": 1,
  "total_chunks": 3,
  "has_attachments": true,
  "attachment_count": 2
}
```

---

### 7. Attachment Manager

**Purpose**: View, extract, and manage email attachments efficiently.

**Key Features**:
- **Attachment List**: View all attachments in archive
- **Preview**: Quick Look preview for common file types
- **Extract**: Save individual or bulk attachments
- **Filter**: Show only emails with attachments
- **Statistics**: Total count and size
- **Type Detection**: Identify file types by content-type

**Supported File Types**:
- Images: JPG, PNG, GIF, TIFF, BMP
- Documents: PDF, DOC, DOCX, XLS, XLSX, PPT, PPTX
- Archives: ZIP, TAR, GZ
- Text: TXT, CSV, JSON, XML
- Code: JS, PY, SWIFT, JAVA, etc.

**Technical Details**:
- Implementation: `AttachmentManager.swift`
- Decodes base64-encoded attachments
- Extracts content-type and filename from headers
- Supports batch extraction with progress

**Usage**:
1. Click "Attachments" in sidebar
2. Browse attachment list
3. Click preview icon for Quick Look
4. Select attachments to extract
5. Click "Extract" and choose destination
6. Attachments saved with original filenames

**Attachment View Columns**:
- Filename
- File type/icon
- Size
- Email subject (source)
- Date

---

### 8. MBOX File Operations

**Purpose**: Merge multiple MBOX files or split large archives into smaller files.

**Key Features**:

**Merge Files**:
- Combine multiple MBOX files into one
- Automatically sorts emails by date
- Removes duplicates (by Message-ID)
- Progress tracking
- Validates MBOX format before merging

**Split File Strategies**:
- **By Email Count**: Split into files with N emails each
  - Example: 1000 emails per file

- **By File Size**: Split when reaching size limit
  - Example: 50 MB per file

- **By Date Period**: Group by time period
  - Options: Day, Month, Year
  - Files named by date range

- **By Sender Domain**: Separate by email domain
  - Example: gmail.com, outlook.com, company.com
  - Creates file for "other" domains

**Technical Details**:
- Implementation: `MboxFileOperations.swift`, `MboxOperationsView.swift`
- Async processing with progress callbacks
- Preserves email format and headers
- Output files are valid MBOX format

**Usage - Merge**:
1. Click "Operations" in sidebar
2. Select "Merge Files" tab
3. Click "Select Files" and choose MBOX files
4. Review file list
5. Click "Merge Files"
6. Choose output location
7. Wait for progress bar

**Usage - Split**:
1. Click "Operations" in sidebar
2. Select "Split File" tab
3. Choose split strategy
4. Configure options:
   - Count: Emails per file
   - Size: MB per file
   - Date: Day/Month/Year
   - Sender: Domain list
5. Preview estimated output
6. Click "Split File"
7. Choose output directory
8. Wait for progress bar

**Output Format**:
```
Merged:
  merged.mbox

Split by count (1000/file):
  part_001.mbox (1000 emails)
  part_002.mbox (1000 emails)
  part_003.mbox (456 emails)

Split by date (Month):
  emails_2024-01.mbox
  emails_2024-02.mbox
  emails_2024-03.mbox

Split by domain:
  gmail.mbox
  outlook.mbox
  company.mbox
  other.mbox
```

---

### 9. Duplicate Detection

**Purpose**: Find and manage duplicate emails based on various criteria.

**Key Features**:
- **Detection Methods**:
  - Exact Message-ID match
  - Subject + sender + date match
  - Body content similarity (fuzzy matching)
  - Attachment hash matching

- **Duplicate Groups**: View duplicates grouped together
- **Keep Best**: Automatically select which copy to keep
- **Bulk Actions**: Delete/export duplicates in batch
- **Statistics**: Show duplicate percentage and wasted space

**Technical Details**:
- Implementation: `DuplicateDetector.swift`, `DuplicatesView.swift`
- Uses MD5 hashing for content comparison
- Levenshtein distance for fuzzy subject matching
- Configurable similarity threshold

**Usage**:
1. Click "Duplicates" in sidebar
2. Click "Scan for Duplicates"
3. Wait for scan progress
4. Review duplicate groups
5. For each group:
   - View all copies
   - Select which to keep
   - Mark others for deletion
6. Click "Delete Selected" or "Export"

**Statistics Shown**:
- Total duplicates found
- Space wasted by duplicates
- Duplicate percentage
- Most duplicated senders

---

### 10. Syntax Highlighting

**Purpose**: Automatically detect and highlight code in email bodies.

**Key Features**:
- **Language Detection**: Identifies programming languages in email text
- **Color Schemes**: Multiple themes (Light, Dark, Solarized, etc.)
- **Supported Languages**:
  - JavaScript, TypeScript
  - Python
  - Swift, Objective-C
  - Java, Kotlin
  - C, C++, C#
  - Ruby, PHP
  - HTML, CSS
  - SQL
  - Shell/Bash
  - JSON, XML, YAML

- **Code Block Detection**: Finds code blocks in various formats:
  - Markdown code fences (```language)
  - Indented blocks
  - Common code patterns

**Technical Details**:
- Implementation: `SyntaxHighlighter.swift`
- Uses regex patterns for token detection
- SwiftUI AttributedString for styling
- Cached highlighting for performance

**Usage**:
- Automatic: Code detected and highlighted in email detail view
- Manual: View → Syntax Highlighting → Choose Theme
- Settings: Configure languages and colors

**Example Detection**:
```python
def hello_world():
    print("Hello, World!")
```
↓ Automatically highlighted with:
- Keywords (def, print) in purple
- Strings ("Hello, World!") in red
- Functions (hello_world) in blue

---

### 11. Window State Management

**Purpose**: Save and restore window positions, sizes, and layouts.

**Key Features**:
- **Window Position**: Remember location on screen
- **Window Size**: Restore width and height
- **Sidebar Width**: Maintain sidebar size
- **Column Widths**: Remember list column sizes
- **Split View State**: Restore pane positions
- **Layout Mode**: Remember 2-column vs. 3-column layout
- **Zoom State**: Restore zoomed/maximized state

**Technical Details**:
- Implementation: `WindowStateManager.swift`
- Stored in UserDefaults
- Auto-saves on window close
- Auto-restores on app launch

**Usage**:
- Automatic: Adjust windows, they'll remember positions
- Manual: Window → Save Layout
- Reset: Window → Reset Layout

**Stored State**:
```json
{
  "window_frame": "{{100, 100}, {1200, 800}}",
  "sidebar_width": 250,
  "email_list_width": 400,
  "detail_width": 550,
  "layout_mode": "three_column",
  "is_zoomed": false
}
```

---

### 12. Keyboard Navigation

**Purpose**: Full keyboard control for efficient navigation and operations.

**Key Features**:
- **Arrow Key Navigation**:
  - ↑/↓: Navigate email list
  - ⌘↑/⌘↓: Jump to first/last email
  - ←/→: Collapse/expand threads

- **Email Operations**:
  - Space: Toggle email selection
  - Return: Open email in detail view
  - Delete: Move to trash
  - ⌘A: Select all

- **Search & Filter**:
  - ⌘F: Focus search field
  - ⌘⌥F: Advanced search
  - ⌘⌥C: Clear filters
  - Esc: Clear search

- **View Control**:
  - ⌘⌃S: Toggle sidebar
  - ⌘⌥L: Toggle layout mode
  - ⌘1/2/3: Switch tabs

- **Application**:
  - ⌘O: Open file
  - ⌘⇧O: Quick open recent
  - ⌘E: Export
  - ⌘W: Close window
  - ⌘Q: Quit app

**Technical Details**:
- Implementation: `KeyboardNavigationModifier.swift`
- SwiftUI `onKeyPress` modifiers
- NSEvent handling for system keys
- Customizable key bindings

**Usage**:
- All keyboard shortcuts work immediately
- View shortcuts: View → Keyboard Shortcuts
- Customize: Preferences → Keyboard

**Accessibility**:
- VoiceOver support
- Full keyboard access
- Focus indicators
- Tab navigation

---

### 13. Thread Visualization

**Purpose**: Visual representation of email conversation threads.

**Key Features**:
- **Tree View**: Hierarchical thread display
- **Connection Lines**: Visual lines connecting replies
- **Indentation**: Nested structure shows reply depth
- **Thread Badges**: Show email count per thread
- **Color Coding**: Different colors for different participants
- **Expand/Collapse**: Show/hide thread branches
- **Timeline View**: Chronological thread visualization

**Technical Details**:
- Implementation: `ThreadVisualizationView.swift`
- Uses Canvas for custom drawing
- Calculates thread hierarchy from Message-ID headers
- Animated expand/collapse transitions

**Usage**:
1. View → Thread Visualization
2. Select thread from list
3. View thread tree structure
4. Click nodes to expand/collapse
5. Click email to view details
6. Export thread diagram as image

**Visualization Types**:
- **Tree**: Hierarchical branches
- **Timeline**: Horizontal date-based
- **Radial**: Circular thread layout
- **Flow**: Sankey-style diagram

---

## Premium Features (14-22)

### 14. Search Term Highlighting

**Purpose**: Visual emphasis on search matches within email content.

**Key Features**:
- **Inline Highlighting**: Yellow background on matched text
- **Match Counter**: Shows "Match 3 of 12" above email
- **Jump to Match**: Navigate between matches with ⌘G/⌘⇧G
- **Context Preview**: Shows surrounding text in search results
- **Multi-Term**: Highlights all search terms with different colors
- **Regex Support**: Highlights regex pattern matches

**Technical Details**:
- Implementation: `TextHighlighter.swift`
- Uses SwiftUI AttributedString
- Case-insensitive matching
- Performance optimized for large emails

**Usage**:
1. Enter search term in search field
2. Matches highlighted in yellow in email list
3. Click email to see highlighted content
4. Use ⌘G to jump to next match
5. Use ⌘⇧G to jump to previous match

**Highlight Colors**:
- Primary term: Yellow (#FFFF00)
- Secondary term: Cyan (#00FFFF)
- Tertiary term: Magenta (#FF00FF)
- Regex match: Orange (#FFA500)

---

### 15. Recent Files & Quick Open

**Purpose**: Fast access to recently opened MBOX files with keyboard shortcut.

**Key Features**:
- **Recent Files List**: Up to 20 recent files
- **Quick Open Dialog**: Searchable file list (⌘⇧O)
- **File Metadata**: Shows file size and last opened date
- **Fuzzy Search**: Type partial filename to filter
- **Keyboard Navigation**: Arrow keys to navigate, Return to open
- **Pin Favorites**: Pin frequently used files to top
- **Clear History**: Remove files from recent list

**Technical Details**:
- Implementation: `RecentFilesManager.swift`, `QuickOpenView.swift`
- Stores file URLs in UserDefaults
- Validates file existence before showing
- Security-scoped bookmarks for sandboxed access

**Usage**:
1. Press ⌘⇧O to open Quick Open dialog
2. Type to search recent files
3. Use ↑/↓ to navigate list
4. Press Return to open selected file
5. Press Esc to cancel

**Quick Open Window**:
```
┌─────────────────────────────────────────┐
│ 🔍  Search recent files...              │
├─────────────────────────────────────────┤
│ 📄  work_emails.mbox                    │
│     ~/Documents/Archives • 156 MB       │
│     Opened 2 hours ago                  │
│                                         │
│ 📄  personal_archive.mbox               │
│     ~/Downloads • 45 MB                 │
│     Opened yesterday                    │
│                                         │
│ 📄  project_discussions.mbox            │
│     ~/Desktop • 23 MB                   │
│     Opened 3 days ago                   │
├─────────────────────────────────────────┤
│ ↑↓ Navigate  ↵ Open  ⎋ Close          │
└─────────────────────────────────────────┘
```

**File Operations**:
- Right-click → Show in Finder
- Right-click → Remove from Recents
- Right-click → Pin to Top
- Right-click → Copy Path

---

### 16. Export Presets & History

**Purpose**: Save export configurations and track export history for reuse.

**Key Features**:

**Export Presets**:
- **Save Settings**: Store format, options, and destination
- **Named Presets**: Give presets descriptive names
- **Quick Apply**: One-click to use saved preset
- **Edit Presets**: Modify existing configurations
- **Delete Presets**: Remove unused presets
- **Import/Export**: Share presets between machines

**Preset Configuration Saved**:
- File format (CSV, JSON, Markdown, TXT)
- Include attachments (yes/no)
- Include headers (yes/no)
- Text cleaning (enabled/disabled)
- Chunk size
- Date format
- Output structure

**Export History**:
- **Track All Exports**: Automatic history of all exports
- **Export Details**: Format, email count, file size, date
- **Destination Path**: Link to exported files
- **Statistics**: Total exports, total data exported
- **Preset Used**: Which preset (if any) was used
- **Reopen**: Navigate to export directory

**Statistics Tab**:
- Total exports count
- Total emails exported
- Total data exported (GB)
- Most used format
- Format breakdown pie chart
- Exports over time graph

**Technical Details**:
- Implementation: `ExportPresetManager.swift`, `ExportPresetsView.swift`
- Presets stored as Codable structs
- History persisted in UserDefaults
- File paths validated before showing

**Usage - Presets**:
1. Click "Presets" in export dialog
2. Click "New Preset"
3. Configure export options
4. Name the preset (e.g., "RAG Export")
5. Click "Save"
6. Next time: Select preset from dropdown
7. Click "Use Preset"

**Usage - History**:
1. View → Export Management
2. Switch to "History" tab
3. Browse past exports
4. Click folder icon to show in Finder
5. Click "X" to remove from history
6. Click "Clear History" to remove all

**Usage - Statistics**:
1. View → Export Management
2. Switch to "Statistics" tab
3. View export analytics
4. See format preferences
5. Track total data exported

**Preset File Format** (JSON):
```json
{
  "id": "uuid-1234",
  "name": "RAG Optimized Export",
  "format": "json",
  "includeAttachments": true,
  "includeHeaders": true,
  "cleanText": true,
  "enableChunking": true,
  "chunkSize": 1000,
  "dateFormat": "yyyy-MM-dd HH:mm:ss",
  "createdDate": "2024-01-15T10:30:00Z"
}
```

---

### 17. Email Comparison

**Purpose**: Compare two emails side-by-side with similarity scoring.

**Key Features**:
- **Side-by-Side View**: Two email panes with synchronized scrolling
- **Similarity Score**: Percentage showing how similar emails are
- **Difference Highlighting**:
  - Unique text in red
  - Common text in black
  - Modified text in orange

- **Field-by-Field Comparison**:
  - Subject comparison
  - Sender comparison
  - Body comparison
  - Header comparison
  - Attachment comparison

- **Algorithm**: Levenshtein distance for similarity calculation
- **Visual Indicators**:
  - 🟢 Green: Identical
  - 🟡 Yellow: Very similar (>80%)
  - 🟠 Orange: Similar (>50%)
  - 🔴 Red: Different (<50%)

**Technical Details**:
- Implementation: `EmailComparisonView.swift`
- Uses Levenshtein distance algorithm
- Diff calculation with dynamic programming
- Character-level and word-level comparison modes

**Usage**:
1. Select first email in list
2. Click "Compare" button in toolbar
3. Choose second email from dropdown
4. Comparison view opens
5. Scroll to view differences
6. Toggle "Show Differences Only" to hide common text
7. Export comparison report

**Comparison View Layout**:
```
┌──────────────────────────────────────────────────────────┐
│              Email Comparison View                        │
│              Similarity: 78%                              │
├────────────────────────────┬─────────────────────────────┤
│ Email 1                    │ Email 2                     │
├────────────────────────────┼─────────────────────────────┤
│ From: john@example.com     │ From: jane@example.com      │
│ Subject: Project Update    │ Subject: Project Update     │
│ Date: 2024-01-15           │ Date: 2024-01-16            │
├────────────────────────────┼─────────────────────────────┤
│ The project is             │ The project is              │
│ progressing well.          │ progressing smoothly.       │
│ [unique text in red]       │ [unique text in red]        │
│ [common text in black]     │ [common text in black]      │
└────────────────────────────┴─────────────────────────────┘
```

**Use Cases**:
- Find duplicate emails with slight variations
- Track changes in email threads
- Compare original vs. forwarded messages
- Verify email modifications

---

### 18. Regex Search & Filter

**Purpose**: Advanced pattern matching with regular expressions for precise searches.

**Key Features**:

**Pattern Library** (Built-in patterns):
1. **Email Addresses**: `[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}`
2. **Phone Numbers**: `(\+\d{1,3}[-.]?)?\(?\d{3}\)?[-.]?\d{3}[-.]?\d{4}`
3. **URLs**: `https?://[^\s]+`
4. **IP Addresses**: `\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b`
5. **Credit Cards**: `\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}`
6. **Dates**: `\d{1,2}[-/]\d{1,2}[-/]\d{2,4}`
7. **SSN**: `\d{3}-\d{2}-\d{4}`
8. **Zip Codes**: `\d{5}(-\d{4})?`

**Custom Patterns**:
- Write your own regex patterns
- Save custom patterns for reuse
- Test patterns with live preview
- Match counter shows total matches

**Search Options**:
- Case-sensitive/insensitive
- Multi-line matching
- Dot matches newline
- Search in: Subject, From, Body, or All fields

**Advanced Features**:
- Capture groups extraction
- Match highlighting in results
- Export matches to CSV
- Replace matches (preview before applying)

**Technical Details**:
- Implementation: `RegexSearchView.swift`
- Uses NSRegularExpression
- Real-time pattern validation
- Performance optimized for large result sets

**Usage**:
1. View → Regex Search (⌘⌥R)
2. Choose pattern from library or enter custom
3. Configure search options
4. Click "Search"
5. View results with match count
6. Click result to jump to email
7. Export matches to CSV

**Regex Search Window**:
```
┌─────────────────────────────────────────────────────────┐
│ Regex Pattern: [A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}  │
│                                                         │
│ Pattern Library: [Email Addresses ▼]                  │
│ Search In: [All Fields ▼]                             │
│ □ Case Sensitive  □ Multi-line  ☑ Dot Matches All    │
│                                                         │
│ [Search]  [Save Pattern]  [Clear]                     │
├─────────────────────────────────────────────────────────┤
│ Results: 156 matches in 89 emails                      │
├─────────────────────────────────────────────────────────┤
│ ✉ Project Discussion                                  │
│   From: john@example.com                              │
│   Match: "contact us at support@company.com"          │
│                                                         │
│ ✉ Meeting Notes                                       │
│   From: jane@company.com                              │
│   Match: "send feedback to feedback@company.com"      │
└─────────────────────────────────────────────────────────┘
```

**Saved Patterns**:
- Name: "Find All Emails"
  Pattern: `[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}`

- Name: "Find Phone Numbers"
  Pattern: `\(?\d{3}\)?[-.]?\d{3}[-.]?\d{4}`

- Name: "Find URLs"
  Pattern: `https?://[^\s]+`

---

### 19. PII Redaction Tool

**Purpose**: Automatically detect and redact personally identifiable information.

**Key Features**:

**PII Types Detected**:
1. **Social Security Numbers (SSN)**:
   - Pattern: `XXX-XX-XXXX`
   - Redaction: `[SSN-REDACTED]` or `***-**-1234`

2. **Credit Card Numbers**:
   - Patterns: Visa, Mastercard, Amex, Discover
   - Redaction: `[CARD-REDACTED]` or `**** **** **** 1234`

3. **Phone Numbers**:
   - Patterns: US, International
   - Redaction: `[PHONE-REDACTED]` or `***-***-4567`

4. **Email Addresses**:
   - Full email patterns
   - Redaction: `[EMAIL-REDACTED]` or `j***@example.com`

5. **Physical Addresses**:
   - Street addresses with zip codes
   - Redaction: `[ADDRESS-REDACTED]`

6. **IP Addresses**:
   - IPv4 and IPv6
   - Redaction: `[IP-REDACTED]` or `192.168.***.***`

7. **Dates of Birth**:
   - Various date formats
   - Redaction: `[DOB-REDACTED]`

**Redaction Modes**:
- **Full Redaction**: Replace with `[TYPE-REDACTED]`
- **Partial Redaction**: Show last N characters
  - SSN: `***-**-1234`
  - Credit Card: `**** **** **** 1234`
  - Phone: `***-***-4567`
  - Email: `j***@example.com`

**Three-Tab Interface**:

**1. Configure Tab**:
- Select PII types to detect
- Toggle full/partial redaction
- View redaction examples
- Configure detection sensitivity

**2. Scan Tab**:
- Scan all emails for PII
- Progress indicator
- Results summary:
  - Total emails scanned
  - Emails with PII detected
  - Total PII instances found
- List of affected emails
- Preview redactions before applying

**3. Redact Tab**:
- Review scan results
- Apply redactions
- Export redacted emails
- Generate redaction report

**Technical Details**:
- Implementation: `PIIRedactor.swift`, `RedactionToolView.swift`
- Uses regex patterns for detection
- Luhn algorithm for credit card validation
- Configurable detection rules
- Immutable email structs (creates new instances)

**Usage**:
1. Tools → PII Redaction Tool (⌘⌥P)
2. **Configure**: Select PII types, choose redaction mode
3. **Scan**: Click "Scan Emails", wait for results
4. **Review**: Browse detected PII by email
5. **Redact**: Click "Export Redacted Emails"
6. Choose destination and format
7. Redacted emails saved with PII removed

**Scan Results Display**:
```
┌─────────────────────────────────────────────────────────┐
│ Scan Results                                            │
├─────────────────────────────────────────────────────────┤
│ 📊 Statistics                                          │
│   • 1,234 emails scanned                               │
│   • 89 emails with PII                                 │
│   • 156 PII instances detected                         │
│   • 1,145 clean emails                                 │
├─────────────────────────────────────────────────────────┤
│ ⚠️  Account Information Request                        │
│   From: support@company.com                            │
│   3 detections: 📧 Email, 📱 Phone, 💳 SSN           │
│   [Preview Redactions]                                 │
│                                                         │
│ ⚠️  Customer Contact Details                           │
│   From: sales@company.com                              │
│   2 detections: 📧 Email, 📱 Phone                    │
│   [Preview Redactions]                                 │
└─────────────────────────────────────────────────────────┘
```

**Preview Before/After**:
```
Original:
"My SSN is 123-45-6789 and credit card is 4111-1111-1111-1234.
Call me at (555) 123-4567 or email john@example.com."

Full Redaction:
"My SSN is [SSN-REDACTED] and credit card is [CARD-REDACTED].
Call me at [PHONE-REDACTED] or email [EMAIL-REDACTED]."

Partial Redaction:
"My SSN is ***-**-6789 and credit card is **** **** **** 1234.
Call me at ***-***-4567 or email j***@example.com."
```

**Important Notice** (shown in UI):
> ⚠️ Automated redaction may miss some PII or produce false positives. Always review redacted content before sharing.

**Export Options**:
- Export format: TXT, JSON, CSV
- Include redaction report
- Generate redaction log
- Metadata with redaction statistics

---

### 20. Dark Mode Optimization

**Purpose**: Beautiful themes optimized for different lighting conditions and preferences.

**Key Features**:

**8 Built-in Themes**:

1. **System** (Default):
   - Follows macOS appearance setting
   - Automatically switches with system
   - Respects user's dark mode schedule

2. **Light**:
   - Clean white backgrounds
   - Dark text for readability
   - Blue accents
   - Best for daylight use

3. **Dark**:
   - Dark gray backgrounds (#1E1E1E)
   - Light text (#FFFFFF)
   - Blue accents
   - Standard dark mode

4. **High Contrast**:
   - Pure black backgrounds (#000000)
   - Pure white text (#FFFFFF)
   - High contrast accents
   - WCAG AAA compliant
   - Best for accessibility

5. **AMOLED**:
   - True black backgrounds (#000000)
   - Reduces power on OLED screens
   - Vibrant accent colors
   - Best for MacBook Pro users

6. **Solarized Dark**:
   - Base03 background (#002b36)
   - Base0 text (#839496)
   - Warm color palette
   - Easy on eyes for long sessions

7. **Solarized Light**:
   - Base3 background (#fdf6e3)
   - Base00 text (#657b83)
   - Warm color palette
   - Reduced eye strain

8. **Nord**:
   - Polar night backgrounds (#2E3440)
   - Snow storm text (#D8DEE9)
   - Frost blue accents
   - Arctic-inspired palette

**Custom Theme**:
- Create your own color scheme
- Customize all UI colors:
  - Background colors
  - Text colors
  - Accent colors
  - Syntax highlighting colors
- Save custom themes
- Export/import themes

**Theme Customization Options**:
- **Background Colors**:
  - Primary background
  - Secondary background
  - Sidebar background
  - Card background

- **Text Colors**:
  - Primary text
  - Secondary text
  - Accent text
  - Link text

- **UI Colors**:
  - Accent color
  - Success color (green)
  - Warning color (yellow)
  - Error color (red)
  - Info color (blue)

- **Syntax Colors**:
  - Keywords
  - Strings
  - Comments
  - Functions
  - Variables

**Technical Details**:
- Implementation: `ThemeManager.swift`, `ThemeSettingsView.swift`
- Uses NSAppearance for system integration
- SwiftUI environment values for colors
- Stored in UserDefaults
- Live preview when changing themes

**Usage**:
1. Tools → Theme Settings (⌘⌥T)
2. Choose theme from list
3. See live preview
4. For custom theme:
   - Select "Custom"
   - Click color wells to change colors
   - Name and save custom theme
5. Click "Apply"

**Theme Settings Window**:
```
┌─────────────────────────────────────────────────────────┐
│ Theme Settings                                          │
├─────────────────────────────────────────────────────────┤
│ ○ System    ○ Light     ○ Dark                         │
│ ○ High Contrast    ○ AMOLED                            │
│ ○ Solarized Dark   ○ Solarized Light                   │
│ ○ Nord             ● Custom                             │
├─────────────────────────────────────────────────────────┤
│ Custom Theme Editor                                     │
│                                                         │
│ Background:   [███████]  Primary Background            │
│ Text:         [███████]  Primary Text                  │
│ Accent:       [███████]  Accent Color                  │
│ Success:      [███████]  Success Color                 │
│ Warning:      [███████]  Warning Color                 │
│ Error:        [███████]  Error Color                   │
│                                                         │
│ [Preview] [Save Theme] [Export Theme]                  │
└─────────────────────────────────────────────────────────┘
```

**Accessibility**:
- All themes meet WCAG AA standards
- High Contrast theme meets WCAG AAA
- Adjustable for color blindness
- Tested with VoiceOver

---

### 21. Drag & Drop

**Purpose**: Intuitive file handling with drag and drop support.

**Key Features**:

**Drop to Open**:
- Drag MBOX file from Finder
- Drop onto app window
- File opens automatically
- Multiple files open in new windows
- Visual feedback during drag

**Drag to Export**:
- Drag email from list
- Drop onto desktop/folder
- Saves as TXT file
- Includes metadata in filename
- Multiple selection support

**Drag Operations**:
1. **Drag MBOX File** → App Window
   - Opens MBOX file
   - Replaces current file
   - Shows confirmation if file already open

2. **Drag Email** → Finder
   - Exports individual email as TXT
   - Filename: `[Date] [Sender] [Subject].txt`
   - Includes email headers and body

3. **Drag Multiple Emails** → Finder
   - Creates folder with all emails
   - Each email as separate file
   - Includes INDEX.txt with list

4. **Drag Attachment** → Finder
   - Extracts attachment file
   - Original filename preserved
   - Decodes base64 automatically

**Visual Feedback**:
- Blue border when file hovers over drop zone
- "Drop to Open" tooltip
- Copy cursor icon
- Animated drop effect

**Technical Details**:
- Implementation: `DragDropModifier.swift`
- SwiftUI `.onDrop` modifier
- NSItemProvider for file handling
- UTType validation for MBOX files
- Background extraction for large files

**Usage - Drop to Open**:
1. Locate MBOX file in Finder
2. Drag file over MBox Explorer window
3. Window highlights with blue border
4. Release mouse to open file

**Usage - Drag to Export**:
1. Select email(s) in list
2. Click and hold on selection
3. Drag outside app window
4. Drop onto Desktop or folder
5. File(s) created automatically

**Supported File Types**:
- Drop: `.mbox`, `.mbx`, `.txt` (MBOX format)
- Drag out: `.txt`, `.eml`, `.json`

**Settings**:
- Preferences → Drag & Drop
- □ Confirm before opening dropped files
- □ Auto-export as EML format
- □ Include attachments when dragging
- □ Create folder for multiple emails

---

### 22. Email Preview Pane

**Purpose**: Optional 3-column layout with adjustable email preview.

**Key Features**:

**Layout Modes**:

1. **Standard (2-Column)**:
   ```
   ┌─────────┬──────────────────────┐
   │ Sidebar │    Email List        │
   │         │                      │
   │         │  [Click to view →]   │
   │         │                      │
   └─────────┴──────────────────────┘
   ```

2. **Three Column**:
   ```
   ┌─────────┬───────────┬──────────┐
   │ Sidebar │ Email List│ Preview  │
   │         │           │          │
   │         │ Selected  │ Subject  │
   │         │ ✓ Email   │ From     │
   │         │           │ Body...  │
   └─────────┴───────────┴──────────┘
   ```

**Preview Pane Features**:
- **Auto-Preview**: Shows email immediately on selection
- **Resizable**: Drag divider to adjust width
- **Collapsible**: Double-click divider to collapse
- **Keyboard Nav**: Space to toggle preview
- **Quick Actions**: Toolbar with common operations

**Preview Pane Sections**:
1. **Header**:
   - From (with avatar)
   - To
   - Subject
   - Date
   - Labels/Tags

2. **Body**:
   - Formatted email content
   - Syntax highlighting
   - Inline images
   - Quoted text collapsed by default

3. **Attachments**:
   - Attachment cards
   - Quick Look preview
   - Download buttons

4. **Actions**:
   - Reply/Forward (opens default mail app)
   - Export
   - Print
   - Share

**Customization**:
- Minimum/maximum pane widths
- Default pane sizes
- Show/hide sections
- Font size adjustment

**Technical Details**:
- Implementation: `ThreeColumnLayoutView.swift`
- SwiftUI NavigationSplitView
- Geometry Reader for sizing
- @State for pane widths
- Persisted in WindowStateManager

**Usage**:
1. View → Toggle Layout Mode (⌘⌥L)
2. Or click layout icon in toolbar
3. Adjust pane widths by dragging dividers
4. Select email to see preview
5. Use keyboard shortcuts:
   - Space: Toggle preview
   - ⌘]: Next email
   - ⌘[: Previous email

**Preview Pane Toolbar**:
```
┌────────────────────────────────────────┐
│ ← → 📧 🖨️ 📤 ⭐ 🗑️ •••               │
├────────────────────────────────────────┤
│ From: john@example.com                 │
│ To: jane@company.com                   │
│ Subject: Project Update                │
│ Date: Jan 15, 2024 10:30 AM            │
├────────────────────────────────────────┤
│ Email body content here...             │
│                                        │
│ The project is progressing well.       │
│ Here are the latest updates...         │
├────────────────────────────────────────┤
│ 📎 Attachments (2)                     │
│ □ document.pdf (1.2 MB)                │
│ □ screenshot.png (234 KB)              │
└────────────────────────────────────────┘
```

**Keyboard Shortcuts in Preview**:
- ⌘P: Print email
- ⌘E: Export email
- ⌘D: Delete email
- ⌘T: Add to tags
- ⌘I: View email info
- ⌘K: Copy email link

**Settings**:
- Preferences → Layout
- Default layout mode
- Preview pane width (%)
- Auto-collapse on narrow windows
- Show preview toolbar
- Font size: [Small] [Medium] [Large]

---

## Feature Summary Matrix

| Feature | Category | Keyboard Shortcut | File Location |
|---------|----------|-------------------|---------------|
| MBOX Parsing | Core | ⌘O | MboxParser.swift |
| Search & Filter | Core | ⌘F | MboxViewModel.swift |
| Thread Detection | Core | - | MboxViewModel.swift |
| Smart Filters | Core | - | SmartFilters.swift |
| Analytics | Core | - | AnalyticsEngine.swift |
| Export Engine | Advanced | ⌘E | ExportEngine.swift |
| Attachments | Advanced | - | AttachmentManager.swift |
| File Operations | Advanced | - | MboxFileOperations.swift |
| Duplicates | Advanced | - | DuplicateDetector.swift |
| Syntax Highlighting | Advanced | - | SyntaxHighlighter.swift |
| Window State | Advanced | - | WindowStateManager.swift |
| Keyboard Nav | Advanced | Various | KeyboardNavigationModifier.swift |
| Thread Viz | Advanced | - | ThreadVisualizationView.swift |
| Highlighting | Premium | ⌘G | TextHighlighter.swift |
| Recent Files | Premium | ⌘⇧O | RecentFilesManager.swift |
| Presets | Premium | - | ExportPresetManager.swift |
| Comparison | Premium | - | EmailComparisonView.swift |
| Regex Search | Premium | ⌘⌥R | RegexSearchView.swift |
| PII Redaction | Premium | ⌘⌥P | PIIRedactor.swift |
| Themes | Premium | ⌘⌥T | ThemeManager.swift |
| Drag & Drop | Premium | - | DragDropModifier.swift |
| Preview Pane | Premium | ⌘⌥L | ThreeColumnLayoutView.swift |

---

## Integration Examples

### Example 1: RAG Workflow

1. Open MBOX file (Feature #1)
2. Use Smart Filters to select relevant emails (Feature #4)
3. Export with RAG optimization (Feature #6):
   - Format: JSON
   - Clean text: Enabled
   - Chunking: 1000 chars
   - Metadata: Enabled
4. Save as preset for reuse (Feature #16)
5. Import to vector database

### Example 2: Compliance Review

1. Open MBOX file (Feature #1)
2. Use Regex Search to find SSNs/credit cards (Feature #18)
3. Use PII Redaction Tool to redact sensitive info (Feature #19)
4. Export redacted emails (Feature #6)
5. Track export in history (Feature #16)

### Example 3: Email Investigation

1. Open MBOX file (Feature #1)
2. Use Thread Detection to group conversations (Feature #3)
3. Use Email Comparison to find similarities (Feature #17)
4. Use Duplicate Detection to find exact matches (Feature #9)
5. Use Analytics to identify patterns (Feature #5)
6. Export findings (Feature #6)

### Example 4: Archive Management

1. Open multiple MBOX files (Feature #1)
2. Merge into single archive (Feature #8)
3. Use Duplicate Detection to clean up (Feature #9)
4. Split by date ranges for organization (Feature #8)
5. Save window layout for future use (Feature #11)

---

## Performance Considerations

### Large File Handling

All features are optimized for large MBOX files:
- **Streaming parsing**: No memory spikes
- **Lazy loading**: Only visible emails loaded
- **Background processing**: UI remains responsive
- **Progress indicators**: Clear feedback on long operations
- **Cancellable operations**: Stop long-running tasks

### Memory Usage

Typical memory footprint:
- Base app: ~50 MB
- Per 1,000 emails: ~1 MB
- Large file (100K emails): ~150 MB
- With all features: ~200 MB

### Search Performance

- Full-text search: <100ms for 10K emails
- Regex search: <500ms for 10K emails
- Smart filters: Real-time (instant)
- Thread grouping: <1s for 10K emails

---

## Troubleshooting

### Common Issues

**Feature not working**:
- Check if MBOX file is loaded
- Verify feature is enabled in Preferences
- Check keyboard shortcut conflicts
- Restart application

**Export fails**:
- Check disk space
- Verify write permissions
- Try smaller batch
- Check export log

**Search not finding results**:
- Check search syntax
- Verify field selection
- Clear filters
- Rebuild search index

**Theme not applying**:
- Check system dark mode setting
- Restart application
- Reset to default theme
- Check for conflicting extensions

---

## Future Enhancements

Potential improvements for each feature category:

**Core**:
- Multi-MBOX support
- Incremental parsing
- Custom thread algorithms
- Advanced search operators

**Advanced**:
- Cloud export destinations
- Plugin architecture
- Custom export templates
- Machine learning categorization

**Premium**:
- Collaborative features
- Email scheduling
- Advanced PII detection
- Theme marketplace

---

For more information, see:
- [USER_GUIDE.md](USER_GUIDE.md) - Step-by-step usage instructions
- [DEVELOPER.md](DEVELOPER.md) - Architecture and development
- [README.md](README.md) - Project overview

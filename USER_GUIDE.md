# MBox Explorer - User Guide

Welcome to MBox Explorer! This comprehensive guide will help you get the most out of all features.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Basic Operations](#basic-operations)
3. [Search and Filter](#search-and-filter)
4. [Analytics](#analytics)
5. [Export Options](#export-options)
6. [Advanced Features](#advanced-features)
7. [Keyboard Shortcuts](#keyboard-shortcuts)
8. [Tips and Tricks](#tips-and-tricks)
9. [Troubleshooting](#troubleshooting)
10. [FAQ](#faq)

---

## Getting Started

### First Launch

1. **Open MBox Explorer** from your Applications folder
2. You'll see the main window with three sections:
   - Left: Sidebar with navigation
   - Center: Email list (empty initially)
   - Right: Detail pane

### Opening Your First MBOX File

**Method 1: Menu**
1. Click **File → Open** (or press ⌘O)
2. Navigate to your MBOX file
3. Click "Open"
4. Wait for the progress bar to complete

**Method 2: Drag and Drop**
1. Locate your MBOX file in Finder
2. Drag it onto the MBox Explorer window
3. Release to open

**Method 3: Quick Open Recent**
1. Press ⌘⇧O
2. Type to search recent files
3. Press Return to open

### Understanding the Interface

```
┌─────────────────────────────────────────────────────────┐
│  File  Edit  View  Tools  Window  Help                  │
├──────────┬────────────────────┬─────────────────────────┤
│ Sidebar  │   Email List       │    Detail Pane          │
│          │                    │                          │
│ 📧 Inbox │ ☑ Email 1          │ Subject: Welcome        │
│ 📊 Analytics│ ☐ Email 2       │ From: sender@email.com │
│ 📎 Attachments│ ☐ Email 3     │ Date: Jan 15, 2024     │
│ 🔄 Duplicates│                │                          │
│ ⚙️  Operations│               │ Email body content...   │
│          │                    │                          │
│ [Export] │   [1,234 emails]   │                          │
└──────────┴────────────────────┴─────────────────────────┘
```

### Where to Find MBOX Files

Common locations:
- **Mail.app**: `~/Library/Mail/V*/MailData/`
- **Thunderbird**: `~/Library/Thunderbird/Profiles/*/Mail/`
- **Gmail Export**: Download from Google Takeout
- **Backup Archives**: Check Time Machine backups

---

## Basic Operations

### Browsing Emails

**Navigate the List**
- Click any email to select it
- Use ↑/↓ arrow keys to move up/down
- Press ⌘↑ to jump to first email
- Press ⌘↓ to jump to last email

**Read Email Content**
1. Select an email from the list
2. View details in the right pane
3. Scroll to read long emails
4. Click attachments to preview

**Select Multiple Emails**
- Hold ⌘ and click emails for non-contiguous selection
- Hold ⇧ and click for range selection
- Press ⌘A to select all

### Thread Grouping

**Enable Thread View**
1. Click "Group by Threads" in sidebar
2. Emails with same subject grouped together
3. Click thread to expand/collapse
4. Thread count shows in badge

**Thread Features**
- Emails indented by reply level
- Chronological order within threads
- Thread statistics shown

### Viewing Attachments

**In Email Detail**
1. Scroll to "Attachments" section
2. See list of attached files
3. Click file icon for Quick Look preview
4. Click "Save" to extract attachment

**Attachment Manager**
1. Click "Attachments" in sidebar
2. Browse all attachments from all emails
3. Filter by type
4. Bulk extract multiple attachments

---

## Search and Filter

### Basic Search

**Quick Search**
1. Click search field (or press ⌘F)
2. Type your search term
3. Results filter instantly
4. Clear with X button or Esc

**Search Tips**
- Searches sender, subject, and body
- Case-insensitive by default
- Partial matches included
- No wildcards needed

**Example Searches**
```
"john"          → Finds emails from/about John
"project alpha" → Finds emails containing both words
"@company.com"  → Finds all emails from company.com domain
```

### Smart Filters

**Create a Filter**
1. Click "Smart Filters" in sidebar
2. Click "+" button
3. Choose filter type:
   - Sender
   - Date Range
   - Has Attachments
   - Size
   - Domain
   - Read/Unread
   - Starred
4. Configure filter criteria
5. Add more filters if needed

**Save Filter Set**
1. Configure your filters
2. Click "Save Filter Set"
3. Name it (e.g., "Work Emails - Last Month")
4. Click "Save"

**Apply Saved Filter**
1. Click dropdown in Smart Filters
2. Select saved filter
3. Filters apply automatically

**Example Filter Combinations**
```
Work Emails:
- Sender contains "@company.com"
- Date: Last 30 days
- Has attachments: Yes

Large Files:
- Size > 5 MB
- Has attachments: Yes

Important Threads:
- Starred: Yes
- Date: This year
```

### Advanced Search (Regex)

**Open Regex Search**
1. View → Regex Search (⌘⌥R)
2. Or click "Regex" button in toolbar

**Use Built-in Patterns**
1. Click "Pattern Library" dropdown
2. Select pattern:
   - Email addresses
   - Phone numbers
   - URLs
   - IP addresses
   - Credit cards
   - Dates
   - SSN
   - Zip codes
3. Click "Search"

**Create Custom Pattern**
1. Enter regex in pattern field
2. Configure options:
   - ☑ Case sensitive
   - ☑ Multi-line
   - ☑ Dot matches all
3. Select search location (Subject/From/Body/All)
4. Click "Search"
5. Optional: Click "Save Pattern" to reuse

**Example Patterns**
```
Find all URLs:
https?://[^\s]+

Find dates (MM/DD/YYYY):
\d{2}/\d{2}/\d{4}

Find email addresses:
[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}

Find phone numbers:
\(?\d{3}\)?[-.]?\d{3}[-.]?\d{4}
```

---

## Analytics

### View Analytics Dashboard

**Open Analytics**
1. Click "Analytics" in sidebar
2. Dashboard displays automatically
3. Scroll to view all statistics

### Understanding Statistics

**Overview Section**
- **Total Emails**: Count of all emails in archive
- **Date Range**: From first to last email
- **Total Size**: Combined size of all emails
- **Average Size**: Mean email size

**Top Senders**
- Bar chart of top 10 senders
- Email count for each sender
- Percentage of total emails
- Click sender to filter

**Time Analysis**
- **By Hour**: 24-hour histogram showing email activity
- **By Day**: Monday-Sunday distribution
- **By Month**: Timeline showing volume over time
- Identify peak communication times

**Attachment Statistics**
- Total attachment count
- Combined attachment size
- Percentage of emails with attachments
- Most common file types
- Average attachments per email

**Thread Statistics**
- Total conversation threads
- Longest thread (email count)
- Average thread length
- Single-email threads

**Domain Analysis**
- Top 10 email domains
- Number of unique domains
- Internal vs. external emails
- Domain distribution

### Export Analytics Report

1. Scroll to bottom of Analytics view
2. Click "Export Report"
3. Choose location
4. Text file generated with all statistics

**Example Report**
```
Email Analytics Report
=====================

Overview:
  Total Emails: 1,234
  Date Range: 2020-01-01 - 2024-12-31
  Total Size: 45.6 MB
  Average Email Size: 38 KB

Top 10 Senders:
  1. john@example.com: 234 emails (19%)
  2. jane@company.com: 189 emails (15%)
  ...

Email Activity by Hour:
  08:00 | ██████████ 45
  09:00 | ████████████████ 78
  10:00 | ██████████████ 67
  ...
```

---

## Export Options

### Basic Export

**Start Export**
1. File → Export (⌘E)
2. Or click "Export" button in toolbar
3. Export options sheet opens

**Choose Format**
Select from 4 formats:
- **CSV**: Spreadsheet-compatible, good for analysis
- **JSON**: Structured data, good for programming
- **Markdown**: Human-readable, good for documentation
- **TXT**: Plain text, universal compatibility

**Choose Export Mode**
- **Per Email**: One file per message (good for search)
- **Per Thread**: One file per conversation (good for context)
- **Both**: Generate both formats

**Basic Options**
- ☑ Include attachments
- ☑ Include headers
- ☑ Selected emails only (if you have a selection)

**Export**
1. Click "Export..."
2. Choose destination folder
3. Name your export
4. Click "Export"
5. Wait for progress bar
6. Success message shown

### RAG-Optimized Export

For AI/LLM integration:

**Configure RAG Options**
1. Open Export Options (⌘E)
2. Check these options:
   - ☑ **Clean Text for RAG**
     - Removes signatures
     - Strips quoted text
     - Eliminates footers
     - Normalizes whitespace

   - ☑ **Include Metadata JSON**
     - Separate .json file per email
     - Contains structured metadata
     - Includes thread links

   - ☑ **Enable Text Chunking**
     - Splits long emails
     - Configurable chunk size (default: 1000 chars)
     - 100-char overlap for context
     - Each chunk numbered

   - ☑ **Include Thread Links**
     - Preserves conversation context
     - Message-ID references
     - Thread hierarchy

**Set Chunk Size**
1. Adjust slider: 500 - 2000 characters
2. 1000 chars recommended for most LLMs
3. Larger for long-context models
4. Smaller for embedding models

**Export**
1. Click "Export..."
2. Choose destination
3. Select format (JSON recommended for RAG)
4. Export creates structure:
```
Export/
├── emails/           # Individual emails
│   ├── 123_sender_subject.txt
│   ├── 123_sender_subject.json
│   └── ...
├── threads/          # Conversation threads
│   ├── thread_subject.txt
│   ├── thread_subject.json
│   └── ...
└── INDEX.txt         # Summary
```

### Using Export Presets

**Save a Preset**
1. Configure export options
2. Click "Save as Preset"
3. Name it (e.g., "RAG Export for LLM")
4. Click "Save"

**Use a Preset**
1. Open Export Options
2. Click "Presets" dropdown
3. Select saved preset
4. Settings apply automatically
5. Click "Export..."

**Manage Presets**
1. View → Export Management
2. Switch to "Presets" tab
3. View all saved presets
4. Click "Edit" to modify
5. Click "Delete" to remove
6. Click "Use" to apply

### View Export History

**See Past Exports**
1. View → Export Management
2. Switch to "History" tab
3. Browse past exports
4. See details:
   - Format used
   - Email count
   - File size
   - Export date
   - Destination path
   - Preset used (if any)

**Actions on History**
- Click folder icon → Show in Finder
- Click X → Remove from history
- Click "Clear History" → Remove all

### Export Statistics

**View Stats**
1. View → Export Management
2. Switch to "Statistics" tab
3. See analytics:
   - Total exports count
   - Total emails exported
   - Total data exported (GB)
   - Most used format
   - Format breakdown chart

---

## Advanced Features

### Email Comparison

**Compare Two Emails**
1. Select first email in list
2. Click "Compare" button
3. Choose second email from dropdown
4. Comparison window opens

**Understanding Comparison**
- **Similarity Score**: Percentage (0-100%)
- **Color Coding**:
  - 🟢 Green: Identical
  - 🟡 Yellow: Very similar (>80%)
  - 🟠 Orange: Similar (>50%)
  - 🔴 Red: Different (<50%)

**Comparison View**
```
┌──────────────────┬──────────────────┐
│ Email 1          │ Email 2          │
├──────────────────┼──────────────────┤
│ Same text        │ Same text        │
│ [Unique text]    │                  │
│                  │ [Unique text]    │
│ Modified text    │ Changed text     │
└──────────────────┴──────────────────┘
```

**Options**
- ☑ Show differences only
- ☑ Highlight changes
- Click "Export Comparison" to save report

**Use Cases**
- Find duplicate emails with variations
- Track email modifications
- Compare original vs. forwarded
- Verify email authenticity

### PII Redaction

**Open Redaction Tool**
1. Tools → PII Redaction Tool (⌘⌥P)
2. Three-tab interface opens

**Tab 1: Configure**
1. Select PII types to detect:
   - ☑ Social Security Numbers
   - ☑ Credit Card Numbers
   - ☑ Phone Numbers
   - ☑ Email Addresses
   - ☑ Physical Addresses
   - ☑ IP Addresses
   - ☑ Dates of Birth

2. Choose redaction mode:
   - **Full**: `[SSN-REDACTED]`
   - **Partial**: `***-**-1234`

3. Review examples

**Tab 2: Scan**
1. Click "Scan Emails"
2. Wait for scan progress
3. Review results:
   - Emails scanned
   - PII detected
   - Clean emails
4. Click email to preview redactions

**Tab 3: Redact**
1. Review summary
2. Click "Export Redacted Emails"
3. Choose format and destination
4. Redacted emails saved

**Example Redaction**
```
Original:
"Contact me at (555) 123-4567 or john@example.com.
My SSN is 123-45-6789."

Full Redaction:
"Contact me at [PHONE-REDACTED] or [EMAIL-REDACTED].
My SSN is [SSN-REDACTED]."

Partial Redaction:
"Contact me at ***-***-4567 or j***@example.com.
My SSN is ***-**-6789."
```

**Important**: Always review redacted content before sharing!

### File Operations

**Merge Multiple MBOX Files**
1. Click "Operations" in sidebar
2. Select "Merge Files" tab
3. Click "Select Files"
4. Choose 2 or more MBOX files
5. Review file list
6. Click "Merge Files"
7. Choose output location
8. Wait for progress
9. Merged file created

**Split Large MBOX File**
1. Load MBOX file first
2. Click "Operations" in sidebar
3. Select "Split File" tab
4. Choose strategy:

   **By Email Count**:
   - Set emails per file (e.g., 1000)
   - Preview: "Will create 3 files"

   **By File Size**:
   - Set max size in MB (e.g., 50 MB)
   - Preview: "Will create 4 files"

   **By Date Period**:
   - Choose Day/Month/Year
   - Groups emails by date

   **By Sender Domain**:
   - Enter domains (comma-separated)
   - Example: "gmail.com, outlook.com"
   - Creates file per domain + "other"

5. Click "Split File"
6. Choose output directory
7. Wait for progress
8. Split files created

### Duplicate Detection

**Find Duplicates**
1. Click "Duplicates" in sidebar
2. Click "Scan for Duplicates"
3. Wait for scan progress
4. Review duplicate groups

**Duplicate Detection Methods**
- Message-ID matching (exact)
- Subject + sender + date matching
- Body similarity (fuzzy)
- Attachment hash matching

**Manage Duplicates**
1. Browse duplicate groups
2. For each group:
   - View all copies
   - Select which to keep (checkmark)
   - Mark others for deletion
3. Click "Delete Selected"
4. Or click "Export" to save before deleting

**Statistics Shown**
- Total duplicates found
- Space wasted
- Duplicate percentage
- Most duplicated senders

### Theme Customization

**Change Theme**
1. Tools → Theme Settings (⌘⌥T)
2. Choose from 8 themes:
   - System (follows macOS)
   - Light
   - Dark
   - High Contrast
   - AMOLED
   - Solarized Dark
   - Solarized Light
   - Nord
3. Click "Apply"

**Create Custom Theme**
1. Select "Custom" theme
2. Click color wells to change colors:
   - Background colors
   - Text colors
   - Accent colors
   - Syntax colors
3. See live preview
4. Click "Save Theme"
5. Name your theme
6. Click "Save"

**Export/Import Themes**
1. Click "Export Theme"
2. Save .json file
3. Share with others
4. Import: Click "Import Theme"

### Layout Modes

**Toggle Layout**
1. View → Toggle Layout Mode (⌘⌥L)
2. Or click layout icon in toolbar

**Standard Layout (2-Column)**
```
┌──────────┬─────────────────────┐
│          │                     │
│ Sidebar  │    Email List       │
│          │                     │
│          │  Click to view →    │
│          │                     │
└──────────┴─────────────────────┘
```

**Three-Column Layout**
```
┌──────────┬──────────┬──────────┐
│          │          │          │
│ Sidebar  │ Emails   │ Preview  │
│          │          │          │
│          │ Selected │ Auto-    │
│          │ ✓        │ displays │
│          │          │          │
└──────────┴──────────┴──────────┘
```

**Adjust Pane Sizes**
- Drag dividers to resize
- Double-click divider to collapse/expand
- Sizes remembered automatically

---

## Keyboard Shortcuts

### Essential Shortcuts

| Action | Shortcut |
|--------|----------|
| **File Operations** |
| Open File | ⌘O |
| Quick Open Recent | ⌘⇧O |
| Close Window | ⌘W |
| Quit | ⌘Q |
| **Search & Filter** |
| Search | ⌘F |
| Regex Search | ⌘⌥R |
| Clear Filters | ⌘⌥C |
| Clear Search | Esc |
| **Navigation** |
| Next Email | ⌘↓ or ↓ |
| Previous Email | ⌘↑ or ↑ |
| First Email | ⌘↑ (at top) |
| Last Email | ⌘↓ (at bottom) |
| Jump to Next Match | ⌘G |
| Jump to Previous Match | ⌘⇧G |
| **Email Operations** |
| Select All | ⌘A |
| Export | ⌘E |
| Delete | Delete or ⌫ |
| **View Controls** |
| Toggle Sidebar | ⌘⌃S |
| Toggle Layout Mode | ⌘⌥L |
| Next Tab | ⌘⌥→ |
| Previous Tab | ⌘⌥← |
| **Tools** |
| PII Redaction | ⌘⌥P |
| Theme Settings | ⌘⌥T |
| Export Management | ⌘⇧E |
| **Copy Actions** |
| Copy Email Address | ⌘C (with email selected) |
| Copy Subject | ⌘⌥C |
| Copy Message ID | ⌘⇧C |

### Power User Tips

**Quick Navigation**
- Type first letter to jump to emails starting with that letter
- Hold ⇧ and use arrows for selection
- ⌘-click for multi-select

**Efficient Searching**
- ⌘F, type, ⌘G to jump through matches
- Use ⌘⌥C to clear and start new search
- Recent searches saved in dropdown

**Workflow Shortcuts**
1. ⌘⇧O → Quick open file
2. ⌘F → Search emails
3. ⌘E → Export results
4. ⌘⌥P → Redact if needed

---

## Tips and Tricks

### Productivity Tips

**1. Use Quick Open for Recent Files**
- Press ⌘⇧O anytime
- Type partial filename
- Instant access to recent work
- Pin frequently used files to top

**2. Save Search Combinations**
- Create complex filters
- Save as named filter set
- Reuse with one click
- Share filter sets with team

**3. Export Presets for Repeated Tasks**
- Configure export once
- Save as preset
- Apply instantly later
- Consistency across exports

**4. Keyboard-First Workflow**
- Learn essential shortcuts
- Navigate without mouse
- Faster email browsing
- More efficient operations

**5. Use Three-Column Layout**
- See list and detail simultaneously
- Faster email review
- Better context
- Reduces clicks

### Search Tips

**Finding Specific Content**
```
Email from specific person:
- Use sender filter: "john@example.com"

Emails in date range:
- Smart filter: Date between [start] and [end]

Large emails with attachments:
- Size filter: > 5 MB
- Has attachments: Yes

Emails about specific project:
- Search: "project alpha"
- Save as filter for reuse
```

**Advanced Search Techniques**
```
Multiple criteria:
1. Search text: "report"
2. Sender filter: "@company.com"
3. Date range: Last 30 days
4. Has attachments: Yes
Result: Recent report emails with attachments from company

Pattern matching:
- Use Regex Search for patterns
- Built-in patterns for common data
- Save custom patterns for reuse
```

### Export Tips

**For Archiving**
```
Format: TXT or Markdown
Mode: Per Email
Options:
- Include headers: Yes
- Include attachments: Yes
- Clean text: No (keep original)
```

**For Analysis**
```
Format: CSV
Mode: Per Email
Options:
- Include headers: Yes
- Include attachments: No
- Clean text: Yes (remove noise)

Open in Excel/Numbers for:
- Sorting by date/sender
- Filtering
- Statistics
- Pivot tables
```

**For RAG/LLM Integration**
```
Format: JSON
Mode: Both (per email + per thread)
Options:
- Clean text: Yes
- Enable chunking: Yes (1000 chars)
- Include metadata: Yes
- Thread links: Yes

Perfect for:
- Vector databases
- Semantic search
- AI chat with emails
- Context-aware queries
```

**For Sharing**
```
Format: Markdown
Mode: Per Thread
Options:
- Clean text: Yes
- Include headers: Yes
- Attachments: Extract separately

Benefits:
- Human-readable
- Formatted for documentation
- Easy to review
- Universal format
```

### Performance Tips

**Large MBOX Files**
1. Be patient during initial parse
2. Use Smart Filters to reduce visible emails
3. Close other applications
4. Consider splitting very large files (>2GB)

**Smooth Scrolling**
- Three-column layout more responsive
- Filter to reduce list size
- Hide preview pane if not needed

**Fast Exports**
- Export filtered results instead of all
- Disable chunking if not needed
- TXT format fastest
- JSON format most comprehensive

---

## Troubleshooting

### Common Issues

#### "Cannot open MBOX file"

**Possible Causes:**
- File is not valid MBOX format
- File is corrupted
- File is locked by another application
- Insufficient permissions

**Solutions:**
1. Verify file format (should start with `From ` lines)
2. Check file is readable in Finder
3. Close other email applications
4. Try opening with smaller test file first

#### "App crashes when opening file"

**Solutions:**
1. Check macOS version (requires 14.0+)
2. Restart computer
3. Check available memory (need ~4GB free)
4. Try smaller file first to test
5. Check Console.app for crash logs
6. Reinstall application

#### "Search not finding results"

**Check:**
- Search field has correct text
- No filters are applied (clear with ⌘⌥C)
- Search is case-insensitive by default
- Results exist in file

**Solutions:**
1. Clear all filters
2. Try simpler search term
3. Use "All Fields" in Regex Search
4. Verify emails contain search term

#### "Export fails"

**Common Causes:**
- Insufficient disk space
- No write permission to destination
- Special characters in filenames
- Destination folder doesn't exist

**Solutions:**
1. Check available disk space (need 2x email size)
2. Choose different destination
3. Ensure folder exists and is writable
4. Check Console for error details
5. Try exporting smaller batch first

#### "App running slowly"

**Optimize Performance:**
1. Close unused applications
2. Restart MBox Explorer
3. Use filters to reduce email list
4. Consider splitting large MBOX files
5. Disable preview pane temporarily
6. Check Activity Monitor for memory usage

#### "Attachments not showing"

**Possible Issues:**
- Attachments not base64-encoded
- Corrupted attachment data
- Unsupported encoding

**Solutions:**
1. Check email headers for "Content-Transfer-Encoding"
2. Try exporting email to see raw data
3. Some inline images may not display
4. Extract attachment to verify content

---

## FAQ

### General Questions

**Q: What MBOX files does this support?**
A: Standard RFC 4155 compliant MBOX files from Mail.app, Thunderbird, Gmail exports, and most email clients.

**Q: Can I modify emails in the archive?**
A: No, MBox Explorer is read-only. It won't modify your MBOX files.

**Q: Is my data sent to the cloud?**
A: No, everything processes locally on your Mac. No internet connection needed (except for updates).

**Q: What's the maximum file size?**
A: Tested with 5GB+ files. Parser is streaming-based so technically unlimited.

**Q: Can I open multiple files simultaneously?**
A: Yes, open multiple windows with different files (File → New Window).

### Feature Questions

**Q: What's the difference between "Per Email" and "Per Thread" export?**
A:
- Per Email: One file per individual message (good for searching)
- Per Thread: Related emails combined into conversation files (good for context)
- Both: Generates both formats

**Q: How does PII redaction work?**
A: Uses regex patterns to detect common PII types. Not 100% accurate - always review redacted output before sharing.

**Q: Can I export to PST format?**
A: Not currently. Exports to CSV, JSON, Markdown, and TXT. PST planned for future release.

**Q: How accurate is the similarity score in email comparison?**
A: Uses Levenshtein distance algorithm. Generally accurate for finding similar emails. Best for emails of similar length.

**Q: What does "RAG-optimized export" mean?**
A: Optimized for Retrieval-Augmented Generation (AI/LLM integration). Includes text cleaning, chunking, and metadata for vector databases.

**Q: Can I customize export templates?**
A: Not in v1.0. Custom templates planned for future release. Currently: CSV, JSON, Markdown, TXT.

### Technical Questions

**Q: What macOS version do I need?**
A: macOS 14.0 (Sonoma) or later. Built with SwiftUI 4.0.

**Q: Does it work on Intel Macs?**
A: Yes, universal binary supports both Apple Silicon and Intel.

**Q: How is data stored?**
A: Settings in UserDefaults, no database needed. MBOX files are never modified.

**Q: Are keyboard shortcuts customizable?**
A: Not in v1.0. Uses standard macOS shortcuts. Customization planned for future release.

**Q: Can I run this from command line?**
A: Not currently. GUI-only. CLI version planned for future release.

### Troubleshooting Questions

**Q: Why is parsing slow?**
A: Large files take time. ~1000 emails/second on Apple Silicon. 10,000 emails ≈ 10 seconds.

**Q: Why are some dates showing incorrectly?**
A: Email clients use different date formats. Parser handles most but some exotic formats may fail.

**Q: Can I cancel a long-running operation?**
A: Some operations are cancellable (look for X button). File parsing currently cannot be cancelled once started.

**Q: How do I reset settings?**
A: Preferences → Reset to Defaults. Or manually delete ~/Library/Preferences/com.mboxexplorer.plist

---

## Getting Help

### Documentation
- **README.md**: Quick overview and installation
- **FEATURES.md**: Complete feature documentation
- **DEVELOPER.md**: Technical architecture
- **CHANGELOG.md**: Version history
- **This guide**: User instructions

### Support Channels
- **GitHub Issues**: https://github.com/yourusername/mbox-explorer/issues
- **Email**: support@mboxexplorer.app
- **Discussions**: https://github.com/yourusername/mbox-explorer/discussions

### Reporting Bugs

**Include:**
1. MBox Explorer version
2. macOS version
3. Steps to reproduce
4. Expected vs. actual behavior
5. Screenshots if relevant
6. Console logs if app crashed

**Example Bug Report:**
```
Title: Search crashes when searching for "@"

Environment:
- MBox Explorer v1.0.0
- macOS 14.2 (Sonoma)
- Apple M1 Max

Steps to Reproduce:
1. Open MBOX file (1000+ emails)
2. Type "@" in search field
3. App crashes

Expected: Show results with "@" symbol
Actual: App crashes immediately

Console log attached
```

### Feature Requests

**Include:**
1. Clear description of feature
2. Use case / why it's needed
3. How you'd like it to work
4. Examples from other apps (if any)

**Example Feature Request:**
```
Title: Add support for PST files

Description:
Allow opening Microsoft Outlook PST files in addition to MBOX.

Use Case:
Many corporate users have PST archives that need reviewing.

Proposed Implementation:
Same interface as MBOX, just add PST parser.

Similar Apps:
Outlook handles PST natively.
```

---

## Appendix

### Glossary

**MBOX**: Mail BOX, a text file format for storing email messages

**RAG**: Retrieval-Augmented Generation, technique for LLM/AI integration

**PII**: Personally Identifiable Information (SSN, credit cards, etc.)

**Thread**: Conversation of related emails with same subject

**Regex**: Regular Expression, pattern matching language

**Metadata**: Structured data about emails (sender, date, etc.)

**Chunk**: Segment of split email text for processing

**Levenshtein Distance**: Algorithm measuring string similarity

**Base64**: Encoding scheme for attachments in emails

**UTF-8**: Unicode character encoding for international text

### File Formats

**MBOX Structure:**
```
From sender@example.com Mon Jan 01 00:00:00 2024
From: sender@example.com
To: recipient@example.com
Subject: Email Subject
Date: Mon, 01 Jan 2024 00:00:00 +0000

Email body content here.

From sender2@example.com Mon Jan 02 00:00:00 2024
...
```

**Export Formats:**

**CSV:**
```csv
from,to,subject,date,body,attachments
"john@ex.com","jane@ex.com","Test","2024-01-01","Body","file.pdf"
```

**JSON:**
```json
{
  "from": "john@example.com",
  "to": "jane@example.com",
  "subject": "Test",
  "date": "2024-01-01 12:00:00",
  "body": "Email body...",
  "attachments": ["file.pdf"]
}
```

**Markdown:**
```markdown
# Test

**From:** john@example.com
**To:** jane@example.com
**Date:** Jan 1, 2024

Email body content here.
```

### Resources

**MBOX Format:**
- [RFC 4155](https://tools.ietf.org/html/rfc4155)
- [Wikipedia: mbox](https://en.wikipedia.org/wiki/Mbox)

**Email Standards:**
- [RFC 5322](https://tools.ietf.org/html/rfc5322) - Internet Message Format
- [RFC 2045](https://tools.ietf.org/html/rfc2045) - MIME Part 1

**Regular Expressions:**
- [Regex Tutorial](https://www.regular-expressions.info/)
- [RegEx101](https://regex101.com/) - Online tester

**RAG & Vector Databases:**
- [LangChain Documentation](https://python.langchain.com/)
- [LlamaIndex Docs](https://docs.llamaindex.ai/)
- [Qdrant Docs](https://qdrant.tech/documentation/)

---

## Conclusion

Congratulations! You now know how to use all features of MBox Explorer.

**Quick Reference:**
- ⌘O to open files
- ⌘F to search
- ⌘E to export
- ⌘⇧O for recent files
- View → All Features

**Remember:**
- All processing is local (private)
- Files are never modified (safe)
- Export presets save time
- Keyboard shortcuts boost productivity

**Get Started:**
1. Open an MBOX file (⌘O)
2. Browse and search emails
3. View analytics
4. Export what you need

**Need Help?**
- Check this guide
- See documentation
- Contact support

Enjoy using MBox Explorer! 🎉

# MBox Explorer - Quick Start Guide

## What It Does

MBox Explorer converts your email archives into text files optimized for AI/RAG systems, so you can have conversations with your old emails.

## Simple 3-Step Workflow

### 1. Open Your MBOX File

Click the big blue **"Open MBOX File"** button in the sidebar and select your email archive.

**Common MBOX locations:**
- Mail.app: `~/Library/Mail/V*/MailData/Sent Messages.mbox`
- Thunderbird: `~/.thunderbird/*/ImapMail/*/INBOX`
- Exported archives: Wherever you saved them

### 2. Search and Filter (Optional)

Use the search fields at the top of the email list:
- **Search**: Find text in subject, sender, or body
- **Filter by sender**: Show only emails from specific people
- **Date range**: Filter by date

Click **"Clear Filters"** in the toolbar to reset.

### 3. Export for AI

Click the **"Export Emails"** button in the sidebar.

**Quick Settings:**
- **Format**: Choose "Both" (recommended for AI use)
- **Clean Text**: ✅ Enabled (removes signatures and noise)
- **Chunking**: ✅ Enabled (splits long emails)
- **Metadata**: ✅ Enabled (adds context for AI)

Click **"Export..."** and choose a folder.

## What You Get

Your export folder will contain:

```
MBox Export/
├── emails/           # One file per email
│   ├── 12345_john_meeting.txt
│   ├── 12345_john_meeting.json
│   └── ...
├── threads/          # Conversations grouped
│   ├── project_discussion_thread.txt
│   └── ...
└── INDEX.txt         # Summary statistics
```

## Use With AI

Feed the exported files into your favorite AI system:

- **ChatGPT**: Upload as custom instructions or documents
- **Claude**: Use Projects feature with file uploads
- **LangChain/LlamaIndex**: Point to the export directory
- **Vector Databases**: Import with metadata for semantic search

## Menu Shortcuts

- **⌘O**: Open MBOX file
- **⌘⇧E**: Quick export
- **⌘,**: Export settings

## Troubleshooting

**App won't open MBOX file:**
- Make sure it's a valid MBOX format (starts with `From ` line)
- Try a smaller file first to test

**Export button doesn't work:**
- Make sure you've loaded an MBOX file first
- Check that you have write permission to the destination folder

**Nothing happens when I click Export:**
- The export settings sheet should appear
- If not, try using the menu: Export > Export Settings (⌘,)

## That's It!

The app is designed to be simple:
1. Load your emails
2. Optionally filter what you want
3. Export for AI

The sidebar shows statistics about your email archive. The middle column shows your email list. The right side shows the selected email's full content.

All the complex RAG optimization happens automatically in the background.

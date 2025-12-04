# Quick Start Guide - Adding New Files to Xcode

## 🚀 3-Minute Setup

You need to add 4 new files to the Xcode project before building. Here's exactly how:

---

## Step 1: Open the Project
1. Open `MBox Explorer.xcodeproj` in Xcode
2. Make sure you can see the Project Navigator on the left (⌘1 if hidden)

---

## Step 2: Add Exporter Files

### Location: Exporters Group
1. In Project Navigator, find the **"Exporters"** folder/group
2. Right-click on "Exporters"
3. Select **"Add Files to MBox Explorer..."**
4. Navigate to: `MBox Explorer/MBox Explorer/Exporters/`
5. **Select these 3 files** (hold ⌘ to multi-select):
   - `CSVExporter.swift`
   - `JSONExporter.swift`
   - `MarkdownExporter.swift`
6. **IMPORTANT Settings in the dialog:**
   - ✅ **UNCHECK** "Copy items if needed" (files are already in right place)
   - ✅ **CHECK** "MBox Explorer" under "Add to targets"
   - ✅ **SELECT** "Create groups" (not folder references)
7. Click **"Add"**

---

## Step 3: Add Utility File

### Location: Utilities Group
1. In Project Navigator, find the **"Utilities"** folder/group
2. Right-click on "Utilities"
3. Select **"Add Files to MBox Explorer..."**
4. Navigate to: `MBox Explorer/MBox Explorer/Utilities/`
5. **Select this 1 file:**
   - `WindowStateManager.swift`
6. **IMPORTANT Settings in the dialog:**
   - ✅ **UNCHECK** "Copy items if needed"
   - ✅ **CHECK** "MBox Explorer" under "Add to targets"
   - ✅ **SELECT** "Create groups"
7. Click **"Add"**

---

## Step 4: Verify Files Were Added

### Check Project Navigator:
You should now see:

```
MBox Explorer/
├── Exporters/
│   ├── ExportEngine.swift
│   ├── CSVExporter.swift ← NEW
│   ├── JSONExporter.swift ← NEW
│   └── MarkdownExporter.swift ← NEW
└── Utilities/
    ├── RecentFilesManager.swift
    ├── TextProcessor.swift
    └── WindowStateManager.swift ← NEW
```

All 4 new files should appear in the Project Navigator with the Xcode file icon (not grayed out).

---

## Step 5: Build the Project

1. Select "MBox Explorer" scheme at the top
2. Press **⌘B** or click Product → Build
3. Wait for build to complete
4. You should see **"Build Succeeded"** ✅

If you see build errors, make sure:
- All 4 files were added to the target
- Files are in the correct groups
- No duplicate files were created

---

## Step 6: Run and Test

1. Press **⌘R** or click the Run button
2. Open an MBOX file
3. Test the new features:

### Quick Tests:
- **Export Formats**: Click "Export All Emails" → See new File Format picker with CSV/JSON/Markdown options
- **Column Sorting**: Click column headers (From, Subject, Date, Size) to sort
- **Date Presets**: Click "Date Range" to see preset buttons (Today, Last 7 Days, etc.)
- **Batch Selection**: Click circles next to emails to select multiple → See batch toolbar
- **Reveal Export**: After exporting, see "Show Last Export" button in sidebar

---

## ✅ Done!

That's it! You've successfully added all the new features to MBox Explorer.

See **NEW_FEATURES_SUMMARY.md** for complete documentation of all features.
See **IMPLEMENTATION_ROADMAP.md** for future planned features.

---

## 🆘 Troubleshooting

### Problem: Build fails with "Cannot find type 'WindowStateManager'"
**Solution:** Make sure WindowStateManager.swift was added to the Utilities group and the MBox Explorer target is checked.

### Problem: Build fails with "Cannot find 'CSVExporter' in scope"
**Solution:** Make sure all 3 exporter files were added to the Exporters group and the MBox Explorer target is checked.

### Problem: Files appear grayed out in Project Navigator
**Solution:** The files weren't added to the target. Right-click the file → Target Membership → Check "MBox Explorer"

### Problem: Duplicate files or files in wrong location
**Solution:**
1. Select the file in Project Navigator
2. Press Delete
3. Choose "Remove Reference" (NOT "Move to Trash")
4. Follow the steps above again, making sure to UNCHECK "Copy items if needed"

---

## 📋 File Checklist

Use this to verify all files were added:

- [ ] CSVExporter.swift (in Exporters group)
- [ ] JSONExporter.swift (in Exporters group)
- [ ] MarkdownExporter.swift (in Exporters group)
- [ ] WindowStateManager.swift (in Utilities group)
- [ ] All 4 files have "MBox Explorer" target membership
- [ ] Build succeeds (⌘B)
- [ ] App runs (⌘R)

---

## 🎯 What You Just Added

### Export Formats
Export emails as CSV, JSON, or Markdown in addition to text files.

### Column Sorting
Click column headers to sort by Date, Sender, Subject, or Size.

### Date Range Presets
Quick buttons for Today, Last 7 Days, This Month, etc.

### Batch Selection
Select multiple emails with checkboxes, export or delete in bulk.

### Reveal Last Export
Quickly open last export folder in Finder.

---

Enjoy your enhanced MBox Explorer! 🎉

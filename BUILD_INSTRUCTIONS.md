# Build Instructions - Add New Files to Xcode

## ⚠️ REQUIRED: Add Files Before Building

The project currently has **5 new Swift files** that must be added to Xcode before building.

---

## Step-by-Step Instructions

### 1. Open Project in Xcode
```
Open: MBox Explorer.xcodeproj
```

---

### 2. Add Files to Models Folder

**Right-click on "Models" group** in Project Navigator

1. Select **"Add Files to MBox Explorer..."**
2. Navigate to: `MBox Explorer/MBox Explorer/Models/`
3. Select: **AttachmentManager.swift**
4. **IMPORTANT Settings:**
   - ✅ **UNCHECK** "Copy items if needed"
   - ✅ **CHECK** "MBox Explorer" target
   - ✅ **SELECT** "Create groups"
5. Click **"Add"**

---

### 3. Add Files to Views Folder

**Right-click on "Views" group** in Project Navigator

1. Select **"Add Files to MBox Explorer..."**
2. Navigate to: `MBox Explorer/MBox Explorer/Views/`
3. **Select these 3 files** (hold ⌘ to multi-select):
   - AttachmentsView.swift
   - SavedSearchesView.swift
   - KeyboardNavigationModifier.swift
4. **IMPORTANT Settings:**
   - ✅ **UNCHECK** "Copy items if needed"
   - ✅ **CHECK** "MBox Explorer" target
   - ✅ **SELECT** "Create groups"
5. Click **"Add"**

---

### 4. Add Files to Utilities Folder

**Right-click on "Utilities" group** in Project Navigator

1. Select **"Add Files to MBox Explorer..."**
2. Navigate to: `MBox Explorer/MBox Explorer/Utilities/`
3. Select: **SearchHistoryManager.swift**
4. **IMPORTANT Settings:**
   - ✅ **UNCHECK** "Copy items if needed"
   - ✅ **CHECK** "MBox Explorer" target
   - ✅ **SELECT** "Create groups"
5. Click **"Add"**

---

## Verification Checklist

After adding files, verify in Project Navigator:

```
MBox Explorer/
├── Models/
│   ├── Email.swift
│   ├── MboxParser.swift
│   ├── EmailThread.swift
│   └── AttachmentManager.swift ← NEW
├── Views/
│   ├── ContentView.swift
│   ├── EmailListView.swift
│   ├── AttachmentsView.swift ← NEW
│   ├── SavedSearchesView.swift ← NEW
│   └── KeyboardNavigationModifier.swift ← NEW
└── Utilities/
    ├── TextProcessor.swift
    ├── WindowStateManager.swift
    └── SearchHistoryManager.swift ← NEW
```

### Check Target Membership:

For each new file:
1. Select file in Project Navigator
2. Open File Inspector (⌘⌥1)
3. Under "Target Membership"
4. Verify "MBox Explorer" is ✅ CHECKED

---

## Build & Run

Once all files are added:

### 1. Clean Build Folder
```
Product → Clean Build Folder (⌘⇧K)
```

### 2. Build Project
```
Product → Build (⌘B)
```

**Expected Result:** ✅ BUILD SUCCEEDED

### 3. Run Application
```
Product → Run (⌘R)
```

---

## Testing Checklist

Once the app launches:

### Basic Functionality:
- [ ] App launches without crashes
- [ ] Can open MBOX file
- [ ] Emails display in list
- [ ] Can select and view email

### New Feature 1: Attachments Hub
- [ ] Click "Attachments" in sidebar
- [ ] See all attachments listed
- [ ] Try category filter (e.g., "Images")
- [ ] Search for filename
- [ ] Select multiple attachments
- [ ] Click "Export" button
- [ ] Right-click attachment → "Show in Email"

### New Feature 2: Search History
- [ ] Type search query in search field
- [ ] Press Enter
- [ ] Click clock icon (history button)
- [ ] See search in history
- [ ] Click history item → Applied

### New Feature 3: Saved Searches
- [ ] Set up filters (search + sender + dates)
- [ ] Click star icon
- [ ] Click "Save Current"
- [ ] Name it "Test Search"
- [ ] Clear all filters
- [ ] Click star icon again
- [ ] Click "Test Search"
- [ ] Verify filters restored

### New Feature 4: List Density
- [ ] Click "View" button in toolbar
- [ ] Select "Compact" → List condenses
- [ ] Select "Spacious" → List expands
- [ ] Select "Comfortable" → Default view
- [ ] Restart app → Verify setting persists

### New Feature 5: Advanced Filters
- [ ] Expand "Advanced Filters" disclosure
- [ ] Type "gmail.com" in domain field
- [ ] Verify only Gmail emails shown
- [ ] Click "10-100KB" size button
- [ ] Verify size filtering works
- [ ] Click "Clear" to remove

### New Feature 6: Keyboard Navigation
- [ ] Press `J` → Next email selected
- [ ] Press `K` → Previous email selected
- [ ] Press `/` → Search field focused
- [ ] Press `Escape` to unfocus
- [ ] Press `X` → Current email selected
- [ ] Press `A` → All emails selected
- [ ] Press `Shift+A` → All deselected
- [ ] Press `?` → Help dialog shows

### Export Features:
- [ ] Export to CSV → Opens in spreadsheet
- [ ] Export to JSON → Valid JSON format
- [ ] Export to Markdown → Proper formatting
- [ ] "Show Last Export" button appears
- [ ] Click it → Finder opens to folder

### Batch Operations:
- [ ] Click checkboxes on 3 emails
- [ ] Toolbar shows "3 selected"
- [ ] Click "Export Selected"
- [ ] Click "Delete Selected"
- [ ] Select All / Deselect All works

### Sorting:
- [ ] Click "From" header → Sorts alphabetically
- [ ] Click again → Reverses order
- [ ] Click "Date" header → Sorts by date
- [ ] Click "Subject" header → Sorts by subject
- [ ] Click "Size" header → Sorts by size
- [ ] Restart app → Sort preference saved

### Date Presets:
- [ ] Expand date filter
- [ ] Click "Today" → Filters to today
- [ ] Click "Last 7 Days" → Filters to week
- [ ] Click "This Month" → Filters to month
- [ ] Click "Clear" → Removes filter

---

## Common Issues & Solutions

### Issue: "Cannot find type 'AttachmentManager' in scope"
**Solution:** AttachmentManager.swift not added to project or not added to target
- Add file to project
- Check target membership

### Issue: "Cannot find 'SearchHistoryManager' in scope"
**Solution:** SearchHistoryManager.swift not added to project
- Add file to Utilities folder in Xcode

### Issue: Views not appearing
**Solution:** Check ContentView integration
- Verify SidebarItem enum includes .attachments
- Verify routing in ContentView content section

### Issue: Keyboard shortcuts not working
**Solution:** Check modifier is applied
- KeyboardNavigationModifier should be in EmailListView
- Check onReceive for notifications

### Issue: Saved searches not persisting
**Solution:** UserDefaults permissions
- Check app has file system access
- Try saving and restarting app

---

## Performance Testing

Test with various MBOX sizes:

### Small (< 1MB, < 100 emails):
- [ ] Loads quickly
- [ ] All features responsive

### Medium (1-50MB, 100-1000 emails):
- [ ] Loads within 5 seconds
- [ ] Filtering is smooth
- [ ] Sorting is fast

### Large (50-500MB, 1000-10000 emails):
- [ ] Progress indicator shows during load
- [ ] Can filter while loading
- [ ] Virtual scrolling handles list

### Very Large (> 500MB, > 10000 emails):
- [ ] Background loading works
- [ ] Memory usage reasonable
- [ ] App remains responsive

---

## Bug Reporting Template

If you find issues, note:

```
**Bug:** [Short description]
**Steps to Reproduce:**
1.
2.
3.

**Expected:** [What should happen]
**Actual:** [What actually happens]
**MBOX Size:** [Small/Medium/Large]
**Feature:** [Which new feature]
**Console Errors:** [Any errors in console]
```

---

## Success Criteria

Build is successful when:
- ✅ No build errors
- ✅ No warnings (or only minor deprecated warnings)
- ✅ App launches
- ✅ All 11 features work as documented
- ✅ No crashes during normal use
- ✅ Performance is acceptable for your typical MBOX size

---

## Next Steps After Testing

Once testing is complete:

### Option 1: Report Issues
If you find bugs, let me know and I'll fix them.

### Option 2: Continue Implementation
If everything works, we'll implement the remaining 11 features.

### Option 3: Prioritize
Choose which remaining features are most important to implement next.

---

**Current Status:**
- Code written: ✅ Complete
- Files added to Xcode: ⏳ **YOUR ACTION REQUIRED**
- Build: ⏳ Pending file addition
- Test: ⏳ Pending successful build

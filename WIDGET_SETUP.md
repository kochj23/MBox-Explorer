# MBox Explorer Widget Setup Guide

This guide explains how to complete the widget setup in Xcode.

## Files Created

The widget extension files have been created in:
- `/MBox Explorer Widget/MBoxExplorerWidget.swift` - Main widget with Small, Medium, Large sizes
- `/MBox Explorer Widget/WidgetData.swift` - Data models
- `/MBox Explorer Widget/SharedDataManager.swift` - App Group data sharing
- `/MBox Explorer Widget/Info.plist` - Extension configuration
- `/MBox Explorer Widget/MBox_Explorer_Widget.entitlements` - App Group entitlement
- `/MBox Explorer Widget/Assets.xcassets/` - Widget assets

Shared files for the main app:
- `/MBox Explorer/Shared/WidgetData.swift` - Shared data models
- `/MBox Explorer/Shared/SharedDataManager.swift` - Shared data manager

## Adding the Widget Target in Xcode

### Step 1: Add Widget Extension Target

1. Open the project in Xcode
2. Go to **File > New > Target...**
3. Select **macOS > Widget Extension**
4. Click **Next**
5. Configure:
   - **Product Name**: MBox Explorer Widget
   - **Bundle Identifier**: com.digitalnoise.MBox-Explorer.widget
   - **Embed in Application**: MBox Explorer
   - Uncheck "Include Configuration App Intent" (we use static configuration)
6. Click **Finish**

### Step 2: Replace Generated Files

After Xcode creates the target, replace the auto-generated files with our custom ones:

1. Delete the auto-generated Swift files in the widget target
2. Add our files to the widget target:
   - Drag `MBox Explorer Widget/MBoxExplorerWidget.swift`
   - Drag `MBox Explorer Widget/WidgetData.swift`
   - Drag `MBox Explorer Widget/SharedDataManager.swift`
3. Ensure all files have the widget target selected in **Target Membership**

### Step 3: Configure App Group

1. Select the main app target "MBox Explorer"
2. Go to **Signing & Capabilities**
3. Click **+ Capability**
4. Add **App Groups**
5. Add: `group.com.jkoch.mboxexplorer`

6. Select the widget target "MBox Explorer Widget"
7. Go to **Signing & Capabilities**
8. Click **+ Capability**
9. Add **App Groups**
10. Add: `group.com.jkoch.mboxexplorer`

### Step 4: Verify Entitlements

Ensure the entitlements files contain:

**MBox Explorer/MBox_Explorer.entitlements:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.jkoch.mboxexplorer</string>
    </array>
</dict>
</plist>
```

**MBox Explorer Widget/MBox_Explorer_Widget.entitlements:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.jkoch.mboxexplorer</string>
    </array>
</dict>
</plist>
```

### Step 5: Build and Test

1. Build the main app (Cmd+B)
2. Build the widget extension
3. Run the app
4. Load an mbox file
5. Add the widget to Notification Center:
   - Click date/time in menu bar
   - Scroll down and click "Edit Widgets"
   - Find "MBox Explorer"
   - Add desired size widget

## Widget Features

### Small Widget
- Email count (large number)
- Loaded file name
- Empty state when no data

### Medium Widget
- Email count and thread count
- Date range
- Top 3 senders with initials avatar

### Large Widget
- All medium widget features
- Top 4 senders
- Recent 4 search queries
- Quick search button (opens app)

## Troubleshooting

### Widget shows "No Data"
- Ensure the main app is running
- Load an mbox file
- The app automatically syncs data to the widget

### Widget doesn't update
- Check App Group is configured correctly in both targets
- Rebuild both targets
- Force refresh widget by removing and re-adding

### Code signing issues
- Ensure both targets use the same Team ID
- App Group must be registered with Apple Developer account
- Use automatic signing if possible

## Technical Details

- **Data Sharing**: Uses `UserDefaults(suiteName:)` with App Group
- **Widget Refresh**: Updates every 15 minutes or when app syncs data
- **URL Scheme**: `mboxexplorer://search` for quick search action
- **Timeline Provider**: Static configuration with automatic refresh

## Author

Jordan Koch - February 2026

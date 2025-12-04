//
//  MBox_ExplorerApp.swift
//  MBox Explorer
//
//  App entry point with menu commands
//

import SwiftUI

@main
struct MBox_ExplorerApp: App {
    @StateObject private var recentFilesViewModel = RecentFilesViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recentFilesViewModel)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open MBOX File...") {
                    NotificationCenter.default.post(name: .openMboxFile, object: nil)
                }
                .keyboardShortcut("o")

                Button("Quick Open...") {
                    NotificationCenter.default.post(name: .quickOpen, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                // Recent Files Menu
                Menu("Open Recent") {
                    if recentFilesViewModel.recentFiles.isEmpty {
                        Text("No Recent Files")
                            .disabled(true)
                    } else {
                        ForEach(recentFilesViewModel.recentFiles) { fileInfo in
                            Button(fileInfo.url.lastPathComponent) {
                                NotificationCenter.default.post(name: .openRecentFile, object: fileInfo.url)
                            }
                        }

                        Divider()

                        Button("Clear Menu") {
                            recentFilesViewModel.clearRecent()
                        }
                    }
                }
            }

            CommandMenu("Export") {
                Button("Export All Emails...") {
                    NotificationCenter.default.post(name: .exportAll, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Export Filtered Emails...") {
                    NotificationCenter.default.post(name: .exportFiltered, object: nil)
                }

                Button("Export Current Thread...") {
                    NotificationCenter.default.post(name: .exportThread, object: nil)
                }

                Divider()

                Button("Export Settings...") {
                    NotificationCenter.default.post(name: .showExportSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu("Tools") {
                Button("PII Redaction Tool...") {
                    NotificationCenter.default.post(name: .showRedactionTool, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .option])

                Button("Theme Settings...") {
                    NotificationCenter.default.post(name: .showThemeSettings, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
            }

            CommandMenu("View") {
                Button("Toggle Layout Mode") {
                    NotificationCenter.default.post(name: .toggleLayoutMode, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .option])

                Divider()

                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }

            CommandMenu("Navigate") {
                Button("Next Email") {
                    NotificationCenter.default.post(name: .navigateNext, object: nil)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command])

                Button("Previous Email") {
                    NotificationCenter.default.post(name: .navigatePrevious, object: nil)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command])

                Divider()

                Button("Find in Emails...") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Regex Search...") {
                    NotificationCenter.default.post(name: .showRegexSearch, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Button("Clear Filters") {
                    NotificationCenter.default.post(name: .clearFilters, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            CommandMenu("Selection") {
                Button("Copy Email Address") {
                    NotificationCenter.default.post(name: .copyEmailAddress, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Copy Subject") {
                    NotificationCenter.default.post(name: .copySubject, object: nil)
                }

                Button("Copy Message ID") {
                    NotificationCenter.default.post(name: .copyMessageId, object: nil)
                }

                Divider()

                Button("Delete Email") {
                    NotificationCenter.default.post(name: .deleteEmail, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [.command])
            }
        }
    }
}

// ViewModel for recent files
class RecentFilesViewModel: ObservableObject {
    @Published var recentFiles: [RecentFileInfo] = []

    struct RecentFileInfo: Identifiable {
        let id = UUID()
        let url: URL
        let lastOpened: Date?
        let fileSize: Int?

        var path: String {
            url.path
        }
    }

    init() {
        loadRecent()
    }

    func loadRecent() {
        let urls = RecentFilesManager.shared.recentFiles
        recentFiles = urls.map { url in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let lastOpened = attributes?[.modificationDate] as? Date
            let fileSize = attributes?[.size] as? Int

            return RecentFileInfo(
                url: url,
                lastOpened: lastOpened,
                fileSize: fileSize
            )
        }
    }

    func addRecent(_ url: URL) {
        RecentFilesManager.shared.addRecentFile(url)
        loadRecent()
    }

    func clearRecent() {
        RecentFilesManager.shared.clearRecentFiles()
        loadRecent()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openMboxFile = Notification.Name("openMboxFile")
    static let quickOpen = Notification.Name("quickOpen")
    static let openRecentFile = Notification.Name("openRecentFile")
    static let exportAll = Notification.Name("exportAll")
    static let exportFiltered = Notification.Name("exportFiltered")
    static let exportThread = Notification.Name("exportThread")
    static let showExportSettings = Notification.Name("showExportSettings")
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let navigateNext = Notification.Name("navigateNext")
    static let navigatePrevious = Notification.Name("navigatePrevious")
    static let focusSearch = Notification.Name("focusSearch")
    static let showRegexSearch = Notification.Name("showRegexSearch")
    static let showRedactionTool = Notification.Name("showRedactionTool")
    static let showThemeSettings = Notification.Name("showThemeSettings")
    static let toggleLayoutMode = Notification.Name("toggleLayoutMode")
    static let clearFilters = Notification.Name("clearFilters")
    static let copyEmailAddress = Notification.Name("copyEmailAddress")
    static let copySubject = Notification.Name("copySubject")
    static let copyMessageId = Notification.Name("copyMessageId")
    static let deleteEmail = Notification.Name("deleteEmail")
}

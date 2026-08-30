//
//  DebugLogger.swift
//  MBox Explorer
//
//  Real-time logging system for debugging UI interactions and state changes
//
//  Created on 2026-08-29
//  Debug build only
//

import Foundation
import os.log

#if DEBUG
final class DebugLogger {
    static let shared = DebugLogger()

    private let logger = Logger(subsystem: "com.digitalnoise.MBox-Explorer", category: "Debug")
    private var logBuffer: [String] = []
    private let bufferLock = NSLock()
    private let maxBufferSize = 1000
    private let logFileURL: URL

    private init() {
        // Create log file in app's container
        let containerURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appSupportURL = containerURL.appendingPathComponent("MBox Explorer", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        logFileURL = appSupportURL.appendingPathComponent("debug.log")
        // Clear old log on launch
        try? "=== MBox Explorer Debug Log ===\n".write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Public Logging Methods

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let entry = formatEntry(message, file: file, function: function, line: line, level: "INFO")
        log(entry, level: .info)
    }

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let entry = formatEntry(message, file: file, function: function, line: line, level: "DEBUG")
        log(entry, level: .debug)
    }

    func warn(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let entry = formatEntry(message, file: file, function: function, line: line, level: "WARN")
        log(entry, level: .error)
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let entry = formatEntry(message, file: file, function: function, line: line, level: "ERROR")
        log(entry, level: .error)
    }

    // MARK: - Event-Specific Logging

    func logAppLaunch() {
        info("=== APP LAUNCHED ===")
        logSystemState()
    }

    func logAutoReopenCheck(enabled: Bool, recentCount: Int) {
        info("AutoReopen: enabled=\(enabled), recentFiles.count=\(recentCount)")
    }

    func logFileToReopen(url: URL?, exists: Bool) {
        if let url = url {
            info("AutoReopen: found file to reopen: \(url.lastPathComponent), exists=\(exists)")
        } else {
            debug("AutoReopen: no file to reopen")
        }
    }

    func logLoadMboxFile(url: URL) {
        info("loadMboxFile called: \(url.lastPathComponent)")
    }

    func logRecentFilesLoaded(count: Int) {
        info("RecentFilesViewModel: loaded \(count) recent files")
    }

    func logRecentFileAdded(url: URL) {
        info("RecentFilesViewModel: added recent file: \(url.lastPathComponent)")
    }

    func logRecentFilesCleared() {
        info("RecentFilesViewModel: cleared all recent files")
    }

    func logSettingsLoaded() {
        debug("AIBackendManager: settings loaded from UserDefaults")
    }

    func logSettingsSaved() {
        debug("AIBackendManager: settings saved to UserDefaults")
    }

    func logBackendSelected(backend: String) {
        info("Backend selected: \(backend)")
    }

    func logLMStudioModelSelected(model: String, type: String) {
        info("LM Studio \(type) model selected: \(model)")
    }

    // MARK: - System State Logging

    func logSystemState() {
        let recentFiles = RecentFilesManager.shared.recentFiles
        info("System state: recentFiles.count=\(recentFiles.count)")
        info("System state: autoReopen=\(AutoReopen.isEnabled)")

        let fileToReopen = AutoReopen.fileToReopen(enabled: AutoReopen.isEnabled, recent: recentFiles)
        if let url = fileToReopen {
            let exists = FileManager.default.fileExists(atPath: url.path)
            info("System state: fileToReopen=\(url.lastPathComponent), exists=\(exists)")
        } else {
            info("System state: fileToReopen=nil")
        }

        let defaults = UserDefaults.standard
        info("System state: selectedBackend=\(defaults.string(forKey: "AIBackendManager_SelectedBackend") ?? "nil")")
        info("System state: lmStudioURL=\(defaults.string(forKey: "AIBackendManager_LMStudioServerURL") ?? "nil")")
        info("System state: selectedLMStudioModel=\(defaults.string(forKey: "AIBackendManager_SelectedLMStudioModel") ?? "nil")")
        info("System state: selectedLMStudioEmbeddingModel=\(defaults.string(forKey: "AIBackendManager_SelectedLMStudioEmbeddingModel") ?? "nil")")
    }

    func dumpRecentFiles() {
        let recentFiles = RecentFilesManager.shared.recentFiles
        info("=== RECENT FILES DUMP ===")
        if recentFiles.isEmpty {
            info("No recent files")
        } else {
            for (index, url) in recentFiles.enumerated() {
                let exists = FileManager.default.fileExists(atPath: url.path)
                info("  [\(index)] \(url.lastPathComponent) - exists: \(exists)")
            }
        }
    }

    // MARK: - Private Methods

    private func formatEntry(_ message: String, file: String, function: String, line: Int, level: String) -> String {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        return "[\(timestamp)] [\(level)] [\(fileName):\(line) \(function)] \(message)"
    }

    private func log(_ entry: String, level: OSLogType) {
        logger.log(level: level, "\(entry, privacy: .public)")

        bufferLock.lock()
        logBuffer.append(entry)
        if logBuffer.count > maxBufferSize {
            logBuffer.removeFirst()
        }
        bufferLock.unlock()

        // Write to file
        if let data = (entry + "\n").data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }

        #if DEBUG
        print(entry)
        #endif
    }

    // MARK: - Public API

    func getLogBuffer() -> [String] {
        bufferLock.lock()
        let buffer = logBuffer
        bufferLock.unlock()
        return buffer
    }

    func clearLogBuffer() {
        bufferLock.lock()
        logBuffer.removeAll()
        bufferLock.unlock()
        info("Log buffer cleared")
    }

    func dumpLogBuffer() {
        bufferLock.lock()
        let buffer = logBuffer
        bufferLock.unlock()
        info("=== LOG BUFFER DUMP (\(buffer.count) entries) ===")
        for entry in buffer {
            info(entry)
        }
    }
}
#else
final class DebugLogger {
    static let shared = DebugLogger()
    private init() {}

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {}
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {}
    func warn(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {}
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {}
    func logAppLaunch() {}
    func logAutoReopenCheck(enabled: Bool, recentCount: Int) {}
    func logFileToReopen(url: URL?, exists: Bool) {}
    func logLoadMboxFile(url: URL) {}
    func logRecentFilesLoaded(count: Int) {}
    func logRecentFileAdded(url: URL) {}
    func logRecentFilesCleared() {}
    func logSettingsLoaded() {}
    func logSettingsSaved() {}
    func logBackendSelected(backend: String) {}
    func logLMStudioModelSelected(model: String, type: String) {}
    func logSystemState() {}
    func dumpRecentFiles() {}
    func getLogBuffer() -> [String] { return [] }
    func clearLogBuffer() {}
    func dumpLogBuffer() {}
}
#endif

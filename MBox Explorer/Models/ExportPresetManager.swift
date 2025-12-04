//
//  ExportPresetManager.swift
//  MBox Explorer
//
//  Manages export presets and history
//

import Foundation

class ExportPresetManager {
    static let shared = ExportPresetManager()

    private let presetsKey = "ExportPresets"
    private let historyKey = "ExportHistory"
    private let maxHistory = 20

    private init() {}

    // MARK: - Presets

    struct ExportPreset: Codable, Identifiable, Equatable {
        let id: UUID
        var name: String
        let format: String // "csv", "json", "markdown"
        let includeAttachments: Bool
        let includeHeaders: Bool
        let dateFormat: String
        let createdDate: Date

        init(id: UUID = UUID(),
             name: String,
             format: String,
             includeAttachments: Bool = true,
             includeHeaders: Bool = true,
             dateFormat: String = "yyyy-MM-dd HH:mm:ss",
             createdDate: Date = Date()) {
            self.id = id
            self.name = name
            self.format = format
            self.includeAttachments = includeAttachments
            self.includeHeaders = includeHeaders
            self.dateFormat = dateFormat
            self.createdDate = createdDate
        }

        var formatIcon: String {
            switch format.lowercased() {
            case "csv": return "tablecells"
            case "json": return "curlybraces"
            case "markdown": return "doc.text"
            default: return "doc"
            }
        }

        var formatDescription: String {
            switch format.lowercased() {
            case "csv": return "Comma-separated values (spreadsheet compatible)"
            case "json": return "JavaScript Object Notation (structured data)"
            case "markdown": return "Markdown format (readable text)"
            default: return "Unknown format"
            }
        }
    }

    var presets: [ExportPreset] {
        guard let data = UserDefaults.standard.data(forKey: presetsKey),
              let decoded = try? JSONDecoder().decode([ExportPreset].self, from: data) else {
            return defaultPresets()
        }
        return decoded
    }

    func savePreset(_ preset: ExportPreset) {
        var presets = self.presets

        // Check if preset with same ID exists, update it
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }

        if let encoded = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(encoded, forKey: presetsKey)
        }
    }

    func deletePreset(_ preset: ExportPreset) {
        var presets = self.presets
        presets.removeAll { $0.id == preset.id }

        if let encoded = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(encoded, forKey: presetsKey)
        }
    }

    func renamePreset(_ preset: ExportPreset, newName: String) {
        var updatedPreset = preset
        updatedPreset.name = newName
        savePreset(updatedPreset)
    }

    private func defaultPresets() -> [ExportPreset] {
        return [
            ExportPreset(
                name: "CSV - Full Details",
                format: "csv",
                includeAttachments: true,
                includeHeaders: true
            ),
            ExportPreset(
                name: "JSON - Complete",
                format: "json",
                includeAttachments: true,
                includeHeaders: true
            ),
            ExportPreset(
                name: "Markdown - Readable",
                format: "markdown",
                includeAttachments: false,
                includeHeaders: true
            )
        ]
    }

    // MARK: - History

    struct ExportHistoryItem: Codable, Identifiable, Equatable {
        let id: UUID
        let format: String
        let emailCount: Int
        let fileSize: Int64
        let exportDate: Date
        let destinationPath: String
        let presetName: String?

        init(id: UUID = UUID(),
             format: String,
             emailCount: Int,
             fileSize: Int64,
             exportDate: Date = Date(),
             destinationPath: String,
             presetName: String? = nil) {
            self.id = id
            self.format = format
            self.emailCount = emailCount
            self.fileSize = fileSize
            self.exportDate = exportDate
            self.destinationPath = destinationPath
            self.presetName = presetName
        }

        var displaySize: String {
            ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        }

        var relativeTime: String {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: exportDate, relativeTo: Date())
        }

        var formatIcon: String {
            switch format.lowercased() {
            case "csv": return "tablecells"
            case "json": return "curlybraces"
            case "markdown": return "doc.text"
            default: return "doc"
            }
        }
    }

    var exportHistory: [ExportHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([ExportHistoryItem].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.exportDate > $1.exportDate }
    }

    func addToHistory(_ item: ExportHistoryItem) {
        var history = self.exportHistory
        history.insert(item, at: 0)

        // Keep only last N items
        if history.count > maxHistory {
            history = Array(history.prefix(maxHistory))
        }

        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }

    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    func removeFromHistory(_ item: ExportHistoryItem) {
        var history = self.exportHistory
        history.removeAll { $0.id == item.id }

        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }

    // MARK: - Statistics

    struct ExportStatistics {
        let totalExports: Int
        let totalEmailsExported: Int
        let totalDataExported: Int64
        let mostUsedFormat: String
        let formatBreakdown: [String: Int]

        var totalDataFormatted: String {
            ByteCountFormatter.string(fromByteCount: totalDataExported, countStyle: .file)
        }
    }

    func getStatistics() -> ExportStatistics {
        let history = exportHistory

        let totalExports = history.count
        let totalEmailsExported = history.reduce(0) { $0 + $1.emailCount }
        let totalDataExported = history.reduce(0) { $0 + $1.fileSize }

        let formatCounts = Dictionary(grouping: history, by: { $0.format })
            .mapValues { $0.count }

        let mostUsedFormat = formatCounts.max { $0.value < $1.value }?.key ?? "csv"

        return ExportStatistics(
            totalExports: totalExports,
            totalEmailsExported: totalEmailsExported,
            totalDataExported: totalDataExported,
            mostUsedFormat: mostUsedFormat,
            formatBreakdown: formatCounts
        )
    }
}

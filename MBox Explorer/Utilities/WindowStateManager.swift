//
//  WindowStateManager.swift
//  MBox Explorer
//
//  Persist window state and user preferences
//

import Foundation
import SwiftUI

class WindowStateManager {
    static let shared = WindowStateManager()

    private let windowFrameKey = "WindowFrame"
    private let columnWidthsKey = "ColumnWidths"
    private let sortOrderKey = "SortOrder"
    private let sortFieldKey = "SortField"
    private let listDensityKey = "ListDensity"
    private let appearanceModeKey = "AppearanceMode"

    struct WindowFrame: Codable {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    struct ColumnWidths: Codable {
        let sidebar: CGFloat
        let list: CGFloat
        let detail: CGFloat
    }

    enum SortField: String, Codable {
        case date
        case sender
        case subject
        case size
    }

    enum SortOrder: String, Codable {
        case ascending
        case descending
    }

    enum ListDensity: String, Codable {
        case compact
        case comfortable
        case spacious
    }

    enum AppearanceMode: String, Codable {
        case light
        case dark
        case auto
    }

    // MARK: - Window Frame

    func saveWindowFrame(_ frame: CGRect) {
        let windowFrame = WindowFrame(x: frame.origin.x, y: frame.origin.y, width: frame.size.width, height: frame.size.height)
        if let data = try? JSONEncoder().encode(windowFrame) {
            UserDefaults.standard.set(data, forKey: windowFrameKey)
        }
    }

    func loadWindowFrame() -> CGRect? {
        guard let data = UserDefaults.standard.data(forKey: windowFrameKey),
              let windowFrame = try? JSONDecoder().decode(WindowFrame.self, from: data) else {
            return nil
        }
        return CGRect(x: windowFrame.x, y: windowFrame.y, width: windowFrame.width, height: windowFrame.height)
    }

    // MARK: - Column Widths

    func saveColumnWidths(sidebar: CGFloat, list: CGFloat, detail: CGFloat) {
        let widths = ColumnWidths(sidebar: sidebar, list: list, detail: detail)
        if let data = try? JSONEncoder().encode(widths) {
            UserDefaults.standard.set(data, forKey: columnWidthsKey)
        }
    }

    func loadColumnWidths() -> ColumnWidths? {
        guard let data = UserDefaults.standard.data(forKey: columnWidthsKey),
              let widths = try? JSONDecoder().decode(ColumnWidths.self, from: data) else {
            return nil
        }
        return widths
    }

    // MARK: - Sort Preferences

    func saveSortPreferences(field: SortField, order: SortOrder) {
        UserDefaults.standard.set(field.rawValue, forKey: sortFieldKey)
        UserDefaults.standard.set(order.rawValue, forKey: sortOrderKey)
    }

    func loadSortField() -> SortField {
        guard let raw = UserDefaults.standard.string(forKey: sortFieldKey),
              let field = SortField(rawValue: raw) else {
            return .date
        }
        return field
    }

    func loadSortOrder() -> SortOrder {
        guard let raw = UserDefaults.standard.string(forKey: sortOrderKey),
              let order = SortOrder(rawValue: raw) else {
            return .descending
        }
        return order
    }

    // MARK: - UI Preferences

    func saveListDensity(_ density: ListDensity) {
        UserDefaults.standard.set(density.rawValue, forKey: listDensityKey)
    }

    func loadListDensity() -> ListDensity {
        guard let raw = UserDefaults.standard.string(forKey: listDensityKey),
              let density = ListDensity(rawValue: raw) else {
            return .comfortable
        }
        return density
    }

    func saveAppearanceMode(_ mode: AppearanceMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: appearanceModeKey)
    }

    func loadAppearanceMode() -> AppearanceMode {
        guard let raw = UserDefaults.standard.string(forKey: appearanceModeKey),
              let mode = AppearanceMode(rawValue: raw) else {
            return .auto
        }
        return mode
    }

    // MARK: - Active List Density

    var activeListDensity: ListDensity {
        get { loadListDensity() }
        set { saveListDensity(newValue) }
    }
}

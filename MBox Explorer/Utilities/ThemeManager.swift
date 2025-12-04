//
//  ThemeManager.swift
//  MBox Explorer
//
//  Custom theme management for dark mode optimization
//

import SwiftUI
import AppKit

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: AppTheme = .system {
        didSet {
            saveTheme()
            applyTheme()
        }
    }

    @Published var customColors = CustomColors()

    enum AppTheme: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
        case highContrast = "High Contrast"
        case amoled = "AMOLED Black"
        case solarized = "Solarized"
        case nord = "Nord"
        case custom = "Custom"

        var id: String { rawValue }
    }

    struct CustomColors: Codable {
        var backgroundColor: String = "#1E1E1E"
        var secondaryBackground: String = "#2D2D30"
        var tertiaryBackground: String = "#3E3E42"
        var textColor: String = "#FFFFFF"
        var secondaryText: String = "#9A9A9A"
        var accentColor: String = "#007AFF"
        var highlightColor: String = "#FFD700"
        var emailRowBackground: String = "#252526"
        var selectedRowBackground: String = "#094771"
        var dividerColor: String = "#3E3E42"
    }

    private init() {
        loadTheme()
        applyTheme()
    }

    func applyTheme() {
        // Update app appearance
        switch currentTheme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .highContrast:
            NSApp.appearance = NSAppearance(named: .accessibilityHighContrastDarkAqua)
        case .amoled, .solarized, .nord, .custom:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func saveTheme() {
        UserDefaults.standard.set(currentTheme.rawValue, forKey: "AppTheme")

        if let encoded = try? JSONEncoder().encode(customColors) {
            UserDefaults.standard.set(encoded, forKey: "CustomColors")
        }
    }

    private func loadTheme() {
        if let themeString = UserDefaults.standard.string(forKey: "AppTheme"),
           let theme = AppTheme(rawValue: themeString) {
            currentTheme = theme
        }

        if let data = UserDefaults.standard.data(forKey: "CustomColors"),
           let decoded = try? JSONDecoder().decode(CustomColors.self, from: data) {
            customColors = decoded
        }
    }

    // MARK: - Theme Colors

    func backgroundColor(for theme: AppTheme) -> Color {
        switch theme {
        case .system, .light:
            return Color(NSColor.windowBackgroundColor)
        case .dark:
            return Color(hex: "#1E1E1E")
        case .highContrast:
            return Color.black
        case .amoled:
            return Color.black
        case .solarized:
            return Color(hex: "#002B36")
        case .nord:
            return Color(hex: "#2E3440")
        case .custom:
            return Color(hex: customColors.backgroundColor)
        }
    }

    func secondaryBackground(for theme: AppTheme) -> Color {
        switch theme {
        case .system, .light:
            return Color(NSColor.controlBackgroundColor)
        case .dark:
            return Color(hex: "#2D2D30")
        case .highContrast:
            return Color(hex: "#0F0F0F")
        case .amoled:
            return Color(hex: "#0A0A0A")
        case .solarized:
            return Color(hex: "#073642")
        case .nord:
            return Color(hex: "#3B4252")
        case .custom:
            return Color(hex: customColors.secondaryBackground)
        }
    }

    func textColor(for theme: AppTheme) -> Color {
        switch theme {
        case .system, .light:
            return Color(NSColor.labelColor)
        case .dark, .highContrast, .amoled:
            return Color.white
        case .solarized:
            return Color(hex: "#839496")
        case .nord:
            return Color(hex: "#ECEFF4")
        case .custom:
            return Color(hex: customColors.textColor)
        }
    }

    func accentColor(for theme: AppTheme) -> Color {
        switch theme {
        case .system, .light, .dark:
            return Color.accentColor
        case .highContrast:
            return Color.yellow
        case .amoled:
            return Color.cyan
        case .solarized:
            return Color(hex: "#268BD2")
        case .nord:
            return Color(hex: "#88C0D0")
        case .custom:
            return Color(hex: customColors.accentColor)
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String {
        guard let components = NSColor(self).cgColor.components else {
            return "#000000"
        }

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Environment Key

struct ThemeKey: EnvironmentKey {
    static let defaultValue = ThemeManager.shared.currentTheme
}

extension EnvironmentValues {
    var appTheme: ThemeManager.AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

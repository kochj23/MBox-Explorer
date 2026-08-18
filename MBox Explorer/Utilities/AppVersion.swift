//
//  AppVersion.swift
//  MBox Explorer
//
//  App version + build date, surfaced in the app menu and the About panel.
//

import Foundation
import AppKit

enum AppVersion {
    /// CFBundleShortVersionString, e.g. "2.3.0".
    static var short: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// CFBundleVersion (build number), e.g. "3".
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    /// When the app binary was built (from the executable's file date).
    static var buildDate: Date {
        if let url = Bundle.main.executableURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let date = (attrs[.creationDate] as? Date) ?? (attrs[.modificationDate] as? Date) {
            return date
        }
        return Date()
    }

    static var buildDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: buildDate)
    }

    /// One-line summary for a menu item, e.g. "Version 2.3.0 (build 3) — Aug 18, 2026".
    static var menuLine: String {
        "Version \(short) (build \(build)) — \(buildDateString)"
    }

    @MainActor
    static func showAboutPanel() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "MBox Explorer",
            .applicationVersion: short,
            .version: build,
            .credits: NSAttributedString(
                string: "Built \(buildDateString)\n",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            )
        ])
    }
}

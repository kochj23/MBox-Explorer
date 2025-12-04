//
//  ThemeSettingsView.swift
//  MBox Explorer
//
//  Theme customization interface
//

import SwiftUI

struct ThemeSettingsView: View {
    @ObservedObject var themeManager = ThemeManager.shared
    @Binding var isPresented: Bool
    @State private var showingCustomColorEditor = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Theme Settings")
                    .font(.title2)
                    .bold()

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Theme Selector
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose Theme")
                            .font(.headline)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(ThemeManager.AppTheme.allCases) { theme in
                                ThemeCard(
                                    theme: theme,
                                    isSelected: themeManager.currentTheme == theme,
                                    onSelect: {
                                        themeManager.currentTheme = theme
                                    }
                                )
                            }
                        }
                    }

                    Divider()

                    // Theme Preview
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Preview")
                            .font(.headline)

                        ThemePreview(theme: themeManager.currentTheme)
                    }

                    Divider()

                    // Custom Color Editor
                    if themeManager.currentTheme == .custom {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Custom Colors")
                                .font(.headline)

                            Button {
                                showingCustomColorEditor = true
                            } label: {
                                Label("Edit Custom Colors", systemImage: "paintpalette")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Divider()

                    // Theme Details
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Theme Details")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            DetailRow(label: "Name", value: themeManager.currentTheme.rawValue)
                            DetailRow(label: "Background", value: themeManager.backgroundColor(for: themeManager.currentTheme).toHex())
                            DetailRow(label: "Text", value: themeManager.textColor(for: themeManager.currentTheme).toHex())
                            DetailRow(label: "Accent", value: themeManager.accentColor(for: themeManager.currentTheme).toHex())
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Button("Reset to Default") {
                    themeManager.currentTheme = .system
                }

                Spacer()

                Button("Done") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 700, height: 650)
        .sheet(isPresented: $showingCustomColorEditor) {
            CustomColorEditorView(
                colors: $themeManager.customColors,
                isPresented: $showingCustomColorEditor
            )
        }
    }
}

// MARK: - Theme Card

struct ThemeCard: View {
    let theme: ThemeManager.AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(spacing: 8) {
                // Color preview
                HStack(spacing: 2) {
                    ThemeManager.shared.backgroundColor(for: theme)
                        .frame(width: 40, height: 60)
                    ThemeManager.shared.secondaryBackground(for: theme)
                        .frame(width: 40, height: 60)
                    ThemeManager.shared.accentColor(for: theme)
                        .frame(width: 40, height: 60)
                }
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                )

                Text(theme.rawValue)
                    .font(.caption)
                    .bold(isSelected)
                    .foregroundColor(isSelected ? .blue : .primary)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor).opacity(isSelected ? 0.5 : 0.2))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme Preview

struct ThemePreview: View {
    let theme: ThemeManager.AppTheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Email Preview")
                    .font(.headline)
                    .foregroundColor(ThemeManager.shared.textColor(for: theme))

                Spacer()

                Circle()
                    .fill(ThemeManager.shared.accentColor(for: theme))
                    .frame(width: 12, height: 12)
            }
            .padding()
            .background(ThemeManager.shared.secondaryBackground(for: theme))

            // Email list preview
            VStack(spacing: 1) {
                ForEach(0..<3) { i in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sample Email Subject \(i + 1)")
                                .font(.subheadline)
                                .foregroundColor(ThemeManager.shared.textColor(for: theme))

                            Text("from@example.com")
                                .font(.caption)
                                .foregroundColor(ThemeManager.shared.textColor(for: theme).opacity(0.7))
                        }

                        Spacer()

                        Text("12:34 PM")
                            .font(.caption2)
                            .foregroundColor(ThemeManager.shared.textColor(for: theme).opacity(0.6))
                    }
                    .padding(12)
                    .background(i == 1 ? ThemeManager.shared.accentColor(for: theme).opacity(0.2) : Color.clear)
                }
            }
            .background(ThemeManager.shared.backgroundColor(for: theme))
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.caption)
                .bold()

            Spacer()

            // Color swatch if it's a hex color
            if value.hasPrefix("#") {
                Color(hex: value)
                    .frame(width: 20, height: 20)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
            }
        }
    }
}

// MARK: - Custom Color Editor

struct CustomColorEditorView: View {
    @Binding var colors: ThemeManager.CustomColors
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Custom Color Editor")
                    .font(.title2)
                    .bold()

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    ColorPickerRow(label: "Background", color: $colors.backgroundColor)
                    ColorPickerRow(label: "Secondary Background", color: $colors.secondaryBackground)
                    ColorPickerRow(label: "Tertiary Background", color: $colors.tertiaryBackground)
                    ColorPickerRow(label: "Text Color", color: $colors.textColor)
                    ColorPickerRow(label: "Secondary Text", color: $colors.secondaryText)
                    ColorPickerRow(label: "Accent Color", color: $colors.accentColor)
                    ColorPickerRow(label: "Highlight Color", color: $colors.highlightColor)
                    ColorPickerRow(label: "Email Row Background", color: $colors.emailRowBackground)
                    ColorPickerRow(label: "Selected Row", color: $colors.selectedRowBackground)
                    ColorPickerRow(label: "Divider Color", color: $colors.dividerColor)
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Reset to Defaults") {
                    colors = ThemeManager.CustomColors()
                }

                Spacer()

                Button("Done") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
    }
}

struct ColorPickerRow: View {
    let label: String
    @Binding var color: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .frame(width: 160, alignment: .leading)

            ColorPicker("", selection: Binding(
                get: { Color(hex: color) },
                set: { color = $0.toHex() }
            ))
            .labelsHidden()

            TextField("Hex", text: $color)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 100)

            Color(hex: color)
                .frame(width: 40, height: 30)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
        }
    }
}

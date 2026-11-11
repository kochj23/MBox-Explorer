//
//  ToolbarCommands.swift
//  MBox Explorer
//
//  Toolbar buttons and commands
//

import SwiftUI
import NovaAIKit

// MARK: - AI Status Indicator for Toolbar

/// NovaAIKit status dot + label; the gear opens the AI settings.
struct AIStatusIndicator: View {
    @State private var showingSettings = false

    var body: some View {
        HStack(spacing: 6) {
            NovaAIStatusIndicator(ai: AppAI.shared)
                .font(.system(size: 11))
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("AI settings")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
        )
        .sheet(isPresented: $showingSettings) {
            AISettingsView(onClose: { showingSettings = false })
        }
    }
}

struct ToolbarCommands: View {
    @ObservedObject var viewModel: MboxViewModel
    @Binding var showingFilePicker: Bool

    var body: some View {
        Group {
            // AI Status indicator (compact)
            AIStatusIndicator()

            // List density picker
            Menu {
                Picker("List Density", selection: $viewModel.listDensity) {
                    Label("Compact", systemImage: "list.bullet").tag(WindowStateManager.ListDensity.compact)
                    Label("Comfortable", systemImage: "list.bullet.indent").tag(WindowStateManager.ListDensity.comfortable)
                    Label("Spacious", systemImage: "list.dash").tag(WindowStateManager.ListDensity.spacious)
                }
            } label: {
                Label("View", systemImage: densityIcon)
            }
            .help("Change list density")
            .onChange(of: viewModel.listDensity) { oldValue, newValue in
                WindowStateManager.shared.saveListDensity(newValue)
            }

            // Only show clear filters if there are active filters
            if !viewModel.searchText.isEmpty || !viewModel.filterSender.isEmpty ||
               viewModel.startDate != nil || viewModel.endDate != nil {
                Button {
                    viewModel.searchText = ""
                    viewModel.filterSender = ""
                    viewModel.startDate = nil
                    viewModel.endDate = nil
                } label: {
                    Label("Clear Filters", systemImage: "xmark.circle")
                }
                .help("Clear all search and filter criteria")
            }
        }
    }

    private var densityIcon: String {
        switch viewModel.listDensity {
        case .compact: return "list.bullet"
        case .comfortable: return "list.bullet.indent"
        case .spacious: return "list.dash"
        }
    }

    private func exportFiltered() async {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Filtered_Export"
        panel.message = "Choose location to export filtered emails"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    await viewModel.exportFiltered(
                        to: url.deletingLastPathComponent(),
                        filename: url.lastPathComponent
                    )
                }
            }
        }
    }
}

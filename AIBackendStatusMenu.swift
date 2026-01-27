import SwiftUI

//
//  AIBackendStatusMenu.swift
//  Universal AI Backend Status Menu
//
//  Reusable component for all Jordan Koch AI projects
//  Shows backend status, model selection, and quick settings access
//
//  Author: Jordan Koch
//  Date: 2026-01-26
//  Version: 1.0.0
//
//  Usage:
//  Add to any SwiftUI view:
//      AIBackendStatusMenu()
//
//  Or with custom theme:
//      AIBackendStatusMenu(accentColor: .blue, compact: true)
//

struct AIBackendStatusMenu: View {
    @ObservedObject var manager = AIBackendManager.shared
    @State private var showSettings = false
    @State private var isRefreshing = false

    // Theme customization
    var accentColor: Color = .blue
    var compact: Bool = false
    var showModelPicker: Bool = true

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            // Status Indicator
            backendStatusIndicator

            // Backend Selector
            if !compact {
                backendSelector
            }

            // Model Selector (for Ollama)
            if showModelPicker && manager.activeBackend == .ollama && !manager.ollamaModels.isEmpty {
                modelSelector
            }

            // Action Buttons
            actionButtons
        }
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.vertical, compact ? 4 : 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
        )
        .sheet(isPresented: $showSettings) {
            AIBackendSelectionView()
        }
    }

    // MARK: - Status Indicator

    private var backendStatusIndicator: some View {
        HStack(spacing: 6) {
            // Main status dot
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 2)
                        .scaleEffect(isRefreshing ? 1.5 : 1.0)
                        .opacity(isRefreshing ? 0 : 1)
                        .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: isRefreshing)
                )

            if !compact {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(statusColor)

                    if let backend = manager.activeBackend {
                        Text(backend.rawValue)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        if manager.activeBackend != nil {
            return .green
        } else if hasAnyConfigured {
            return .gray
        } else {
            return .red
        }
    }

    private var statusText: String {
        if manager.activeBackend != nil {
            return "Connected"
        } else if hasAnyConfigured {
            return "Not Configured"
        } else {
            return "Offline"
        }
    }

    private var hasAnyConfigured: Bool {
        manager.isOllamaAvailable || manager.isMLXAvailable ||
        manager.isTinyLLMAvailable || manager.isTinyChatAvailable ||
        manager.isOpenWebUIAvailable || manager.isOpenAIAvailable ||
        manager.isGoogleCloudAvailable || manager.isAzureAvailable ||
        manager.isAWSAvailable || manager.isIBMWatsonAvailable
    }

    // MARK: - Backend Selector

    private var backendSelector: some View {
        Menu {
            ForEach(AIBackendManager.AIBackend.allCases, id: \.self) { backend in
                Button(action: {
                    manager.activeBackend = backend
                    manager.saveConfiguration()
                    Task {
                        await manager.refreshAllBackends()
                    }
                }) {
                    HStack {
                        Image(systemName: backendIcon(backend))
                        Text(backend.rawValue)
                        Spacer()
                        if isBackendAvailable(backend) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else if isBackendConfigured(backend) {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.gray)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
            }

            Divider()

            Button(action: { showSettings = true }) {
                Label("Settings", systemImage: "gear")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                Text("Backend")
                    .font(.system(size: 11))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundColor(accentColor)
        }
        .menuStyle(.borderlessButton)
        .frame(height: 24)
    }

    // MARK: - Model Selector

    private var modelSelector: some View {
        Menu {
            ForEach(manager.ollamaModels, id: \.self) { model in
                Button(action: {
                    manager.selectedOllamaModel = model
                    manager.saveConfiguration()
                }) {
                    HStack {
                        Text(model)
                        Spacer()
                        if manager.selectedOllamaModel == model {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "brain")
                Text(truncateModelName(manager.selectedOllamaModel))
                    .font(.system(size: 11))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .foregroundColor(accentColor)
        }
        .menuStyle(.borderlessButton)
        .frame(height: 24)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 4) {
            // Refresh Button
            Button(action: {
                isRefreshing = true
                Task {
                    await manager.refreshAllBackends()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    isRefreshing = false
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(accentColor)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isRefreshing)
            }
            .buttonStyle(.plain)
            .help("Refresh backend status")

            // Settings Button
            Button(action: { showSettings = true }) {
                Image(systemName: "gear")
                    .font(.system(size: 11))
                    .foregroundColor(accentColor)
            }
            .buttonStyle(.plain)
            .help("Configure AI backends")
        }
    }

    // MARK: - Helper Functions

    private func backendIcon(_ backend: AIBackendManager.AIBackend) -> String {
        switch backend {
        case .ollama: return "network"
        case .mlx: return "cpu"
        case .tinyLLM: return "cube"
        case .tinyChat: return "bubble.left.and.bubble.right.fill"
        case .openWebUI: return "globe"
        case .openAI: return "brain"
        case .googleCloud: return "cloud"
        case .azureCognitive: return "cloud.fill"
        case .awsAI: return "server.rack"
        case .ibmWatson: return "atom"
        }
    }

    private func isBackendAvailable(_ backend: AIBackendManager.AIBackend) -> Bool {
        switch backend {
        case .ollama: return manager.isOllamaAvailable
        case .mlx: return manager.isMLXAvailable
        case .tinyLLM: return manager.isTinyLLMAvailable
        case .tinyChat: return manager.isTinyChatAvailable
        case .openWebUI: return manager.isOpenWebUIAvailable
        case .openAI: return manager.isOpenAIAvailable
        case .googleCloud: return manager.isGoogleCloudAvailable
        case .azureCognitive: return manager.isAzureAvailable
        case .awsAI: return manager.isAWSAvailable
        case .ibmWatson: return manager.isIBMWatsonAvailable
        }
    }

    private func isBackendConfigured(_ backend: AIBackendManager.AIBackend) -> Bool {
        switch backend {
        case .ollama, .mlx, .tinyLLM, .tinyChat, .openWebUI:
            return true // Local backends don't need configuration
        case .openAI: return !manager.openAIAPIKey.isEmpty
        case .googleCloud: return !manager.googleCloudAPIKey.isEmpty
        case .azureCognitive: return !manager.azureAPIKey.isEmpty
        case .awsAI: return !manager.awsAccessKey.isEmpty
        case .ibmWatson: return !manager.ibmWatsonAPIKey.isEmpty
        }
    }

    private func truncateModelName(_ name: String) -> String {
        let parts = name.split(separator: ":")
        return String(parts.first ?? name)
    }
}

// MARK: - Compact Variant

struct AIBackendStatusMenuCompact: View {
    var body: some View {
        AIBackendStatusMenu(compact: true, showModelPicker: false)
    }
}

// MARK: - Preview

#if DEBUG
struct AIBackendStatusMenu_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            AIBackendStatusMenu()
            AIBackendStatusMenu(accentColor: .green)
            AIBackendStatusMenu(compact: true)
        }
        .padding()
    }
}
#endif

//
//  AISettingsView.swift
//  MBox Explorer
//
//  AI settings: the NovaAIKit settings (on/off, backend, model, URLs, Keychain keys, timeout, status, test
//  connection) plus MBox Explorer's own semantic-search embedding settings.
//  Author: Jordan Koch
//  Updated: 2026-11-11 - Chat/summary AI moved to NovaAIKit; embeddings stay app-owned
//

import SwiftUI
import NovaAIKit

struct AISettingsView: View {
    /// Set when the view is shown as a sheet (adds a Done button).
    var onClose: (() -> Void)?

    @ObservedObject private var ai: NovaAI
    @State private var tab = 0

    /// - Parameter ai: the NovaAI to configure; nil = `AppAI.shared` (tests pass their own).
    init(ai: NovaAI? = nil, onClose: (() -> Void)? = nil) {
        self.ai = ai ?? AppAI.shared
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("AI").tag(0)
                Text("Semantic Search").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            if tab == 0 {
                NovaAISettingsView(ai: ai, footer: AppAI.settingsFooter)
            } else {
                EmbeddingSettingsView()
            }

            if let onClose {
                Divider()
                HStack {
                    Spacer()
                    Button("Done", action: onClose).keyboardShortcut(.defaultAction)
                }
                .padding()
            }
        }
        .frame(minWidth: 560, minHeight: 620)
    }
}

/// Embedding provider settings for semantic search (not chat AI; NovaAIKit does not cover embeddings).
struct EmbeddingSettingsView: View {
    @ObservedObject private var embeddingManager = EmbeddingManager.shared

    @State private var tinyChatURL: String = "http://localhost:8000"
    @State private var openWebUIURL: String = "http://localhost:8080"
    @State private var openWebUIKeyDraft: String = ""
    @State private var openWebUIKeyStored = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox(label: Label("Embedding Provider", systemImage: "brain.head.profile")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose how semantic search embeddings are generated. Keyword search always works.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Embedding Provider", selection: $embeddingManager.selectedProvider) {
                            ForEach(EmbeddingProviderType.allCases) { provider in
                                Text(provider.rawValue).tag(provider)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())

                        HStack {
                            Circle()
                                .fill(embeddingManager.isAvailable ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(embeddingManager.statusMessage)
                                .font(.caption)
                                .foregroundColor(embeddingManager.isAvailable ? .green : .orange)
                        }

                        if let setup = embeddingManager.selectedProvider.requiresSetup {
                            Text("Setup: \(setup)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .monospaced()
                        }

                        if let attribution = embeddingManager.selectedProvider.attribution {
                            Text(attribution)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text("The Ollama embedding provider uses the Ollama URL from the AI tab. The OpenAI provider uses the OpenAI key stored there (Keychain).")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                GroupBox(label: Label("TinyChat Embeddings", systemImage: "bubble.left.and.bubble.right")) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Server URL", text: $tinyChatURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit { embeddingManager.tinyChat?.setBaseURL(tinyChatURL) }

                        Button("Save & Test") {
                            embeddingManager.tinyChat?.setBaseURL(tinyChatURL)
                            Task { await embeddingManager.tinyChat?.checkAvailability() }
                        }

                        availability(embeddingManager.tinyChat?.isAvailable == true)
                    }
                    .padding(.vertical, 8)
                }

                GroupBox(label: Label("OpenWebUI Embeddings", systemImage: "globe")) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Server URL", text: $openWebUIURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit { embeddingManager.openWebUI?.setBaseURL(openWebUIURL) }

                        HStack {
                            SecureField(openWebUIKeyStored ? "API key stored in Keychain" : "API Key (optional)", text: $openWebUIKeyDraft)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            Button("Store") {
                                embeddingManager.openWebUI?.setAPIKey(openWebUIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                                openWebUIKeyDraft = ""
                                openWebUIKeyStored = embeddingManager.openWebUI?.hasStoredAPIKey ?? false
                            }
                            .disabled(openWebUIKeyDraft.isEmpty)
                            if openWebUIKeyStored {
                                Button("Remove") {
                                    embeddingManager.openWebUI?.setAPIKey("")
                                    openWebUIKeyStored = false
                                }
                            }
                        }

                        Button("Save & Test") {
                            embeddingManager.openWebUI?.setBaseURL(openWebUIURL)
                            Task { await embeddingManager.openWebUI?.checkAvailability() }
                        }

                        availability(embeddingManager.openWebUI?.isAvailable == true)
                    }
                    .padding(.vertical, 8)
                }

                GroupBox(label: Label("Database", systemImage: "cylinder")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: {
                            NotificationCenter.default.post(name: NSNotification.Name("RegenerateEmbeddings"), object: nil)
                        }) {
                            Label("Regenerate All Embeddings", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        Text("Re-index emails if you change the embedding provider. This will take several minutes for large mailboxes.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding()
        }
        .onAppear {
            tinyChatURL = embeddingManager.tinyChat?.serverURL ?? tinyChatURL
            openWebUIURL = embeddingManager.openWebUI?.serverURL ?? openWebUIURL
            openWebUIKeyStored = embeddingManager.openWebUI?.hasStoredAPIKey ?? false
            Task { await embeddingManager.updateActiveProvider() }
        }
    }

    private func availability(_ ok: Bool) -> some View {
        HStack {
            Circle()
                .fill(ok ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(ok ? "Available" : "Not detected")
                .font(.caption)
                .foregroundColor(ok ? .green : .gray)
        }
    }
}

struct AISettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AISettingsView()
    }
}

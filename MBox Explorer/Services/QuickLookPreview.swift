//
//  QuickLookPreview.swift
//  MBox Explorer
//
//  Quick Look preview support for emails
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import SwiftUI
import QuickLook
import Quartz
import WebKit

// MARK: - Quick Look Preview Provider

class EmailQuickLookProvider: NSObject, QLPreviewPanelDataSource {
    private var previewItems: [URL] = []

    func setEmails(_ emails: [Email]) {
        previewItems = emails.compactMap { email in
            createPreviewFile(for: email)
        }
    }

    func createPreviewFile(for email: Email) -> URL? {
        // Create a temporary HTML file for preview
        let html = generateEmailHTML(email)

        let tempDir = FileManager.default.temporaryDirectory
        let filename = "\(email.id.uuidString).html"
        let fileURL = tempDir.appendingPathComponent(filename)

        do {
            try html.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Failed to create preview: \(error)")
            return nil
        }
    }

    private func generateEmailHTML(_ email: Email) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    margin: 20px;
                    line-height: 1.5;
                    color: #333;
                }
                .header {
                    border-bottom: 1px solid #ddd;
                    padding-bottom: 16px;
                    margin-bottom: 20px;
                }
                .field {
                    margin-bottom: 8px;
                }
                .label {
                    font-weight: 600;
                    color: #666;
                    display: inline-block;
                    width: 60px;
                }
                .subject {
                    font-size: 24px;
                    font-weight: bold;
                    margin-bottom: 16px;
                }
                .body {
                    white-space: pre-wrap;
                }
                .attachment {
                    background: #f5f5f5;
                    padding: 8px 12px;
                    margin-top: 16px;
                    border-radius: 4px;
                }
            </style>
        </head>
        <body>
            <div class="header">
                <div class="subject">\(escapeHTML(email.subject))</div>
                <div class="field"><span class="label">From:</span> \(escapeHTML(email.from))</div>
                <div class="field"><span class="label">To:</span> \(escapeHTML(email.to ?? ""))</div>
                <div class="field"><span class="label">Date:</span> \(escapeHTML(email.date))</div>
            </div>
            <div class="body">\(escapeHTML(email.body))</div>
            \(attachmentsSection(email))
        </body>
        </html>
        """
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func attachmentsSection(_ email: Email) -> String {
        guard let attachments = email.attachments, !attachments.isEmpty else {
            return ""
        }

        let items = attachments.map { "<div>\($0.filename) (\(formatSize($0.size ?? 0)))</div>" }.joined()
        return "<div class=\"attachment\"><strong>Attachments:</strong>\(items)</div>"
    }

    private func formatSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewItems[index] as QLPreviewItem
    }
}

// MARK: - Quick Look View

struct EmailQuickLookView: NSViewRepresentable {
    let email: Email

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView()
        updatePreview(view: view)
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        updatePreview(view: nsView)
    }

    private func updatePreview(view: QLPreviewView) {
        let provider = EmailQuickLookProvider()
        if let item = provider.createPreviewFile(for: email) {
            view.previewItem = item as QLPreviewItem
        }
    }
}

// MARK: - Quick Look Controller

struct QuickLookSheet: View {
    let emails: [Email]
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            // Navigation header
            HStack {
                Button(action: { currentIndex = max(0, currentIndex - 1) }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentIndex == 0)

                Spacer()

                Text("\(currentIndex + 1) of \(emails.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { currentIndex = min(emails.count - 1, currentIndex + 1) }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentIndex >= emails.count - 1)

                Spacer()

                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Preview
            if emails.indices.contains(currentIndex) {
                EmailQuickLookView(email: emails[currentIndex])
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

// MARK: - Thumbnail Generator

class EmailThumbnailGenerator {
    static let shared = EmailThumbnailGenerator()

    func generateThumbnail(for email: Email, size: CGSize) -> NSImage? {
        let provider = EmailQuickLookProvider()
        guard let url = provider.createPreviewFile(for: email) else {
            return nil
        }

        // Use WebKit to render thumbnail
        let webView = WKWebView(frame: CGRect(origin: .zero, size: size))

        // Load the HTML
        let request = URLRequest(url: url)

        var image: NSImage?
        let semaphore = DispatchSemaphore(value: 0)

        webView.load(request)

        // Wait for load and capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let config = WKSnapshotConfiguration()
            config.rect = CGRect(origin: .zero, size: size)

            webView.takeSnapshot(with: config) { snapshot, error in
                image = snapshot
                semaphore.signal()
            }
        }

        semaphore.wait()
        return image
    }
}

// MARK: - Preview Button

struct QuickLookButton: View {
    let email: Email
    @State private var isShowingPreview = false

    var body: some View {
        Button {
            isShowingPreview = true
        } label: {
            Image(systemName: "eye")
        }
        .help("Quick Look")
        .keyboardShortcut(" ", modifiers: [])
        .sheet(isPresented: $isShowingPreview) {
            QuickLookSheet(emails: [email])
        }
    }
}

// MARK: - Multi-Email Preview

struct MultiEmailPreviewButton: View {
    let emails: [Email]
    @State private var isShowingPreview = false

    var body: some View {
        Button {
            isShowingPreview = true
        } label: {
            HStack {
                Image(systemName: "eye")
                Text("Preview (\(emails.count))")
            }
        }
        .disabled(emails.isEmpty)
        .sheet(isPresented: $isShowingPreview) {
            QuickLookSheet(emails: emails)
        }
    }
}

// MARK: - Preview Panel Integration

class QuickLookPanelController: NSObject {
    static let shared = QuickLookPanelController()

    private var provider = EmailQuickLookProvider()

    func showPanel(for emails: [Email]) {
        provider.setEmails(emails)

        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = provider
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hidePanel() {
        QLPreviewPanel.shared()?.close()
    }

    func togglePanel(for emails: [Email]) {
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.close()
        } else {
            showPanel(for: emails)
        }
    }
}

#Preview {
    QuickLookButton(email: Email(
        id: UUID(),
        from: "test@example.com",
        to: "you@example.com",
        subject: "Test Email",
        date: "Jan 30, 2026",
        body: "This is a test email body."
    ))
}

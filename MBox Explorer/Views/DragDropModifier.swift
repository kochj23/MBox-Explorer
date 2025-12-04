//
//  DragDropModifier.swift
//  MBox Explorer
//
//  Drag and drop support for files and emails
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drop Modifier for File Import

struct FileDropModifier: ViewModifier {
    let onDrop: (URL) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }

                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url {
                        // Verify it's an MBOX file
                        let ext = url.pathExtension.lowercased()
                        if ext == "mbox" || ext == "" || ext == "mbx" {
                            DispatchQueue.main.async {
                                onDrop(url)
                            }
                        }
                    }
                }

                return true
            }
            .overlay(
                Group {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 3)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue.opacity(0.1))
                            )
                            .overlay(
                                VStack(spacing: 12) {
                                    Image(systemName: "arrow.down.doc.fill")
                                        .font(.system(size: 60))
                                        .foregroundColor(.blue)

                                    Text("Drop MBOX file to open")
                                        .font(.title2)
                                        .bold()
                                        .foregroundColor(.blue)
                                }
                            )
                    }
                }
            )
    }
}

extension View {
    func fileDropTarget(onDrop: @escaping (URL) -> Void) -> some View {
        modifier(FileDropModifier(onDrop: onDrop))
    }
}

// MARK: - Draggable Email Item

struct DraggableEmailItem: View {
    let email: Email
    let content: AnyView

    var body: some View {
        content
            .onDrag {
                // Create a temporary file for the email
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(email.safeFilename).txt")

                let emailContent = """
                From: \(email.from)
                To: \(email.to ?? "")
                Subject: \(email.subject)
                Date: \(email.displayDate)

                \(email.cleanBody)
                """

                try? emailContent.write(to: tempURL, atomically: true, encoding: .utf8)

                return NSItemProvider(object: tempURL as NSURL)
            }
    }
}

// MARK: - Email Row with Drag Support

struct DraggableEmailRow: View {
    let email: Email
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        DraggableEmailItem(email: email, content: AnyView(
            Button {
                onSelect()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(email.subject)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Text(email.from)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            if email.hasAttachments {
                                Image(systemName: "paperclip")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Text(email.displayDate)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        ))
    }
}

// MARK: - Batch Email Export via Drag

struct BatchEmailDragView: View {
    let emails: [Email]
    let label: String

    var body: some View {
        Text(label)
            .onDrag {
                // Create a temporary directory with all emails
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("MBoxExport_\(UUID().uuidString)")

                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                for (index, email) in emails.enumerated() {
                    let filename = "\(String(format: "%04d", index + 1))_\(email.safeFilename).txt"
                    let fileURL = tempDir.appendingPathComponent(filename)

                    let content = """
                    From: \(email.from)
                    To: \(email.to ?? "")
                    Subject: \(email.subject)
                    Date: \(email.displayDate)

                    \(email.cleanBody)
                    """

                    try? content.write(to: fileURL, atomically: true, encoding: .utf8)
                }

                return NSItemProvider(object: tempDir as NSURL)
            }
    }
}

// MARK: - Drop Zone View

struct DropZoneView: View {
    let onDrop: (URL) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 80))
                .foregroundColor(.blue.opacity(0.6))

            VStack(spacing: 8) {
                Text("Drop an MBOX file here")
                    .font(.title2)
                    .bold()

                Text("or use File > Open to browse")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button("Browse Files") {
                NotificationCenter.default.post(name: .openMboxFile, object: nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .fileDropTarget(onDrop: onDrop)
    }
}

// MARK: - Drag Preview

struct EmailDragPreview: View {
    let email: Email
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: count > 1 ? "envelope.badge.fill" : "envelope.fill")
                .font(.title)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                if count > 1 {
                    Text("\(count) emails")
                        .font(.headline)
                } else {
                    Text(email.subject)
                        .font(.headline)
                        .lineLimit(1)

                    Text(email.from)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 5)
        .frame(width: 300)
    }
}

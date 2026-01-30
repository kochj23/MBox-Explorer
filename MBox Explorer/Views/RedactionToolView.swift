//
//  RedactionToolView.swift
//  MBox Explorer
//
//  PII detection and redaction interface
//

import SwiftUI

struct RedactionToolView: View {
    @ObservedObject var viewModel: MboxViewModel
    @Binding var isPresented: Bool
    @State private var redactionOptions = PIIRedactor.RedactionOptions()
    @State private var scanResults: [Email: PIIRedactor.RedactionResult] = [:]
    @State private var isScanning = false
    @State private var scanProgress: Double = 0.0
    @State private var totalDetections = 0
    @State private var showingPreview = false
    @State private var previewEmail: Email?
    @State private var selectedTab: Tab = .configure

    enum Tab: String, CaseIterable {
        case configure = "Configure"
        case scan = "Scan Results"
        case redact = "Redact"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("PII Redaction Tool")
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

            // Tab selector
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider()

            // Content
            Group {
                switch selectedTab {
                case .configure:
                    ConfigureTabView(options: $redactionOptions)
                case .scan:
                    ScanResultsTabView(
                        viewModel: viewModel,
                        scanResults: $scanResults,
                        isScanning: $isScanning,
                        scanProgress: $scanProgress,
                        totalDetections: $totalDetections,
                        options: $redactionOptions,
                        showingPreview: $showingPreview,
                        previewEmail: $previewEmail
                    )
                case .redact:
                    RedactTabView(viewModel: viewModel, options: redactionOptions)
                }
            }
        }
        .frame(width: 750, height: 650)
        .sheet(isPresented: $showingPreview) {
            if let email = previewEmail {
                RedactionPreviewView(
                    email: email,
                    options: redactionOptions,
                    isPresented: $showingPreview
                )
            }
        }
    }
}

// MARK: - Configure Tab

struct ConfigureTabView: View {
    @Binding var options: PIIRedactor.RedactionOptions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Select PII Types to Detect")
                    .font(.headline)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(PIIRedactor.PIIType.allCases) { type in
                        PIITypeToggle(
                            type: type,
                            isEnabled: Binding(
                                get: { options.enabledTypes.contains(type) },
                                set: { enabled in
                                    if enabled {
                                        options.enabledTypes.insert(type)
                                    } else {
                                        options.enabledTypes.remove(type)
                                    }
                                }
                            )
                        )
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Redaction Options")
                        .font(.headline)

                    Toggle("Partial Redaction", isOn: $options.partialRedaction)
                        .toggleStyle(.switch)

                    Text("When enabled, shows partial information (e.g., last 4 digits of SSN)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Examples")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        ExampleRow(
                            label: "SSN",
                            original: "123-45-6789",
                            full: "[SSN-REDACTED]",
                            partial: "***-**-6789"
                        )
                        ExampleRow(
                            label: "Credit Card",
                            original: "4111 1111 1111 1234",
                            full: "[CARD-REDACTED]",
                            partial: "**** **** **** 1234"
                        )
                        ExampleRow(
                            label: "Phone",
                            original: "(555) 123-4567",
                            full: "[PHONE-REDACTED]",
                            partial: "***-***-4567"
                        )
                        ExampleRow(
                            label: "Email",
                            original: "john@example.com",
                            full: "[EMAIL-REDACTED]",
                            partial: "j***@example.com"
                        )
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                Divider()

                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Important Notice")
                            .font(.caption)
                            .bold()
                        Text("Automated redaction may miss some PII or produce false positives. Always review redacted content before sharing.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
        }
    }
}

struct PIITypeToggle: View {
    let type: PIIRedactor.PIIType
    @Binding var isEnabled: Bool

    var body: some View {
        Toggle(isOn: $isEnabled) {
            HStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 30)

                Text(type.rawValue)
                    .font(.subheadline)
            }
        }
        .toggleStyle(.checkbox)
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct ExampleRow: View {
    let label: String
    let original: String
    let full: String
    let partial: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption)
                .bold()
                .frame(width: 80, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text("Original: \(original)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Full: \(full)")
                    .font(.caption2)
                    .foregroundColor(.red)
                Text("Partial: \(partial)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Scan Results Tab

struct ScanResultsTabView: View {
    @ObservedObject var viewModel: MboxViewModel
    @Binding var scanResults: [Email: PIIRedactor.RedactionResult]
    @Binding var isScanning: Bool
    @Binding var scanProgress: Double
    @Binding var totalDetections: Int
    @Binding var options: PIIRedactor.RedactionOptions
    @Binding var showingPreview: Bool
    @Binding var previewEmail: Email?

    var body: some View {
        VStack(spacing: 0) {
            if scanResults.isEmpty && !isScanning {
                ContentUnavailableView(
                    "No Scan Results",
                    systemImage: "magnifyingglass",
                    description: Text("Click 'Scan Emails' to detect PII in your emails")
                )
                .frame(maxHeight: .infinity)

                Divider()

                HStack {
                    Spacer()

                    Button("Scan Emails") {
                        scanEmails()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if isScanning {
                VStack(spacing: 20) {
                    ProgressView(value: scanProgress) {
                        Text("Scanning emails for PII...")
                    }
                    .frame(width: 300)

                    Text("\(Int(scanProgress * 100))% complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                // Results
                VStack(spacing: 0) {
                    // Summary
                    HStack(spacing: 20) {
                        RedactionStatBadge(
                            icon: "envelope",
                            label: "Emails Scanned",
                            value: "\(viewModel.emails.count)"
                        )

                        RedactionStatBadge(
                            icon: "exclamationmark.triangle.fill",
                            label: "PII Detected",
                            value: "\(totalDetections)",
                            color: .orange
                        )

                        RedactionStatBadge(
                            icon: "checkmark.shield.fill",
                            label: "Clean Emails",
                            value: "\(viewModel.emails.count - scanResults.count)",
                            color: .green
                        )
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // List of emails with PII
                    List {
                        ForEach(viewModel.emails.filter { scanResults[$0] != nil }) { email in
                            Button {
                                previewEmail = email
                                showingPreview = true
                            } label: {
                                if let result = scanResults[email] {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(email.subject)
                                                .font(.headline)
                                                .lineLimit(1)

                                            Text(email.from)
                                                .font(.caption)
                                                .foregroundColor(.secondary)

                                            HStack(spacing: 8) {
                                                Label("\(result.redactionCount) detections", systemImage: "exclamationmark.triangle")
                                                    .font(.caption2)
                                                    .foregroundColor(.orange)

                                                let types = Set(result.detections.map { $0.type })
                                                ForEach(Array(types).prefix(3), id: \.self) { type in
                                                    Image(systemName: type.icon)
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    Button("Clear Results") {
                        scanResults.removeAll()
                        totalDetections = 0
                    }

                    Spacer()

                    Button("Rescan") {
                        scanEmails()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
    }

    private func scanEmails() {
        isScanning = true
        scanProgress = 0.0
        scanResults.removeAll()
        totalDetections = 0

        Task {
            let emails = viewModel.emails
            let total = Double(emails.count)

            for (index, email) in emails.enumerated() {
                let result = PIIRedactor.redactPII(in: "\(email.subject) \(email.body) \(email.from) \(email.to ?? "")", options: options)

                if !result.detections.isEmpty {
                    await MainActor.run {
                        scanResults[email] = result
                        totalDetections += result.redactionCount
                    }
                }

                await MainActor.run {
                    scanProgress = Double(index + 1) / total
                }

                // Small delay to prevent UI freeze
                try? await Task.sleep(nanoseconds: 1_000_000)
            }

            await MainActor.run {
                isScanning = false
            }
        }
    }
}

struct RedactionStatBadge: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = .blue

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .bold()
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Redact Tab

struct RedactTabView: View {
    @ObservedObject var viewModel: MboxViewModel
    let options: PIIRedactor.RedactionOptions
    @State private var isRedacting = false
    @State private var showingExportPicker = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("Ready to Redact")
                .font(.title)
                .bold()

            Text("This will create redacted copies of your emails with PII removed or masked according to your settings.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "envelope")
                    Text("\(viewModel.emails.count) emails will be redacted")
                }

                HStack {
                    Image(systemName: "shield.checkered")
                    Text("\(options.enabledTypes.count) PII types enabled")
                }

                HStack {
                    Image(systemName: options.partialRedaction ? "eye.slash" : "eye.slash.fill")
                    Text(options.partialRedaction ? "Partial redaction" : "Full redaction")
                }
            }
            .font(.subheadline)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Spacer()
        }
        .padding()
        .frame(maxHeight: .infinity)

        Divider()

        HStack(spacing: 12) {
            Spacer()

            Button("Export Redacted Emails") {
                showingExportPicker = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .fileExporter(
            isPresented: $showingExportPicker,
            document: RedactedEmailsDocument(emails: viewModel.emails, options: options),
            contentType: .plainText,
            defaultFilename: "redacted_emails"
        ) { result in
            switch result {
            case .success(let url):
                print("Exported redacted emails to: \(url)")
            case .failure(let error):
                print("Export failed: \(error)")
            }
        }
    }
}

// MARK: - Preview View

struct RedactionPreviewView: View {
    let email: Email
    let options: PIIRedactor.RedactionOptions
    @Binding var isPresented: Bool
    @State private var showOriginal = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Redaction Preview")
                    .font(.title2)
                    .bold()

                Spacer()

                Toggle("Show Original", isOn: $showOriginal)
                    .toggleStyle(.switch)

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
                VStack(alignment: .leading, spacing: 16) {
                    let result = PIIRedactor.redactPII(in: email.body, options: options)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Subject")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(showOriginal ? email.subject : PIIRedactor.redactPII(in: email.subject, options: options).redactedText)
                            .font(.headline)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("From")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(showOriginal ? email.from : PIIRedactor.redactPII(in: email.from, options: options).redactedText)
                            .font(.body)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Body")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            if !showOriginal {
                                Label("\(result.redactionCount) redactions", systemImage: "checkmark.shield")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }

                        Text(showOriginal ? email.body : result.redactedText)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - Document for Export

import UniformTypeIdentifiers

struct RedactedEmailsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    let emails: [Email]
    let options: PIIRedactor.RedactionOptions

    init(emails: [Email], options: PIIRedactor.RedactionOptions) {
        self.emails = emails
        self.options = options
    }

    init(configuration: ReadConfiguration) throws {
        self.emails = []
        self.options = PIIRedactor.RedactionOptions()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var output = ""

        for email in emails {
            let redactedEmail = PIIRedactor.redactEmail(email, options: options)

            output += "From: \(redactedEmail.from)\n"
            output += "Subject: \(redactedEmail.subject)\n"
            output += "Date: \(redactedEmail.displayDate)\n"
            output += "\n"
            output += redactedEmail.body
            output += "\n\n" + String(repeating: "=", count: 80) + "\n\n"
        }

        let data = output.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}

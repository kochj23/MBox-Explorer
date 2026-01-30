//
//  ContactExporter.swift
//  MBox Explorer
//
//  Export email contacts to vCard or CSV format
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation
import Contacts
import SwiftUI

class ContactExporter: ObservableObject {
    static let shared = ContactExporter()

    @Published var isExporting = false
    @Published var extractedContacts: [ExtractedContact] = []
    @Published var progress: Double = 0

    private let contactStore = CNContactStore()

    // MARK: - Extract Contacts

    func extractContacts(from emails: [Email]) async -> [ExtractedContact] {
        await MainActor.run {
            isExporting = true
            progress = 0
            extractedContacts = []
        }

        defer {
            Task { @MainActor in
                isExporting = false
            }
        }

        var contactDict: [String: ExtractedContact] = [:]

        for (index, email) in emails.enumerated() {
            // Extract from sender
            processAddress(email.from, into: &contactDict, role: .sender)

            // Extract from recipient
            if let to = email.to {
                processAddress(to, into: &contactDict, role: .recipient)
            }

            let progressValue = Double(index + 1) / Double(emails.count)
            await MainActor.run {
                self.progress = progressValue
            }
        }

        let contacts = Array(contactDict.values).sorted { $0.emailCount > $1.emailCount }

        await MainActor.run {
            extractedContacts = contacts
        }

        return contacts
    }

    private func processAddress(_ address: String, into dict: inout [String: ExtractedContact], role: ContactRole) {
        let email = extractEmail(from: address)
        let name = extractName(from: address)

        guard !email.isEmpty else { return }

        let normalizedEmail = email.lowercased()

        if var existing = dict[normalizedEmail] {
            existing.emailCount += 1
            if role == .sender {
                existing.sentCount += 1
            } else {
                existing.receivedCount += 1
            }
            // Update name if we have a better one
            if existing.name.isEmpty && !name.isEmpty {
                existing.name = name
            }
            dict[normalizedEmail] = existing
        } else {
            let contact = ExtractedContact(
                email: email,
                name: name,
                emailCount: 1,
                sentCount: role == .sender ? 1 : 0,
                receivedCount: role == .recipient ? 1 : 0
            )
            dict[normalizedEmail] = contact
        }
    }

    private func extractEmail(from address: String) -> String {
        if let startRange = address.range(of: "<"),
           let endRange = address.range(of: ">") {
            return String(address[startRange.upperBound..<endRange.lowerBound])
        }

        // Check if it's just an email
        if address.contains("@") && !address.contains(" ") {
            return address
        }

        return ""
    }

    private func extractName(from address: String) -> String {
        if let range = address.range(of: "<") {
            let name = String(address[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            // Remove surrounding quotes if present
            if name.hasPrefix("\"") && name.hasSuffix("\"") {
                return String(name.dropFirst().dropLast())
            }
            return name
        }
        return ""
    }

    // MARK: - Export to vCard

    func exportToVCard(_ contacts: [ExtractedContact]) -> String {
        var vcf = ""

        for contact in contacts {
            vcf += "BEGIN:VCARD\n"
            vcf += "VERSION:3.0\n"

            if !contact.name.isEmpty {
                let nameParts = contact.name.components(separatedBy: " ")
                if nameParts.count >= 2 {
                    let lastName = nameParts.last ?? ""
                    let firstName = nameParts.dropLast().joined(separator: " ")
                    vcf += "N:\(lastName);\(firstName);;;\n"
                    vcf += "FN:\(contact.name)\n"
                } else {
                    vcf += "N:\(contact.name);;;;\n"
                    vcf += "FN:\(contact.name)\n"
                }
            } else {
                let username = contact.email.split(separator: "@").first ?? ""
                vcf += "FN:\(username)\n"
            }

            vcf += "EMAIL:\(contact.email)\n"
            vcf += "NOTE:Extracted from MBox - \(contact.emailCount) emails\n"
            vcf += "END:VCARD\n\n"
        }

        return vcf
    }

    // MARK: - Export to CSV

    func exportToCSV(_ contacts: [ExtractedContact]) -> String {
        var csv = "Name,Email,Total Emails,Sent,Received,Domain\n"

        for contact in contacts {
            let domain = contact.email.split(separator: "@").last ?? ""
            let escapedName = contact.name.replacingOccurrences(of: "\"", with: "\"\"")

            let row = [
                "\"\(escapedName)\"",
                contact.email,
                "\(contact.emailCount)",
                "\(contact.sentCount)",
                "\(contact.receivedCount)",
                String(domain)
            ].joined(separator: ",")

            csv += row + "\n"
        }

        return csv
    }

    // MARK: - Export to Address Book

    func requestContactsAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            contactStore.requestAccess(for: .contacts) { granted, error in
                if let error = error {
                    print("Contacts access error: \(error.localizedDescription)")
                }
                continuation.resume(returning: granted)
            }
        }
    }

    func exportToAddressBook(_ contacts: [ExtractedContact]) async throws -> Int {
        let hasAccess = await requestContactsAccess()
        guard hasAccess else {
            throw ContactExportError.accessDenied
        }

        var addedCount = 0

        for contact in contacts {
            // Check if contact already exists
            let predicate = CNContact.predicateForContacts(matchingEmailAddress: contact.email)
            let existingContacts = try? contactStore.unifiedContacts(matching: predicate, keysToFetch: [CNContactEmailAddressesKey as CNKeyDescriptor])

            if existingContacts?.isEmpty == true {
                let newContact = CNMutableContact()

                if !contact.name.isEmpty {
                    let nameParts = contact.name.components(separatedBy: " ")
                    if nameParts.count >= 2 {
                        newContact.givenName = nameParts.dropLast().joined(separator: " ")
                        newContact.familyName = nameParts.last ?? ""
                    } else {
                        newContact.givenName = contact.name
                    }
                }

                newContact.emailAddresses = [
                    CNLabeledValue(label: CNLabelWork, value: contact.email as NSString)
                ]

                newContact.note = "Imported from MBox Explorer - \(contact.emailCount) emails"

                let saveRequest = CNSaveRequest()
                saveRequest.add(newContact, toContainerWithIdentifier: nil)

                do {
                    try contactStore.execute(saveRequest)
                    addedCount += 1
                } catch {
                    print("Failed to save contact: \(error.localizedDescription)")
                }
            }
        }

        return addedCount
    }

    // MARK: - Statistics

    func getContactStats(_ contacts: [ExtractedContact]) -> ContactStats {
        let totalContacts = contacts.count
        let uniqueDomains = Set(contacts.compactMap { $0.email.split(separator: "@").last.map(String.init) }).count
        let totalEmails = contacts.reduce(0) { $0 + $1.emailCount }

        let topDomains = Dictionary(grouping: contacts) { contact -> String in
            String(contact.email.split(separator: "@").last ?? "")
        }
        .map { (domain: $0.key, count: $0.value.count) }
        .sorted { $0.count > $1.count }
        .prefix(10)
        .map { DomainCount(domain: $0.domain, count: $0.count) }

        return ContactStats(
            totalContacts: totalContacts,
            uniqueDomains: uniqueDomains,
            totalEmails: totalEmails,
            topDomains: topDomains
        )
    }
}

// MARK: - Models

struct ExtractedContact: Identifiable, Hashable {
    let id = UUID()
    var email: String
    var name: String
    var emailCount: Int
    var sentCount: Int
    var receivedCount: Int

    var domain: String {
        String(email.split(separator: "@").last ?? "")
    }
}

enum ContactRole {
    case sender
    case recipient
}

struct ContactStats {
    let totalContacts: Int
    let uniqueDomains: Int
    let totalEmails: Int
    let topDomains: [DomainCount]
}

struct DomainCount: Identifiable {
    let id = UUID()
    let domain: String
    let count: Int
}

enum ContactExportError: Error, LocalizedError {
    case accessDenied
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Contacts access denied. Please grant permission in System Preferences."
        case .exportFailed:
            return "Failed to export contacts."
        }
    }
}

// MARK: - Contact Exporter View

struct ContactExporterView: View {
    @ObservedObject var viewModel: MboxViewModel
    @StateObject private var exporter = ContactExporter.shared
    @State private var selectedContacts: Set<UUID> = []
    @State private var searchText = ""
    @State private var showingExportOptions = false
    @State private var exportResult: String?

    var filteredContacts: [ExtractedContact] {
        if searchText.isEmpty {
            return exporter.extractedContacts
        }
        let query = searchText.lowercased()
        return exporter.extractedContacts.filter {
            $0.name.lowercased().contains(query) ||
            $0.email.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Contact Export")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if exporter.isExporting {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("\(Int(exporter.progress * 100))%")
                        .foregroundColor(.secondary)
                } else if exporter.extractedContacts.isEmpty {
                    Button("Extract Contacts") {
                        Task {
                            await exporter.extractContacts(from: viewModel.emails)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    HStack(spacing: 12) {
                        Button("Select All") {
                            selectedContacts = Set(exporter.extractedContacts.map(\.id))
                        }

                        Button("Export") {
                            showingExportOptions = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedContacts.isEmpty)
                    }
                }
            }
            .padding()

            if let result = exportResult {
                Text(result)
                    .padding()
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }

            // Stats
            if !exporter.extractedContacts.isEmpty {
                let stats = exporter.getContactStats(exporter.extractedContacts)
                HStack(spacing: 20) {
                    StatItem(title: "Contacts", value: "\(stats.totalContacts)")
                    StatItem(title: "Domains", value: "\(stats.uniqueDomains)")
                    StatItem(title: "Emails", value: "\(stats.totalEmails)")
                }
                .padding()
            }

            Divider()

            // Search
            if !exporter.extractedContacts.isEmpty {
                TextField("Search contacts...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding()
            }

            // Contact list
            List(filteredContacts, selection: $selectedContacts) { contact in
                ContactRow(contact: contact)
            }
        }
        .sheet(isPresented: $showingExportOptions) {
            ContactExportOptionsView(
                contacts: exporter.extractedContacts.filter { selectedContacts.contains($0.id) },
                exporter: exporter,
                result: $exportResult,
                isPresented: $showingExportOptions
            )
        }
    }
}

struct StatItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct ContactRow: View {
    let contact: ExtractedContact

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if !contact.name.isEmpty {
                    Text(contact.name)
                        .fontWeight(.medium)
                }
                Text(contact.email)
                    .font(.caption)
                    .foregroundColor(contact.name.isEmpty ? .primary : .secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(contact.emailCount) emails")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Label("\(contact.sentCount)", systemImage: "arrow.up.circle")
                    Label("\(contact.receivedCount)", systemImage: "arrow.down.circle")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }
}

struct ContactExportOptionsView: View {
    let contacts: [ExtractedContact]
    let exporter: ContactExporter
    @Binding var result: String?
    @Binding var isPresented: Bool

    @State private var exportFormat: ContactExportFormat = .vcard
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Export \(contacts.count) Contacts")
                .font(.headline)

            Picker("Format", selection: $exportFormat) {
                Text("vCard (.vcf)").tag(ContactExportFormat.vcard)
                Text("CSV").tag(ContactExportFormat.csv)
                Text("Add to Contacts").tag(ContactExportFormat.addressBook)
            }
            .pickerStyle(.radioGroup)

            Text(exportFormat.description)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }

                Spacer()

                Button("Export") {
                    performExport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
            }
        }
        .padding()
        .frame(width: 350)
    }

    private func performExport() {
        isExporting = true

        switch exportFormat {
        case .vcard:
            let vcf = exporter.exportToVCard(contacts)
            saveFile(content: vcf, filename: "contacts.vcf")

        case .csv:
            let csv = exporter.exportToCSV(contacts)
            saveFile(content: csv, filename: "contacts.csv")

        case .addressBook:
            Task {
                do {
                    let count = try await exporter.exportToAddressBook(contacts)
                    await MainActor.run {
                        result = "Added \(count) contacts to Address Book"
                        isPresented = false
                    }
                } catch {
                    await MainActor.run {
                        result = "Error: \(error.localizedDescription)"
                        isPresented = false
                    }
                }
                await MainActor.run {
                    isExporting = false
                }
            }
        }
    }

    private func saveFile(content: String, filename: String) {
        let panel = NSSavePanel()
        panel.title = "Save Contacts"
        panel.nameFieldStringValue = filename

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                isExporting = false
                return
            }

            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                result = "Exported to \(url.lastPathComponent)"
            } catch {
                result = "Error: \(error.localizedDescription)"
            }

            isExporting = false
            isPresented = false
        }
    }
}

enum ContactExportFormat {
    case vcard
    case csv
    case addressBook

    var description: String {
        switch self {
        case .vcard:
            return "Standard format compatible with most email and contact apps"
        case .csv:
            return "Spreadsheet format for analysis and import into other systems"
        case .addressBook:
            return "Add directly to macOS Contacts app"
        }
    }
}

#Preview {
    ContactExporterView(viewModel: MboxViewModel())
}

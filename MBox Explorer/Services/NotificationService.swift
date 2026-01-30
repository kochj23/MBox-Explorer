//
//  NotificationService.swift
//  MBox Explorer
//
//  Notification Center integration for alerts and reminders
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation
import UserNotifications
import SwiftUI

class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published var isAuthorized = false
    @Published var pendingNotifications: [UNNotificationRequest] = []

    private let center = UNUserNotificationCenter.current()

    init() {
        checkAuthorization()
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                isAuthorized = granted
            }
            return granted
        } catch {
            print("Notification authorization error: \(error.localizedDescription)")
            return false
        }
    }

    func checkAuthorization() {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Send Notifications

    /// Send immediate notification
    func sendNotification(
        title: String,
        body: String,
        identifier: String = UUID().uuidString,
        userInfo: [AnyHashable: Any] = [:]
    ) async throws {
        if !isAuthorized {
            let granted = await requestAuthorization()
            guard granted else { return }
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        try await center.add(request)
    }

    /// Schedule notification for later
    func scheduleNotification(
        title: String,
        body: String,
        at date: Date,
        identifier: String = UUID().uuidString,
        userInfo: [AnyHashable: Any] = [:]
    ) async throws {
        if !isAuthorized {
            let granted = await requestAuthorization()
            guard granted else { return }
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        try await center.add(request)

        await refreshPendingNotifications()
    }

    /// Schedule reminder for action item
    func scheduleActionReminder(for actionItem: ActionItem) async throws {
        guard let deadline = actionItem.deadline else { return }

        // Schedule 1 day before deadline
        let reminderDate = Calendar.current.date(byAdding: .day, value: -1, to: deadline) ?? deadline

        try await scheduleNotification(
            title: "Action Item Reminder",
            body: actionItem.description,
            at: reminderDate,
            identifier: "action-\(actionItem.id.uuidString)",
            userInfo: [
                "type": "actionItem",
                "emailId": actionItem.sourceEmailId.uuidString
            ]
        )
    }

    /// Schedule reminder for extracted event
    func scheduleEventReminder(for event: ExtractedEvent, minutesBefore: Int = 30) async throws {
        guard let startDate = event.startDate else { return }

        let reminderDate = Calendar.current.date(byAdding: .minute, value: -minutesBefore, to: startDate) ?? startDate

        try await scheduleNotification(
            title: "Upcoming: \(event.title)",
            body: event.location ?? "Meeting starting soon",
            at: reminderDate,
            identifier: "event-\(event.id.uuidString)",
            userInfo: [
                "type": "event",
                "emailId": event.sourceEmailId.uuidString
            ]
        )
    }

    // MARK: - Manage Notifications

    func refreshPendingNotifications() async {
        let requests = await center.pendingNotificationRequests()
        await MainActor.run {
            pendingNotifications = requests
        }
    }

    func cancelNotification(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        Task {
            await refreshPendingNotifications()
        }
    }

    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
        Task {
            await refreshPendingNotifications()
        }
    }

    // MARK: - Notification Types

    func notifyImportComplete(emailCount: Int, filename: String) async {
        try? await sendNotification(
            title: "Import Complete",
            body: "Imported \(emailCount) emails from \(filename)",
            userInfo: ["type": "import"]
        )
    }

    func notifyExportComplete(filename: String) async {
        try? await sendNotification(
            title: "Export Complete",
            body: "Exported to \(filename)",
            userInfo: ["type": "export"]
        )
    }

    func notifyIndexingComplete(emailCount: Int) async {
        try? await sendNotification(
            title: "Indexing Complete",
            body: "\(emailCount) emails indexed for search",
            userInfo: ["type": "indexing"]
        )
    }

    func notifyAIAnalysisComplete(feature: String) async {
        try? await sendNotification(
            title: "Analysis Complete",
            body: "\(feature) finished processing",
            userInfo: ["type": "ai"]
        )
    }

    func notifyThreatDetected(threatCount: Int) async {
        try? await sendNotification(
            title: "Security Alert",
            body: "Found \(threatCount) potential threat(s) in emails",
            userInfo: ["type": "threat"]
        )
    }
}

// MARK: - Settings View

struct NotificationSettingsView: View {
    @ObservedObject var service = NotificationService.shared
    @State private var enableImportNotifications = true
    @State private var enableExportNotifications = true
    @State private var enableReminderNotifications = true
    @State private var enableSecurityNotifications = true
    @State private var reminderMinutesBefore = 30

    var body: some View {
        Form {
            Section {
                if service.isAuthorized {
                    Label("Notifications Enabled", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    HStack {
                        Label("Notifications Disabled", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)

                        Spacer()

                        Button("Enable") {
                            Task {
                                await service.requestAuthorization()
                            }
                        }
                    }
                }
            } header: {
                Text("Status")
            }

            Section {
                Toggle("Import Complete", isOn: $enableImportNotifications)
                Toggle("Export Complete", isOn: $enableExportNotifications)
                Toggle("Reminders", isOn: $enableReminderNotifications)
                Toggle("Security Alerts", isOn: $enableSecurityNotifications)
            } header: {
                Text("Notification Types")
            }

            Section {
                Picker("Remind Before Events", selection: $reminderMinutesBefore) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("1 day").tag(1440)
                }
            } header: {
                Text("Timing")
            }

            Section {
                HStack {
                    Text("Pending Notifications")
                    Spacer()
                    Text("\(service.pendingNotifications.count)")
                        .foregroundColor(.secondary)
                }

                if !service.pendingNotifications.isEmpty {
                    Button("Clear All Scheduled", role: .destructive) {
                        service.cancelAllNotifications()
                    }
                }
            } header: {
                Text("Scheduled")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            Task {
                await service.refreshPendingNotifications()
            }
        }
    }
}

// MARK: - Pending Notifications View

struct PendingNotificationsView: View {
    @ObservedObject var service = NotificationService.shared

    var body: some View {
        List {
            ForEach(service.pendingNotifications, id: \.identifier) { request in
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.content.title)
                        .fontWeight(.medium)

                    Text(request.content.body)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let trigger = request.trigger as? UNCalendarNotificationTrigger,
                       let nextDate = trigger.nextTriggerDate() {
                        Text("Scheduled: \(nextDate, style: .relative)")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        service.cancelNotification(identifier: request.identifier)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            if service.pendingNotifications.isEmpty {
                Text("No scheduled notifications")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            Task {
                await service.refreshPendingNotifications()
            }
        }
    }
}

#Preview {
    NotificationSettingsView()
}

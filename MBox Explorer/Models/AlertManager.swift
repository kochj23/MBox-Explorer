//
//  AlertManager.swift
//  MBox Explorer
//
//  Error and alert management
//

import Foundation
import SwiftUI

class AlertManager: ObservableObject {
    @Published var showingAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var alertType: AlertType = .error
    @Published var showDetails = false
    @Published var detailsText = ""

    enum AlertType {
        case error
        case warning
        case success
        case info
    }

    func showError(_ title: String, message: String, details: String? = nil) {
        alertTitle = title
        alertMessage = message
        alertType = .error
        detailsText = details ?? ""
        showingAlert = true
    }

    func showSuccess(_ title: String, message: String) {
        alertTitle = title
        alertMessage = message
        alertType = .success
        showingAlert = true
    }

    func showWarning(_ title: String, message: String) {
        alertTitle = title
        alertMessage = message
        alertType = .warning
        showingAlert = true
    }

    func showInfo(_ title: String, message: String) {
        alertTitle = title
        alertMessage = message
        alertType = .info
        showingAlert = true
    }
}

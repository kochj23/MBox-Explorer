//
//  ProgressView.swift
//  MBox Explorer
//
//  Progress indicator with cancellation support
//

import SwiftUI

struct ProgressSheet: View {
    @ObservedObject var viewModel: MboxViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Progress indicator
            ProgressView(value: viewModel.parser.progress) {
                Text(viewModel.parser.status)
                    .font(.headline)
            } currentValueLabel: {
                Text("\(Int(viewModel.parser.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .progressViewStyle(.linear)
            .frame(width: 300)

            // Estimated time
            if viewModel.parser.progress > 0.1 {
                Text(estimatedTimeRemaining)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Cancel button
            Button("Cancel") {
                viewModel.parser.cancel()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(30)
        .frame(minWidth: 400, minHeight: 150)
    }

    private var estimatedTimeRemaining: String {
        guard viewModel.parser.progress > 0 else { return "" }

        let elapsed = Date().timeIntervalSince(viewModel.loadStartTime ?? Date())
        let totalEstimated = elapsed / viewModel.parser.progress
        let remaining = totalEstimated - elapsed

        if remaining < 60 {
            return "About \(Int(remaining)) seconds remaining"
        } else {
            let minutes = Int(remaining / 60)
            return "About \(minutes) minute\(minutes == 1 ? "" : "s") remaining"
        }
    }
}

struct ExportProgressSheet: View {
    @ObservedObject var viewModel: MboxViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Progress indicator
            ProgressView(value: viewModel.exporter.progress) {
                Text(viewModel.exporter.status)
                    .font(.headline)
            } currentValueLabel: {
                Text("\(Int(viewModel.exporter.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .progressViewStyle(.linear)
            .frame(width: 300)

            // Current file being exported
            if !viewModel.exporter.status.isEmpty {
                Text(viewModel.exporter.status)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Cancel button
            Button("Cancel") {
                viewModel.exporter.cancel()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(30)
        .frame(minWidth: 400, minHeight: 150)
    }
}

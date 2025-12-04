//
//  LocalLLM.swift
//  MBox Explorer
//
//  Local LLM integration using Python MLX
//  Author: Jordan Koch
//  Date: 2025-12-03
//

import Foundation

/// Local LLM manager using MLX for email queries
class LocalLLM: ObservableObject {
    @Published var isAvailable = false
    @Published var isProcessing = false
    @Published var lastResponse = ""

    private let pythonPath = "/opt/homebrew/bin/python3"
    private let mlxScriptPath: String

    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        mlxScriptPath = homeDir.appendingPathComponent(".mlx/mbox_llm.py").path
        createMLXScript()
        Task {
            await checkAvailability()
        }
    }

    private func createMLXScript() {
        let script = """
        #!/usr/bin/env python3
        import sys
        import json

        try:
            import mlx.core as mx
            import mlx.nn as nn
        except ImportError:
            print("MLX not available")
            sys.exit(1)

        def answer_question(question, context_emails):
            # Simple answering logic (can be enhanced with actual LLM)
            # For now, extract relevant information from context

            response = f"Based on {len(context_emails)} emails:\\n\\n"

            # Extract key information
            for email in context_emails[:3]:  # Top 3 most relevant
                response += f"From {email['from']} ({email['date']}):\\n"
                response += f"Subject: {email['subject']}\\n"
                response += f"{email['snippet']}\\n\\n"

            response += "Sources: " + ", ".join([e['from'] for e in context_emails[:3]])

            return response

        if __name__ == "__main__":
            if len(sys.argv) < 2:
                print("Error: No input provided")
                sys.exit(1)

            input_data = json.loads(sys.argv[1])
            question = input_data.get('question', '')
            context = input_data.get('context', [])

            answer = answer_question(question, context)
            print(answer)
        """

        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let mlxDir = homeDir.appendingPathComponent(".mlx")
        try? FileManager.default.createDirectory(at: mlxDir, withIntermediateDirectories: true)

        let scriptURL = mlxDir.appendingPathComponent("mbox_llm.py")
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)

        // Make executable
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    func checkAvailability() async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: pythonPath)
        task.arguments = ["-c", "import mlx.core; print('OK')"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            await MainActor.run {
                isAvailable = task.terminationStatus == 0
            }
        } catch {
            await MainActor.run {
                isAvailable = false
            }
        }
    }

    /// Ask a question about emails
    func askQuestion(_ question: String, context: [SearchResult]) async -> String {
        guard isAvailable else {
            return "MLX not available. Using basic context extraction:\n\n" + generateBasicAnswer(question, context: context)
        }

        await MainActor.run {
            isProcessing = true
        }
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        // Prepare context for LLM
        let contextData = context.map { result in
            [
                "from": result.from,
                "subject": result.subject,
                "date": result.date,
                "snippet": result.snippet
            ]
        }

        let inputData: [String: Any] = [
            "question": question,
            "context": contextData
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: inputData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "Error: Could not prepare query"
        }

        // Call Python MLX script
        let task = Process()
        task.executableURL = URL(fileURLWithPath: pythonPath)
        task.arguments = [mlxScriptPath, jsonString]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No response"

            await MainActor.run {
                lastResponse = output
            }

            return output
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private func generateBasicAnswer(_ question: String, context: [SearchResult]) -> String {
        var answer = "Found \(context.count) relevant emails:\n\n"

        for (index, result) in context.prefix(3).enumerated() {
            answer += "\(index + 1). From: \(result.from)\n"
            answer += "   Subject: \(result.subject)\n"
            answer += "   Date: \(result.date)\n"
            answer += "   \(result.snippet)\n\n"
        }

        if context.count > 3 {
            answer += "...and \(context.count - 3) more emails\n"
        }

        return answer
    }

    /// Generate summary of email or thread
    func summarize(content: String) async -> String {
        guard isAvailable else {
            return generateBasicSummary(content)
        }

        // In full implementation, would call MLX LLM for summarization
        return generateBasicSummary(content)
    }

    private func generateBasicSummary(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        let firstLines = lines.prefix(10).joined(separator: " ")

        if firstLines.count > 200 {
            return String(firstLines.prefix(200)) + "..."
        }
        return firstLines
    }
}

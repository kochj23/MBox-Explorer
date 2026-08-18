//
//  OptimizationTests.swift
//  MBox ExplorerTests
//
//  Tests for the streaming MboxParser rewrite (#1 memory, #2 >From quoting,
//  #3 main-actor progress) and the PII file-permission helper (#6).
//

import XCTest
@testable import MBox_Explorer

// MARK: - Streaming parser

final class MboxParserStreamingTests: XCTestCase {

    private var temp: [URL] = []

    override func tearDownWithError() throws {
        for u in temp { try? FileManager.default.removeItem(at: u) }
        temp.removeAll()
    }

    private func writeMbox(_ body: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("parser-\(UUID().uuidString).mbox")
        try? body.data(using: .utf8)!.write(to: url)
        temp.append(url)
        return url
    }

    private func message(_ i: Int, body: String) -> String {
        """
        From sender\(i)@example.com Mon Jan 01 00:00:00 2024
        From: Sender \(i) <sender\(i)@example.com>
        To: recipient@example.com
        Subject: Message \(i)
        Date: Mon, 01 Jan 2024 00:00:0\(i % 10) +0000
        Message-ID: <msg\(i)@example.com>

        \(body)

        """
    }

    func testParsesMultipleMessages() async throws {
        let url = writeMbox(message(1, body: "First body.") + message(2, body: "Second body.") + message(3, body: "Third."))
        let emails = try await MboxParser().parse(fileURL: url)
        XCTAssertEqual(emails.count, 3)
        XCTAssertEqual(emails[0].subject, "Message 1")
        XCTAssertEqual(emails[1].from, "Sender 2 <sender2@example.com>")
        XCTAssertTrue(emails[2].body.contains("Third."))
    }

    // #2: a ">From " body line must be un-escaped and must NOT split the message.
    func testFromQuotingIsUnescapedAndDoesNotSplit() async throws {
        let msg = """
        From a@example.com Mon Jan 01 00:00:00 2024
        From: A <a@example.com>
        Subject: Quoting
        Date: Mon, 01 Jan 2024 00:00:00 +0000

        Body start
        >From the vault, this is still body
        Body end

        """
        let emails = try await MboxParser().parse(fileURL: writeMbox(msg))
        XCTAssertEqual(emails.count, 1, "a quoted >From line must not create a second message")
        XCTAssertTrue(emails[0].body.contains("From the vault, this is still body"))
        XCTAssertFalse(emails[0].body.contains(">From the vault"), "the mbox '>' quote should be stripped")
    }

    func testEmptyFileReturnsEmpty() async throws {
        let emails = try await MboxParser().parse(fileURL: writeMbox(""))
        XCTAssertEqual(emails.count, 0)
    }

    // #1: streaming should handle a large mailbox without loading it whole.
    func testLargeMailboxParses() async throws {
        var s = ""
        for i in 1...5000 { s += message(i, body: "Body of message \(i) with some filler text.") }
        let emails = try await MboxParser().parse(fileURL: writeMbox(s))
        XCTAssertEqual(emails.count, 5000)
    }

    // #3: progress must complete (and, implicitly, be published without crashing).
    func testProgressReachesComplete() async throws {
        let parser = MboxParser()
        _ = try await parser.parse(fileURL: writeMbox(message(1, body: "x")))
        XCTAssertEqual(parser.progress, 1.0, accuracy: 0.0001)
    }

    // Non-UTF8 (Latin-1) bytes must fall back gracefully, not crash or drop the message.
    func testLatin1Fallback() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("latin1-\(UUID().uuidString).mbox")
        var bytes = Array("From x@example.com Mon Jan 01 00:00:00 2024\nFrom: A <a@example.com>\nSubject: Cafe\n\nCaf".utf8)
        bytes.append(0xE9)  // 'é' in Latin-1, invalid as standalone UTF-8
        bytes.append(0x0A)
        try Data(bytes).write(to: url)
        temp.append(url)
        let emails = try await MboxParser().parse(fileURL: url)
        XCTAssertEqual(emails.count, 1)
        XCTAssertTrue(emails[0].body.contains("Caf"))
    }

    // LineReader unit: splits on \n and strips trailing \r.
    func testLineReaderStripsCRLF() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lr-\(UUID().uuidString).txt")
        try "alpha\r\nbeta\ngamma".data(using: .utf8)!.write(to: url)
        temp.append(url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let reader = LineReader(handle: handle, chunkSize: 4)   // tiny buffer forces multi-read
        var lines: [String] = []
        while let (line, _) = reader.nextLine() { lines.append(line) }
        XCTAssertEqual(lines, ["alpha", "beta", "gamma"])
    }
}

// MARK: - PII file permissions (#6)

final class FilePermissionsTests: XCTestCase {

    func testRestrictFileSetsOwnerOnly() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("perm-\(UUID().uuidString).db")
        try "sensitive".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        FilePermissions.restrictFile(url.path)
        let perms = (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(perms, 0o600)
    }

    func testRestrictDirectorySetsOwnerOnly() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("permdir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        FilePermissions.restrictDirectory(dir.path)
        let perms = (try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(perms, 0o700)
    }
}

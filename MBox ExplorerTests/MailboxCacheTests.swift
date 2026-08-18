//
//  MailboxCacheTests.swift
//  MBox ExplorerTests
//
//  Tests for the parsed-mailbox cache that fixes issue #2 ("Mailbox is fully
//  re-parsed on every app launch"). Organized across the 7 standard categories:
//  unit, integration, regression, performance, edge-case, security, UI/smoke.
//

import XCTest
@testable import MBox_Explorer

// A parser spy that counts how many times a full parse is performed, so the
// regression test can prove a reopen does NOT re-parse.
final class SpyParser: MboxParser {
    var parseCallCount = 0
    var stub: [Email] = []
    override func parse(fileURL: URL) async throws -> [Email] {
        parseCallCount += 1
        return stub
    }
}

final class MailboxCacheTests: XCTestCase {

    private var cacheDir: URL!
    private var cache: MailboxCache!
    private var tempFiles: [URL] = []

    override func setUpWithError() throws {
        cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailboxCacheTests-\(UUID().uuidString)", isDirectory: true)
        cache = MailboxCache(directory: cacheDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: cacheDir)
        for f in tempFiles { try? FileManager.default.removeItem(at: f) }
        tempFiles.removeAll()
    }

    // MARK: - Helpers

    private func makeEmail(_ n: Int) -> Email {
        Email(from: "sender\(n)@example.com",
              subject: "Subject \(n)",
              date: "2024-01-0\(n)",
              body: "Body number \(n).",
              messageId: "<msg\(n)@example.com>")
    }

    private func sampleEmails(_ count: Int = 3) -> [Email] {
        (1...count).map { makeEmail($0) }
    }

    /// Writes arbitrary bytes to a unique temp file and returns its URL.
    private func writeSourceFile(_ content: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("src-\(UUID().uuidString).mbox")
        try? content.data(using: .utf8)!.write(to: url)
        tempFiles.append(url)
        return url
    }

    /// Generates a syntactically valid mbox with `n` messages.
    private func writeMbox(_ n: Int) -> URL {
        var s = ""
        for i in 1...n {
            s += "From sender\(i)@example.com Mon Jan 0\(min(i,9)) 00:00:00 2024\n"
            s += "From: Sender \(i) <sender\(i)@example.com>\n"
            s += "To: recipient@example.com\n"
            s += "Subject: Message \(i)\n"
            s += "Date: Mon, 0\(min(i,9)) Jan 2024 00:00:00 +0000\n"
            s += "Message-ID: <msg\(i)@example.com>\n"
            s += "\n"
            s += "This is the body of message \(i).\n\n"
        }
        return writeSourceFile(s)
    }

    private func ids(_ e: [Email]) -> [UUID] { e.map(\.id) }
    private func bodies(_ e: [Email]) -> [String] { e.map(\.body) }

    // MARK: - (1) Unit — store/load round trip

    func testStoreThenLoadRoundTrip() {
        let url = writeSourceFile("dummy source bytes")
        let emails = sampleEmails(3)
        XCTAssertTrue(cache.store(emails, for: url))
        let loaded = cache.load(for: url)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 3)
        XCTAssertEqual(ids(loaded ?? []), ids(emails))
        XCTAssertEqual(bodies(loaded ?? []), bodies(emails))
    }

    func testLoadBeforeStoreReturnsNil() {
        let url = writeSourceFile("never cached")
        XCTAssertNil(cache.load(for: url), "a never-cached file must be a miss")
    }

    // MARK: - (2) Integration — real parser → cache → load

    func testParseThenCacheThenLoad() async throws {
        let url = writeMbox(4)
        let parser = MboxParser()
        let parsed = try await parser.parse(fileURL: url)
        XCTAssertFalse(parsed.isEmpty, "fixture should parse to some emails")
        XCTAssertTrue(cache.store(parsed, for: url))
        let loaded = cache.load(for: url)
        XCTAssertEqual(loaded?.count, parsed.count)
        XCTAssertEqual(ids(loaded ?? []), ids(parsed))
    }

    // MARK: - (3) Regression — reopen must NOT re-parse (guards issue #2)

    func testReopenUsesCacheAndDoesNotReparse() async throws {
        let url = writeMbox(3)
        let spy = SpyParser()
        spy.stub = sampleEmails(3)

        // Mirror exactly the branch in MboxViewModel.loadMboxFile.
        func load() async throws -> [Email] {
            if let cached = cache.load(for: url) { return cached }
            let parsed = try await spy.parse(fileURL: url)
            cache.store(parsed, for: url)
            return parsed
        }

        let first = try await load()   // miss → parse + store
        let second = try await load()  // hit → no parse
        XCTAssertEqual(spy.parseCallCount, 1, "reopening an unchanged file must not re-parse")
        XCTAssertEqual(ids(first), ids(second))
    }

    // MARK: - (4) Performance — cache hit far faster than a fresh parse

    func testCacheHitIsFasterThanParse() async throws {
        let url = writeMbox(2000)
        let parser = MboxParser()

        let t0 = Date()
        let parsed = try await parser.parse(fileURL: url)
        let parseTime = Date().timeIntervalSince(t0)
        cache.store(parsed, for: url)

        let t1 = Date()
        let loaded = cache.load(for: url)
        let cacheTime = Date().timeIntervalSince(t1)

        XCTAssertEqual(loaded?.count, parsed.count)
        XCTAssertLessThan(cacheTime, parseTime,
                          "cache hit (\(cacheTime)s) should beat a full parse (\(parseTime)s)")
    }

    // MARK: - (5) Edge cases

    func testEmptyMailboxCachesAsEmpty() {
        let url = writeSourceFile("")
        XCTAssertTrue(cache.store([], for: url))
        let loaded = cache.load(for: url)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 0)
    }

    func testCorruptCacheFileReturnsNil() {
        let url = writeSourceFile("source")
        try? "}{ not json".data(using: .utf8)!.write(to: cache.cacheFileURL(for: url))
        XCTAssertNil(cache.load(for: url), "a corrupt cache must be treated as a miss, not crash")
    }

    func testChangedFileInvalidatesCache() throws {
        let url = writeSourceFile("original content")
        cache.store(sampleEmails(2), for: url)
        XCTAssertNotNil(cache.load(for: url))
        // Change the file (grow its size) → cache identity no longer matches.
        try "original content plus much more appended data".data(using: .utf8)!.write(to: url)
        XCTAssertNil(cache.load(for: url), "a changed source file must invalidate the cache")
    }

    func testSchemaVersionMismatchInvalidatesCache() throws {
        let url = writeSourceFile("source for schema test")
        let id = cache.fileIdentity(of: url)!
        let stale = MailboxCache.Envelope(schemaVersion: 999, path: url.path,
                                          fileSize: id.size, modifiedAt: id.modifiedAt,
                                          emails: sampleEmails(1))
        let data = try JSONEncoder().encode(stale)
        try data.write(to: cache.cacheFileURL(for: url))
        XCTAssertNil(cache.load(for: url), "an old schema version must be rejected")
    }

    // MARK: - (6) Security — perms + location (bodies are PII)

    func testCacheFileIsOwnerOnly() throws {
        let url = writeSourceFile("pii source")
        XCTAssertTrue(cache.store(sampleEmails(1), for: url))
        let attrs = try FileManager.default.attributesOfItem(atPath: cache.cacheFileURL(for: url).path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(perms, 0o600, "cache holds email bodies (PII) — must be owner read/write only")
    }

    func testSharedCacheLivesInApplicationSupport() {
        let path = MailboxCache.shared.directory.path
        XCTAssertTrue(path.contains("Application Support"),
                      "PII cache must live in Application Support, not a shared/temp path")
        XCTAssertTrue(path.contains("MBoxExplorer"))
    }

    // MARK: - (7) UI / smoke — reopen flow through the view model

    @MainActor
    func testReopenSmokeFlowThroughViewModel() async throws {
        let url = writeMbox(3)
        MailboxCache.shared.remove(for: url)   // clean slate
        defer { MailboxCache.shared.remove(for: url) }

        let vm = MboxViewModel()
        await vm.loadMboxFile(url: url)

        XCTAssertFalse(vm.emails.isEmpty, "first load should populate emails")
        XCTAssertFalse(vm.showingProgressSheet, "progress sheet should be dismissed")
        XCTAssertFalse(vm.isLoading, "loading should finish")
        XCTAssertNotNil(MailboxCache.shared.load(for: url),
                        "first load must write the cache so a reopen hits it instead of re-parsing")
    }
}

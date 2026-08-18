//
//  IndexingResumeTests.swift
//  MBox ExplorerTests
//
//  Tests for resumable semantic indexing (#5): the work-set selection that lets
//  a cancelled/partial index run pick up where it left off.
//

import XCTest
@testable import MBox_Explorer

final class IndexingResumeTests: XCTestCase {

    private func email(_ i: Int) -> Email {
        Email(from: "sender\(i)@example.com", subject: "Subject \(i)", date: "2024-01-01", body: "Body \(i)")
    }

    func testPendingSkipsAlreadyIndexed() {
        let a = email(1), b = email(2), c = email(3)
        let indexed: Set<String> = [a.id.uuidString, c.id.uuidString]
        let pending = VectorDatabase.pendingEmails([a, b, c], alreadyIndexed: indexed)
        XCTAssertEqual(pending.map(\.id), [b.id], "only the not-yet-indexed email should remain")
    }

    func testNoneIndexedReturnsAll() {
        let all = [email(1), email(2), email(3)]
        XCTAssertEqual(VectorDatabase.pendingEmails(all, alreadyIndexed: []).count, 3)
    }

    func testAllIndexedReturnsEmpty() {
        let all = [email(1), email(2)]
        let indexed = Set(all.map { $0.id.uuidString })
        XCTAssertTrue(VectorDatabase.pendingEmails(all, alreadyIndexed: indexed).isEmpty,
                      "a fully-indexed mailbox has no pending work (a resume is a no-op)")
    }

    func testPreservesOrderOfPending() {
        let e = (1...5).map { email($0) }
        // pretend #2 and #4 are done
        let indexed: Set<String> = [e[1].id.uuidString, e[3].id.uuidString]
        let pending = VectorDatabase.pendingEmails(e, alreadyIndexed: indexed)
        XCTAssertEqual(pending.map(\.id), [e[0].id, e[2].id, e[4].id])
    }
}

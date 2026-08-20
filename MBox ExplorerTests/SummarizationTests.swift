//
//  SummarizationTests.swift
//  MBox ExplorerTests
//
//  Deterministic (no-network) tests for the balanced email-summarization
//  request builder and the graceful-no-backend availability decision.
//

import XCTest
@testable import MBox_Explorer

final class SummarizationTests: XCTestCase {

    // MARK: - Pure prompt building

    func testEmailPromptContainsHeadersAndBody() {
        let prompt = SummarizationRequest.emailPrompt(
            subject: "Q3 Planning",
            from: "alice@example.com",
            date: "2024-05-01",
            body: "Please review the attached deck before Friday."
        )
        XCTAssertTrue(prompt.contains("Subject: Q3 Planning"))
        XCTAssertTrue(prompt.contains("From: alice@example.com"))
        XCTAssertTrue(prompt.contains("Date: 2024-05-01"))
        XCTAssertTrue(prompt.contains("Please review the attached deck"))
        XCTAssertTrue(prompt.contains("action items"))
    }

    func testEmailPromptTruncatesLongBody() {
        let body = String(repeating: "x", count: 10_000)
        let prompt = SummarizationRequest.emailPrompt(subject: "s", from: "f", date: "d", body: body, bodyLimit: 100)
        // The body slice is capped; the whole prompt stays near the limit + header.
        XCTAssertLessThan(prompt.count, 500)
        XCTAssertFalse(prompt.contains(String(repeating: "x", count: 200)))
    }

    func testTruncateShortStringUnchanged() {
        XCTAssertEqual(SummarizationRequest.truncate("hello", limit: 100), "hello")
        XCTAssertEqual(SummarizationRequest.truncate("hello", limit: 3), "hel")
    }

    func testThreadPromptCountsMessages() {
        let msgs = [
            (from: "a@x.com", date: "d1", subject: "s", body: "first"),
            (from: "b@x.com", date: "d2", subject: "s", body: "second")
        ]
        let prompt = SummarizationRequest.threadPrompt(messages: msgs)
        XCTAssertTrue(prompt.contains("thread of 2 messages"))
        XCTAssertTrue(prompt.contains("first"))
        XCTAssertTrue(prompt.contains("second"))
        XCTAssertTrue(prompt.contains("---")) // separator between messages
    }

    func testThreadPromptSingularWording() {
        let prompt = SummarizationRequest.threadPrompt(messages: [(from: "a", date: "d", subject: "s", body: "only")])
        XCTAssertTrue(prompt.contains("thread of 1 message"))
        XCTAssertFalse(prompt.contains("1 messages"))
    }

    // MARK: - Graceful availability decision (no-backend path)

    func testAvailabilityPrefersBalancedWhenPoolHealthy() {
        let a = SummarizationRequest.availability(isBalancingEnabled: true, balancerHasBackend: true, singleBackendAvailable: false)
        XCTAssertEqual(a, .balanced)
    }

    func testAvailabilityFallsBackToSingleBackend() {
        let a = SummarizationRequest.availability(isBalancingEnabled: false, balancerHasBackend: false, singleBackendAvailable: true)
        XCTAssertEqual(a, .single)
    }

    func testAvailabilityUnavailableWhenBalancingOnButPoolEmpty() {
        let a = SummarizationRequest.availability(isBalancingEnabled: true, balancerHasBackend: false, singleBackendAvailable: false)
        guard case .unavailable(let reason) = a else { return XCTFail("expected unavailable") }
        XCTAssertTrue(reason.contains("no enabled backend is reachable"))
    }

    func testAvailabilityUnavailableWhenNothingConfigured() {
        let a = SummarizationRequest.availability(isBalancingEnabled: false, balancerHasBackend: false, singleBackendAvailable: false)
        guard case .unavailable(let reason) = a else { return XCTFail("expected unavailable") }
        XCTAssertTrue(reason.contains("No AI backend is available"))
    }

    func testAvailabilityBalancedWinsOverSingle() {
        // When both are possible, the balanced pool is preferred.
        let a = SummarizationRequest.availability(isBalancingEnabled: true, balancerHasBackend: true, singleBackendAvailable: true)
        XCTAssertEqual(a, .balanced)
    }

    // MARK: - Basic extractive fallback (never crashes, always returns text)

    func testBasicSummaryFromMultilineContent() {
        let content = "First line.\n\nSecond line.\nThird line."
        let summary = BalancedSummarizer.basicSummary(content)
        XCTAssertTrue(summary.contains("First line."))
        XCTAssertFalse(summary.isEmpty)
    }

    func testBasicSummaryTruncatesAndEllipsizes() {
        let content = String(repeating: "word ", count: 400)
        let summary = BalancedSummarizer.basicSummary(content)
        XCTAssertLessThanOrEqual(summary.count, 302)
        XCTAssertTrue(summary.hasSuffix("…"))
    }

    func testBasicSummaryEmptyContentIsSafe() {
        XCTAssertEqual(BalancedSummarizer.basicSummary(""), "")
        XCTAssertEqual(BalancedSummarizer.basicSummary("\n\n   \n"), "")
    }
}

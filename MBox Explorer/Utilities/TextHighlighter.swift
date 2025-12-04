//
//  TextHighlighter.swift
//  MBox Explorer
//
//  Text highlighting for search results
//

import Foundation
import SwiftUI
import AppKit

class TextHighlighter {

    // MARK: - Highlight Options

    struct HighlightOptions {
        var caseSensitive: Bool = false
        var wholeWord: Bool = false
        var useRegex: Bool = false
        var highlightColor: NSColor = .systemYellow
        var textColor: NSColor = .black
    }

    // MARK: - Public Methods

    static func highlightedAttributedString(
        text: String,
        searchTerms: [String],
        options: HighlightOptions = HighlightOptions()
    ) -> AttributedString {
        guard !searchTerms.isEmpty else {
            return AttributedString(text)
        }

        var attributedString = AttributedString(text)

        for term in searchTerms where !term.isEmpty {
            let ranges = findRanges(in: text, searchTerm: term, options: options)

            for range in ranges {
                if let attributedRange = Range(range, in: attributedString) {
                    attributedString[attributedRange].backgroundColor = Color(options.highlightColor)
                    attributedString[attributedRange].foregroundColor = Color(options.textColor)
                }
            }
        }

        return attributedString
    }

    static func highlightedNSAttributedString(
        text: String,
        searchTerms: [String],
        options: HighlightOptions = HighlightOptions()
    ) -> NSAttributedString {
        guard !searchTerms.isEmpty else {
            return NSAttributedString(string: text)
        }

        let attributedString = NSMutableAttributedString(string: text)

        // Base attributes
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.textColor
        ]
        attributedString.addAttributes(baseAttributes, range: NSRange(location: 0, length: text.count))

        // Highlight attributes
        let highlightAttributes: [NSAttributedString.Key: Any] = [
            .backgroundColor: options.highlightColor,
            .foregroundColor: options.textColor
        ]

        for term in searchTerms where !term.isEmpty {
            let ranges = findRanges(in: text, searchTerm: term, options: options)

            for range in ranges {
                attributedString.addAttributes(highlightAttributes, range: range)
            }
        }

        return attributedString
    }

    // MARK: - Find Ranges

    private static func findRanges(
        in text: String,
        searchTerm: String,
        options: HighlightOptions
    ) -> [NSRange] {
        var ranges: [NSRange] = []

        if options.useRegex {
            ranges = findRegexRanges(in: text, pattern: searchTerm, options: options)
        } else {
            ranges = findLiteralRanges(in: text, searchTerm: searchTerm, options: options)
        }

        return ranges
    }

    private static func findLiteralRanges(
        in text: String,
        searchTerm: String,
        options: HighlightOptions
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        let nsText = text as NSString

        var searchOptions: NSString.CompareOptions = []
        if !options.caseSensitive {
            searchOptions.insert(.caseInsensitive)
        }

        var searchRange = NSRange(location: 0, length: nsText.length)

        while searchRange.location < nsText.length {
            let foundRange = nsText.range(of: searchTerm, options: searchOptions, range: searchRange)

            if foundRange.location == NSNotFound {
                break
            }

            // Check for whole word match
            if options.wholeWord {
                if isWholeWord(at: foundRange, in: text) {
                    ranges.append(foundRange)
                }
            } else {
                ranges.append(foundRange)
            }

            // Move search range forward
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = nsText.length - searchRange.location
        }

        return ranges
    }

    private static func findRegexRanges(
        in text: String,
        pattern: String,
        options: HighlightOptions
    ) -> [NSRange] {
        var ranges: [NSRange] = []

        do {
            var regexOptions: NSRegularExpression.Options = []
            if !options.caseSensitive {
                regexOptions.insert(.caseInsensitive)
            }

            let regex = try NSRegularExpression(pattern: pattern, options: regexOptions)
            let nsText = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

            for match in matches {
                ranges.append(match.range)
            }
        } catch {
            // Invalid regex, return empty
            return []
        }

        return ranges
    }

    private static func isWholeWord(at range: NSRange, in text: String) -> Bool {
        let nsText = text as NSString

        // Check character before
        if range.location > 0 {
            let charBefore = nsText.character(at: range.location - 1)
            if CharacterSet.alphanumerics.contains(UnicodeScalar(charBefore)!) {
                return false
            }
        }

        // Check character after
        let endLocation = range.location + range.length
        if endLocation < nsText.length {
            let charAfter = nsText.character(at: endLocation)
            if CharacterSet.alphanumerics.contains(UnicodeScalar(charAfter)!) {
                return false
            }
        }

        return true
    }

    // MARK: - Match Context

    struct MatchContext {
        let text: String
        let matchRange: NSRange
        let lineNumber: Int
        let contextBefore: String
        let matchedText: String
        let contextAfter: String

        var fullContext: String {
            return "\(contextBefore)\(matchedText)\(contextAfter)"
        }
    }

    static func findMatches(
        in text: String,
        searchTerms: [String],
        options: HighlightOptions = HighlightOptions(),
        contextLength: Int = 50
    ) -> [MatchContext] {
        var matches: [MatchContext] = []
        let nsText = text as NSString

        for term in searchTerms where !term.isEmpty {
            let ranges = findRanges(in: text, searchTerm: term, options: options)

            for range in ranges {
                // Calculate line number
                let lineNumber = text.prefix(range.location).filter { $0.isNewline }.count + 1

                // Get context
                let contextBeforeStart = max(0, range.location - contextLength)
                let contextBeforeRange = NSRange(location: contextBeforeStart, length: range.location - contextBeforeStart)
                let contextBefore = nsText.substring(with: contextBeforeRange)

                let matchedText = nsText.substring(with: range)

                let contextAfterEnd = min(nsText.length, range.location + range.length + contextLength)
                let contextAfterRange = NSRange(location: range.location + range.length, length: contextAfterEnd - (range.location + range.length))
                let contextAfter = nsText.substring(with: contextAfterRange)

                let context = MatchContext(
                    text: text,
                    matchRange: range,
                    lineNumber: lineNumber,
                    contextBefore: contextBefore,
                    matchedText: matchedText,
                    contextAfter: contextAfter
                )

                matches.append(context)
            }
        }

        return matches
    }

    // MARK: - Statistics

    static func countMatches(
        in text: String,
        searchTerms: [String],
        options: HighlightOptions = HighlightOptions()
    ) -> Int {
        var totalCount = 0

        for term in searchTerms where !term.isEmpty {
            let ranges = findRanges(in: text, searchTerm: term, options: options)
            totalCount += ranges.count
        }

        return totalCount
    }

    static func highlightStatistics(
        emails: [Email],
        searchTerms: [String],
        options: HighlightOptions = HighlightOptions()
    ) -> HighlightStatistics {
        var totalMatches = 0
        var emailsWithMatches = 0
        var matchesByEmail: [(Email, Int)] = []

        for email in emails {
            let text = "\(email.subject) \(email.body)"
            let count = countMatches(in: text, searchTerms: searchTerms, options: options)

            if count > 0 {
                emailsWithMatches += 1
                matchesByEmail.append((email, count))
            }

            totalMatches += count
        }

        // Sort by match count
        matchesByEmail.sort { $0.1 > $1.1 }

        return HighlightStatistics(
            totalMatches: totalMatches,
            emailsWithMatches: emailsWithMatches,
            topEmails: Array(matchesByEmail.prefix(10))
        )
    }

    struct HighlightStatistics {
        let totalMatches: Int
        let emailsWithMatches: Int
        let topEmails: [(Email, Int)]
    }
}

// MARK: - SwiftUI View Extension

extension Text {
    static func highlighted(
        _ text: String,
        searchTerms: [String],
        options: TextHighlighter.HighlightOptions = TextHighlighter.HighlightOptions()
    ) -> Text {
        let attributedString = TextHighlighter.highlightedAttributedString(
            text: text,
            searchTerms: searchTerms,
            options: options
        )
        return Text(attributedString)
    }
}

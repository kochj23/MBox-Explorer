//
//  SmartFilters.swift
//  MBox Explorer
//
//  Smart filtering criteria model
//

import Foundation

struct SmartFilters {
    var hasAttachments = false
    var hasNoAttachments = false
    var excludeAutomated = false
    var enableLengthFilter = false
    var minLength = 0
    var maxLength = 100000
    var useRegex = false
    var regexPattern = ""
    var regexCaseSensitive = false
    var onlyThreadRoots = false
    var onlyReplies = false

    var isValidRegex: Bool {
        guard !regexPattern.isEmpty else { return false }
        do {
            _ = try NSRegularExpression(pattern: regexPattern, options: [])
            return true
        } catch {
            return false
        }
    }

    var isActive: Bool {
        hasAttachments || hasNoAttachments || excludeAutomated ||
        enableLengthFilter || (useRegex && !regexPattern.isEmpty) ||
        onlyThreadRoots || onlyReplies
    }
}

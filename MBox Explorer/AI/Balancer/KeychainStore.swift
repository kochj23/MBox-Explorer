//
//  KeychainStore.swift
//  MBox Explorer (balancer core — copied verbatim from AIStudio)
//
//  Created by Jordan Koch on 2026-02-19.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import Foundation
import Security

/// Minimal macOS Keychain wrapper for storing secrets (e.g. API keys).
///
/// Secrets are stored as classic generic-password items in the login keychain so
/// that the round-trip works in unsigned/unsandboxed unit-test processes (no
/// data-protection keychain, which would require entitlements). Never store
/// secrets in UserDefaults.
struct KeychainStore {
    let service: String
    let account: String

    /// - Parameters:
    ///   - service: Keychain service identifier. Defaults to the OpenRouter service.
    ///   - account: Account/key name within the service.
    init(service: String = OpenRouterProvider.keychainService, account: String = "apiKey") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Store (or replace) a secret. Returns true on success.
    @discardableResult
    func set(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Remove any existing item first so we can cleanly re-add.
        SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve a secret, or nil if none is stored.
    func get() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Delete the stored secret. Returns true if an item was removed or none existed.
    @discardableResult
    func delete() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// True if a non-empty secret is stored.
    var hasValue: Bool {
        guard let value = get() else { return false }
        return !value.isEmpty
    }
}

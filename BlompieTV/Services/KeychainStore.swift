//
//  KeychainStore.swift
//  BlompieTV (originally from AIStudio)
//
//  Created by Jordan Koch on 2026-02-19.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import Foundation
import Security

/// Minimal Keychain wrapper for storing secrets (e.g. API keys).
///
/// Secrets are generic-password items under this app's own service name
/// (`com.jkoch.blompietv.<provider>`). Never store secrets in UserDefaults,
/// files or environment variables.
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

    /// Store (or replace) a secret. Updates in place when an item exists so its
    /// access settings are kept. Returns true on success.
    @discardableResult
    func set(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
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

    /// One-time migration from an older service name: if this store is empty and
    /// `legacy` holds a non-empty secret, copy it here and remove the legacy item.
    /// Returns true when a secret was migrated. Never logs the secret.
    @discardableResult
    func migrate(from legacy: KeychainStore) -> Bool {
        guard legacy.service != service || legacy.account != account else { return false }
        guard !hasValue, let old = legacy.get(), !old.isEmpty else { return false }
        guard set(old) else { return false }
        legacy.delete()
        return true
    }
}

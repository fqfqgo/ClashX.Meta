//
//  SubscriptionPasswordStorage.swift
//  ClashX
//
//  Store subscription decryption password in Keychain for auto-update.
//

import Foundation
import Security

enum SubscriptionPasswordStorage {
    private static let serviceName = "com.metacubex.ClashX.meta.subscription"

    static func savePassword(_ password: String, forConfigName name: String) {
        guard !password.isEmpty, !name.isEmpty else { return }
        deletePassword(forConfigName: name)
        guard let data = password.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: name,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func getPassword(forConfigName name: String) -> String? {
        guard !name.isEmpty else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: name,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    static func deletePassword(forConfigName name: String) {
        guard !name.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: name
        ]
        SecItemDelete(query as CFDictionary)
    }
}

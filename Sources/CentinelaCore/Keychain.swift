import Foundation
import Security

/// The token lives in the Keychain, not in `UserDefaults` and not in a dotfile.
///
/// The reason is not theoretical: the token that started this project sat in `~/.sentryclirc`
/// in plain text, readable by any process running as the user, and backed up to wherever the
/// home directory gets backed up. A Sentry organization token does not expire on its own.
public enum Keychain {
    public static let service = "cl.bioalergia.centinela"

    public enum Failure: Error, LocalizedError {
        case system(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .system(let status):
                let text = SecCopyErrorMessageString(status, nil) as String? ?? "code \(status)"
                return "The Keychain answered: \(text)"
            }
        }
    }

    public static func read(account: String) throws -> String? {
        var query = base(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.system(status)
        }
    }

    public static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = base(account: account)

        // Update is attempted before add. `SecItemAdd` on an existing item returns
        // `errSecDuplicateItem` instead of replacing it, so the order matters.
        let change = [kSecValueData as String: data] as CFDictionary
        let updated = SecItemUpdate(query as CFDictionary, change)
        if updated == errSecSuccess { return }
        if updated != errSecItemNotFound { throw Failure.system(updated) }

        var fresh = query
        fresh[kSecValueData as String] = data
        // Only while the machine is unlocked, and never synced to iCloud nor restored onto a
        // different device.
        fresh[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(fresh as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure.system(added) }
    }

    public static func delete(account: String) throws {
        let status = SecItemDelete(base(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.system(status)
        }
    }

    private static func base(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}

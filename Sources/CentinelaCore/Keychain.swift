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

/// Where a secret is kept, behind a seam.
///
/// It exists because of one specific hole. `AppSettings.move` copies a secret to a new account and
/// deletes the old one only if the copy succeeded — written the other way round, a Keychain that
/// refuses the write takes the only copy with it and signs somebody out for good. That ordering
/// could not be tested: with a real Keychain the write always succeeds, so breaking the order left
/// the suite green, which is the same as having no test at all.
///
/// A second thing falls out of it: tests that use their own store do not touch the login keychain,
/// which is where a run once sat for five minutes waiting on a password dialog.
public protocol SecretStore: Sendable {
    func read(account: String) throws -> String?
    func save(_ value: String, account: String) throws
    func delete(account: String) throws
}

/// The real one. `Keychain` is an enum of statics, so this is the thin thing that conforms.
public struct KeychainStore: SecretStore {
    public init() {}
    public func read(account: String) throws -> String? { try Keychain.read(account: account) }
    public func save(_ value: String, account: String) throws { try Keychain.save(value, account: account) }
    public func delete(account: String) throws { try Keychain.delete(account: account) }
}

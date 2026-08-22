import Foundation
import Testing

@testable import CentinelaCore

/// The Keychain is the project's central security claim and until now had not a single test.
/// These make the round trip against the real Keychain, with an account of their own that is
/// deleted afterwards.
///
/// They run serially: they share one account in a system-global store and would trample each
/// other in parallel.
@Suite("Keychain", .serialized)
struct KeychainTests {
    private let account = "centinela-automated-test"

    private func clean() { try? Keychain.delete(account: account) }

    @Test("Saving and reading back returns exactly the same thing")
    func roundTrip() throws {
        clean()
        defer { clean() }

        // With non-ASCII characters: the value travels as UTF-8 `Data` and a careless
        // conversion would lose them silently.
        let secret = "sntrys_ñÑáé·\(UUID().uuidString)"
        try Keychain.save(secret, account: account)
        #expect(try Keychain.read(account: account) == secret)
    }

    /// `SecItemAdd` on an item that already exists returns `errSecDuplicateItem` instead of
    /// replacing it. That is why `save` tries to update first; without that order, changing the
    /// token would fail from the second time on.
    @Test("Saving twice replaces, it does not duplicate or fail")
    func overwrite() throws {
        clean()
        defer { clean() }

        try Keychain.save("first", account: account)
        try Keychain.save("second", account: account)
        #expect(try Keychain.read(account: account) == "second")
    }

    @Test("An account that does not exist returns nil, not an error")
    func absent() throws {
        clean()
        #expect(try Keychain.read(account: "account-that-does-not-exist-\(UUID().uuidString)") == nil)
    }

    @Test("Deleting twice does not fail the second time")
    func deleteIsIdempotent() throws {
        try Keychain.save("x", account: account)
        try Keychain.delete(account: account)
        try Keychain.delete(account: account)
        #expect(try Keychain.read(account: account) == nil)
    }
}

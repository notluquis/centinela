import Foundation
import Testing

@testable import CentinelaCore

/// The migrations, and the seam that makes them testable.
///
/// Split out of `AppSettingsTests` when that type crossed swiftlint's 250-line body. The seam is
/// the reason they are together: what happens to a stored session when the names it was stored
/// under change, including the case a real Keychain will not produce on demand.
///
/// They run serially and against their own accounts. The real ones belong to a live session, and
/// a probe that used them once overwrote and then deleted it.
@MainActor
@Suite("App settings migrations", .serialized)
struct AppSettingsMigrationTests {
    /// The rename is only safe if it carries the old values over. Without this, upgrading forgets
    /// the organization, the window and the refresh interval, and the app comes back saying it
    /// was never configured.
    @Test("Renamed preference keys carry their old values over")
    func renamedKeysKeepTheirValues() {
        let unique = UUID().uuidString
        let suiteName = "centinela.tests.rename.\(unique)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        // Written under the names a pre-rename install would have left behind.
        suite.set("example", forKey: "organizacion")
        suite.set("7d", forKey: "ventana")
        suite.set(900.0, forKey: "intervaloSegundos")
        suite.set(25, forKey: "maximoIssues")

        let settings = AppSettings(
            defaults: suite,
            tokenAccount: "token-\(unique)",
            refreshAccount: "refresh-\(unique)"
        )
        defer {
            try? Keychain.delete(account: settings.tokenAccountName)
            try? Keychain.delete(account: settings.refreshAccountName)
        }

        #expect(settings.organization == "example")
        #expect(settings.window == .sevenDays)
        #expect(settings.intervalSeconds == 900)
        #expect(settings.maxIssues == 25)

        // The old names are gone, so this cannot keep happening on every launch.
        #expect(suite.object(forKey: "organizacion") == nil)
        #expect(suite.string(forKey: "organization") == "example")
    }
    /// The Keychain half of the rename, which had no test because the guard that kept tests away
    /// from a live session also kept them away from the migration. The old account names are
    /// injectable now, so this exercises the real path against throwaway accounts.
    @Test("A session stored under the old account names moves across")
    func keychainMigrationMovesTheSession() throws {
        let unique = UUID().uuidString
        let suite = UserDefaults(suiteName: "centinela.tests.kc.\(unique)")!
        let oldToken = "old-token-\(unique)"
        let oldRefresh = "old-refresh-\(unique)"
        let newToken = "new-token-\(unique)"
        let newRefresh = "new-refresh-\(unique)"
        defer {
            for account in [oldToken, oldRefresh, newToken, newRefresh] {
                try? Keychain.delete(account: account)
            }
            UserDefaults.standard.removePersistentDomain(forName: "centinela.tests.kc.\(unique)")
        }

        // What a pre-rename install left behind.
        try Keychain.save("a-token", account: oldToken)
        try Keychain.save("a-refresh", account: oldRefresh)

        let settings = AppSettings(
            defaults: suite,
            tokenAccount: newToken,
            refreshAccount: newRefresh,
            legacyTokenAccount: oldToken,
            legacyRefreshAccount: oldRefresh
        )

        // The access token moves at init, because without it the app comes back signed out.
        #expect(settings.token == "a-token")
        #expect(try Keychain.read(account: newToken) == "a-token")
        #expect(try Keychain.read(account: oldToken) == nil, "the old one is gone once the new one is written")

        // The refresh token moves on first use instead, to keep a Keychain read off the launch.
        #expect(try Keychain.read(account: newRefresh) == nil, "not touched at init")
        #expect(settings.refreshToken == "a-refresh")
        #expect(try Keychain.read(account: newRefresh) == "a-refresh")
        #expect(try Keychain.read(account: oldRefresh) == nil)
    }
    /// An in-memory store, so a test can say "the write fails" — which a real Keychain will not
    /// do on demand, and which is exactly the case that loses somebody's session.
    private final class Store: SecretStore, @unchecked Sendable {
        var items: [String: String]
        let refusesWritesTo: String?

        init(_ items: [String: String] = [:], refusesWritesTo: String? = nil) {
            self.items = items
            self.refusesWritesTo = refusesWritesTo
        }

        func read(account: String) throws -> String? { items[account] }
        func save(_ value: String, account: String) throws {
            if account == refusesWritesTo { throw Keychain.Failure.system(-25299) }
            items[account] = value
        }
        func delete(account: String) throws { items[account] = nil }
    }
    /// The one that could not be written before the seam existed, and the reason the seam does.
    ///
    /// Copy first, delete second, and only if the copy worked. The other order reads the same and
    /// behaves the same every time the write succeeds, which is every time on a real Keychain —
    /// so the wrong version passed the suite. It fails this one.
    @Test("A refused write keeps the old secret instead of destroying it")
    func refusedMigrationKeepsTheOldSecret() {
        let store = Store(["old-token": "a-token"], refusesWritesTo: "new-token")
        let suiteName = "centinela.tests.refuse.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(
            defaults: suite,
            tokenAccount: "new-token",
            refreshAccount: "new-refresh",
            legacyTokenAccount: "old-token",
            legacyRefreshAccount: "old-refresh",
            store: store
        )

        // The session still works in this run: the value was read, it just could not be re-homed.
        #expect(settings.token == "a-token")
        // And the only copy is still there, so the next launch can try again.
        #expect(store.items["old-token"] == "a-token", "a refused write must not take the original with it")
        #expect(store.items["new-token"] == nil)
        #expect(settings.lastStorageError != nil, "and it says so rather than failing quietly")
    }
}

import Foundation
import Observation
import Testing

@testable import CentinelaCore

/// The bug these pin looked like this: the menu bar cheerfully counted 22 errors while the panel
/// right below it said "Not configured yet". Both read the same two values.
///
/// The cause was that `token` was a computed property backed by an `@ObservationIgnored` cache,
/// so `isConfigured` depended on something SwiftUI could not observe. The panel was built while
/// the Keychain was empty, the token arrived a moment later, and nothing ever told the panel to
/// look again.
///
/// They run serially and against their own Keychain accounts: the real ones belong to a live
/// session, and a probe that used them once overwrote and then deleted it.
@MainActor
@Suite("App settings", .serialized)
struct AppSettingsTests {
    private func fresh() -> (AppSettings, String) {
        let unique = UUID().uuidString
        let suite = UserDefaults(suiteName: "centinela.tests.\(unique)")!
        let settings = AppSettings(
            defaults: suite,
            tokenAccount: "centinela-test-token-\(unique)",
            refreshAccount: "centinela-test-refresh-\(unique)"
        )
        return (settings, unique)
    }

    private func clean(_ unique: String) {
        try? Keychain.delete(account: "centinela-test-token-\(unique)")
        try? Keychain.delete(account: "centinela-test-refresh-\(unique)")
        UserDefaults.standard.removePersistentDomain(forName: "centinela.tests.\(unique)")
    }

    /// The regression test for the panel bug: saving a token has to notify whoever is observing
    /// `isConfigured`. Without the notification the value flips and nothing redraws.
    @Test("Saving a token notifies observers of `isConfigured`")
    func savingTokenNotifiesObservers() {
        let (settings, unique) = fresh()
        defer { clean(unique) }
        settings.organization = "example"
        #expect(!settings.isConfigured)

        var notified = false
        withObservationTracking {
            _ = settings.isConfigured
        } onChange: {
            notified = true
        }

        settings.saveToken("a-token")
        #expect(settings.isConfigured)
        #expect(notified, "isConfigured changed without telling anyone: the panel never redraws")
    }

    @Test("Signing out also notifies")
    func signOutNotifies() {
        let (settings, unique) = fresh()
        defer { clean(unique) }
        settings.organization = "example"
        settings.saveToken("a-token")

        var notified = false
        withObservationTracking {
            _ = settings.isConfigured
        } onChange: {
            notified = true
        }

        settings.signOut()
        #expect(!settings.isConfigured)
        #expect(notified)
    }

    @Test("Both halves are required: organization and token")
    func bothHalvesRequired() {
        let (settings, unique) = fresh()
        defer { clean(unique) }
        #expect(!settings.isConfigured)
        settings.saveToken("a-token")
        #expect(!settings.isConfigured, "a token with no organization is not configured")
        settings.organization = "example"
        #expect(settings.isConfigured)
        #expect(settings.credentials() != nil)
    }

    /// The token is read from the Keychain once, when the object is built. A previous version
    /// read it lazily from a view body, which is a synchronous system call on every draw.
    @Test("The token is loaded at init, not on every read")
    func tokenLoadedAtInit() {
        let (first, unique) = fresh()
        defer { clean(unique) }
        first.saveToken("stored-token")

        let second = AppSettings(
            defaults: UserDefaults(suiteName: "centinela.tests.\(unique)")!,
            tokenAccount: "centinela-test-token-\(unique)",
            refreshAccount: "centinela-test-refresh-\(unique)"
        )
        #expect(second.token == "stored-token")
    }

    @Test("Preferences survive being rebuilt")
    func preferencesPersist() {
        let (first, unique) = fresh()
        defer { clean(unique) }
        first.organization = "example"
        first.window = .sevenDays
        first.maxIssues = 25

        let second = AppSettings(
            defaults: UserDefaults(suiteName: "centinela.tests.\(unique)")!,
            tokenAccount: "centinela-test-token-\(unique)",
            refreshAccount: "centinela-test-refresh-\(unique)"
        )
        #expect(second.organization == "example")
        #expect(second.window == .sevenDays)
        #expect(second.maxIssues == 25)
    }
}

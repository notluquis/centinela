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
    /// The store writes into a temporary directory, never into the real container. It was not
    /// injectable once, and a probe of mine overwrote and then deleted a live session token.
    /// A settings object wired to a temporary directory and its own defaults suite.
    struct Fixture {
        let settings: AppSettings
        let suiteName: String
        let directory: URL
    }

    private func fresh() -> Fixture {
        let unique = UUID().uuidString
        let suite = UserDefaults(suiteName: "centinela.tests.\(unique)")!
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("centinela-tests-\(unique)")
        let settings = AppSettings(
            defaults: suite,
            tokenAccount: "token-\(unique)",
            refreshAccount: "refresh-\(unique)"
        )
        return Fixture(settings: settings, suiteName: "centinela.tests.\(unique)", directory: directory)
    }

    private func clean(_ fixture: Fixture) {
        try? Keychain.delete(account: fixture.settings.tokenAccountName)
        try? Keychain.delete(account: fixture.settings.refreshAccountName)
        try? FileManager.default.removeItem(at: fixture.directory)
        UserDefaults.standard.removePersistentDomain(forName: fixture.suiteName)
    }

    /// The regression test for the panel bug: saving a token has to notify whoever is observing
    /// `isConfigured`. Without the notification the value flips and nothing redraws.
    @Test("Saving a token notifies observers of `isConfigured`")
    func savingTokenNotifiesObservers() {
        let fixture = fresh()
        let settings = fixture.settings
        defer { clean(fixture) }
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
        let fixture = fresh()
        let settings = fixture.settings
        defer { clean(fixture) }
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
        let fixture = fresh()
        let settings = fixture.settings
        defer { clean(fixture) }
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
        let fixture = fresh()
        let first = fixture.settings
        defer { clean(fixture) }
        first.saveToken("stored-token")

        let second = AppSettings(
            defaults: UserDefaults(suiteName: fixture.suiteName)!,
            tokenAccount: first.tokenAccountName,
            refreshAccount: first.refreshAccountName
        )
        #expect(second.token == "stored-token")
    }

    @Test("Preferences survive being rebuilt")
    func preferencesPersist() {
        let fixture = fresh()
        let first = fixture.settings
        defer { clean(fixture) }
        first.organization = "example"
        first.window = .sevenDays
        first.maxIssues = 25
        first.badgeMetric = .escalating

        let second = AppSettings(
            defaults: UserDefaults(suiteName: fixture.suiteName)!,
            tokenAccount: first.tokenAccountName,
            refreshAccount: first.refreshAccountName
        )
        #expect(second.organization == "example")
        #expect(second.window == .sevenDays)
        #expect(second.maxIssues == 25)
        #expect(second.badgeMetric == .escalating)
    }

    /// The default is error events, the one metric that rides the series the cheap cycle already
    /// fetches, so a fresh install does not pull an issue-list read into every periodic tick. A
    /// blank preference reads as that default; an issue count is an explicit opt-in.
    @Test("The menu-bar count defaults to error events, keeping the cheap cycle cheap")
    func badgeMetricDefaultsToErrorEvents() {
        let fixture = fresh()
        defer { clean(fixture) }
        #expect(fixture.settings.badgeMetric == .errorEvents)
    }

    @Test("`authMethod` tells the two ways in apart, and survives a restart")
    func authMethodReflectsStoredState() {
        let fixture = fresh()
        let settings = fixture.settings
        defer { clean(fixture) }
        #expect(settings.authMethod == .signedOut)

        settings.saveManualToken("pasted")
        #expect(settings.authMethod == .pastedToken)

        settings.saveSession(DeviceFlow.Grant(
            accessToken: "from-oauth",
            refreshToken: "renew-me",
            expiresAt: Date().addingTimeInterval(3600)
        ))
        #expect(settings.authMethod == .deviceFlow)

        // The point of deriving it from stored state: a second object over the same store, which
        // is what a relaunch is, reads the same answer. `LoginController.stage` would say `.idle`.
        let afterRestart = AppSettings(
            defaults: UserDefaults(suiteName: fixture.suiteName)!,
            tokenAccount: settings.tokenAccountName,
            refreshAccount: settings.refreshAccountName
        )
        #expect(afterRestart.authMethod == .deviceFlow)

        settings.signOut()
        #expect(settings.authMethod == .signedOut)
    }

    /// Not a classification detail. `shouldRefresh` needs an expiry in the past AND a refresh
    /// token, and both used to survive a paste: the next cycle renewed the old OAuth session
    /// straight over the token that had just been pasted by hand.
    @Test("Pasting a token ends the OAuth session instead of leaving it to renew over it")
    func pastingATokenEndsTheOAuthSession() {
        let fixture = fresh()
        let settings = fixture.settings
        defer { clean(fixture) }

        settings.saveSession(DeviceFlow.Grant(
            accessToken: "from-oauth",
            refreshToken: "renew-me",
            expiresAt: Date().addingTimeInterval(-60)
        ))
        #expect(settings.shouldRefresh)

        settings.saveManualToken("pasted")
        #expect(settings.token == "pasted")
        #expect(settings.tokenExpiresAt == nil)
        #expect(settings.refreshToken == nil)
        #expect(!settings.shouldRefresh)
        #expect(settings.authMethod == .pastedToken)
    }

    /// Pins the order, not the answer. Reordering `shouldRefresh` changes no answer it gives —
    /// every combination returns exactly what it returned before — so the only thing a test can
    /// hold on to is whether the Keychain was touched. `refreshToken` is a Keychain read, this
    /// runs every cycle, and with no team identifier every read after an update costs a password
    /// dialog.
    @Test("A token with life left decides without reading the Keychain")
    func freshTokenDoesNotReadTheRefreshToken() {
        let store = InMemoryStore()
        let suiteName = "centinela.tests.clock.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        // Explicit account names even with a fake store. The suite's rule is that tests never
        // name the live accounts, and leaving the defaults here means the day something reaches
        // `Keychain` statically instead of through the store, it lands on a real session.
        let settings = AppSettings(
            defaults: suite,
            tokenAccount: "token-\(UUID().uuidString)",
            refreshAccount: "refresh-\(UUID().uuidString)",
            store: store
        )

        settings.saveSession(DeviceFlow.Grant(
            accessToken: "from-oauth",
            refreshToken: "renew-me",
            expiresAt: Date().addingTimeInterval(3600)
        ))

        let before = store.reads
        #expect(!settings.shouldRefresh)
        #expect(store.reads == before, "a token with life left has nothing to ask the Keychain")

        // And when a renewal really is due, it does read: the guard is an ordering, not a way of
        // never looking.
        settings.tokenExpiresAt = Date().addingTimeInterval(60)
        #expect(settings.shouldRefresh)
        #expect(store.reads > before)
    }

    /// Changing what Sentry is asked has to be visible as a change; changing something else must
    /// not be, or every preference costs a request. Both halves are the point, and the second is
    /// the one a careless edit breaks: fold `intervalSeconds` in and the app re-asks Sentry every
    /// time somebody moves a slider.
    @Test("The query shape tracks what shapes the query, and nothing else")
    func queryShapeTracksTheRightPreferences() {
        let fixture = fresh()
        let settings = fixture.settings
        defer { clean(fixture) }
        settings.organization = "example"
        settings.saveManualToken("t")

        var shape = settings.queryShape
        settings.window = .sevenDays
        #expect(settings.queryShape != shape, "the window shapes the query")

        shape = settings.queryShape
        settings.selectedProjectID = "11"
        #expect(settings.queryShape != shape, "the project shapes the query")

        shape = settings.queryShape
        settings.selectedEnvironment = "staging"
        #expect(settings.queryShape != shape, "the environment shapes the query")

        shape = settings.queryShape
        settings.maxIssues = 30
        #expect(settings.queryShape != shape, "the issue limit shapes the query")

        // The menu-bar metric decides which route the cheap cycle asks for, so a change has to
        // re-ask now, not at the next tick. That is exactly what belonging to the shape buys.
        shape = settings.queryShape
        settings.badgeMetric = .escalating
        #expect(settings.queryShape != shape, "the menu-bar metric shapes the query")

        // How often to ask is not part of what is asked, and neither is signing out and back in
        // to the same account.
        shape = settings.queryShape
        settings.intervalSeconds = 900
        #expect(settings.queryShape == shape, "the refresh interval must not cost a request")
    }

    /// A rate limit belongs to the token that earned it. Left behind on sign-out, the next
    /// session would sit silent waiting out somebody else's deadline, and the only symptom would
    /// be an app that fetched nothing and said nothing about why.
    @Test("Signing out forgets the rate limit along with the token")
    func signingOutClearsTheRateLimit() {
        let fixture = fresh()
        let settings = fixture.settings
        defer { clean(fixture) }
        settings.organization = "example"
        settings.saveManualToken("t")

        settings.askAgainAfter = Date().addingTimeInterval(300)
        #expect(settings.isRateLimited)

        settings.signOut()
        #expect(!settings.isRateLimited, "the next token starts with a clean slate")
        #expect(settings.askAgainAfter == nil)
    }

    /// A deadline in the past is not a rate limit. Reading it as one would silence the app for
    /// good after a single 429.
    @Test("A deadline that has passed is not a rate limit")
    func expiredDeadlineIsNotALimit() {
        let fixture = fresh()
        let settings = fixture.settings
        defer { clean(fixture) }

        settings.askAgainAfter = Date().addingTimeInterval(-1)
        #expect(!settings.isRateLimited)
        settings.askAgainAfter = Date().addingTimeInterval(30)
        #expect(settings.isRateLimited)
    }
}

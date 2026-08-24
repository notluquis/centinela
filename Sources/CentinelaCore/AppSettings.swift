import Foundation
import Observation

/// User preferences. The token is NOT in `UserDefaults`: it lives in the Keychain (see
/// `Keychain`). `UserDefaults` gets backed up and synced; a Sentry organization token should not.
///
/// This lives in `CentinelaCore` and not in the app target so the suite can exercise it. That is
/// not bookkeeping: the bug that made the panel say "not configured" while the menu bar was
/// happily showing errors was in here, and it was untestable where it used to live.
@MainActor
@Observable
public final class AppSettings {
    public enum AuthMethod: Equatable {
        case signedOut
        /// Obtained through the device flow, so it expires and gets renewed.
        case deviceFlow
        /// Pasted by hand. Sentry organization tokens do not expire on their own.
        case pastedToken
    }

    // `nonisolated` on all four: they are the default values of `init` parameters, and a
    // default value is evaluated at the CALL SITE, outside this type's actor. Without it the
    // compiler warns four times that a main actor-isolated static cannot be referenced from a
    // nonisolated context — the same trap AGENTS.md already records for `AppSettings()` as a
    // default, walked into again. They are immutable strings, so there is nothing to isolate.
    //
    // They did not show up locally because an incremental build does not re-emit warnings.
    /// The names before the rename to English. They are injectable for the same reason the
    /// current ones are: guarding the migration with `tokenAccount == defaultTokenAccount` kept
    /// tests away from a live session, and in doing so made the migration itself impossible to
    /// test. A branch that no test can reach is a branch nobody has run.
    nonisolated public static let legacyTokenAccount = "token-de-organizacion"
    nonisolated public static let legacyRefreshAccount = "token-de-refresco"

    nonisolated public static let defaultTokenAccount = "organization-token"
    nonisolated public static let defaultRefreshAccount = "refresh-token"

    public var organization: String {
        didSet { defaults.set(organization, forKey: "organization") }
    }

    public var host: String {
        didSet { defaults.set(host, forKey: "host") }
    }

    public var window: TimeWindow {
        didSet { defaults.set(window.rawValue, forKey: "window") }
    }

    /// Five minutes by default. With the measured API limits (40 requests per window per route,
    /// 25 concurrent) it could ask far more often; the ceiling is not Sentry but battery, plus
    /// the fact that an error from three minutes ago is not handled differently from one from
    /// five.
    public var intervalSeconds: TimeInterval {
        didSet { defaults.set(intervalSeconds, forKey: "intervalSeconds") }
    }

    public var maxIssues: Int {
        didSet { defaults.set(maxIssues, forKey: "maxIssues") }
    }

    /// OAuth client id for the device flow. Empty in `UserDefaults` means "use Centinela's", not
    /// "there is none". It is not a secret (RFC 8628 treats these clients as public), which is
    /// why it lives here and not in the Keychain.
    public var oauthClientID: String {
        didSet { defaults.set(oauthClientID, forKey: "oauthClientID") }
    }

    /// When the access token expires. Only applies to tokens obtained through OAuth; a pasted
    /// token does not expire on its own and this stays `nil`.
    public var tokenExpiresAt: Date? {
        didSet { defaults.set(tokenExpiresAt?.timeIntervalSince1970 ?? 0, forKey: "tokenExpiresAt") }
    }

    /// How long the token was good for when issued, so "less than 10% of its life" has meaning.
    public var tokenLife: TimeInterval {
        didSet { defaults.set(tokenLife, forKey: "tokenLife") }
    }

    /// The project to ask about, or `nil` for every one. Stored as the numeric id Sentry uses.
    public var selectedProjectID: String? {
        didSet { defaults.set(selectedProjectID ?? "", forKey: "selectedProject") }
    }

    /// The environment to ask about, or `nil` for every one. Today the organization has only
    /// `production`, so the control stays hidden until there is something to choose between.
    public var selectedEnvironment: String? {
        didSet { defaults.set(selectedEnvironment ?? "", forKey: "selectedEnvironment") }
    }

    /// The last thing the Keychain said when it refused. `nil` when the last write went fine.
    ///
    /// It exists because an earlier version used `try?` in both directions: a failed write left
    /// the UI showing "Saved to the Keychain" with its checkmark, having saved nothing, and the
    /// app sat at "not configured" forever with no error anywhere.
    public var lastStorageError: String?

    /// The access token, loaded once from the Keychain and kept here.
    ///
    /// **It is an observed stored property and that is the whole point.** It used to be a
    /// computed property backed by an `@ObservationIgnored` cache, which meant `isConfigured`
    /// depended on a value SwiftUI could not observe: the panel was built while the Keychain was
    /// empty, the token arrived later, and nothing ever told the panel to re-evaluate. The
    /// result was a menu bar cheerfully counting errors above a panel insisting the app was not
    /// configured. Reading the Keychain lazily from a view body was also the wrong shape: it is
    /// a synchronous system call and the body runs constantly.
    public private(set) var token: String

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let tokenAccount: String
    @ObservationIgnored private let refreshAccount: String
    @ObservationIgnored private let legacyTokenAccount: String
    @ObservationIgnored private let legacyRefreshAccount: String
    @ObservationIgnored private let store: SecretStore

    /// Exposed so a test can rebuild a second `AppSettings` over the same store.
    public var tokenAccountName: String { tokenAccount }
    public var refreshAccountName: String { refreshAccount }

    /// The Keychain accounts are injectable so tests and probes never touch the real ones. They
    /// were not, and a layout probe overwrote and then deleted a live session token.
    public init(
        defaults: UserDefaults = .standard,
        tokenAccount: String = AppSettings.defaultTokenAccount,
        refreshAccount: String = AppSettings.defaultRefreshAccount,
        legacyTokenAccount: String = AppSettings.legacyTokenAccount,
        legacyRefreshAccount: String = AppSettings.legacyRefreshAccount,
        store: SecretStore = KeychainStore()
    ) {
        self.defaults = defaults
        self.tokenAccount = tokenAccount
        self.refreshAccount = refreshAccount
        self.legacyTokenAccount = legacyTokenAccount
        self.legacyRefreshAccount = legacyRefreshAccount
        self.store = store
        AppSettings.renameOldKeys(in: defaults)
        organization = defaults.string(forKey: "organization") ?? ""
        host = defaults.string(forKey: "host") ?? "https://sentry.io"
        window = TimeWindow(rawValue: defaults.string(forKey: "window") ?? "") ?? .twentyFourHours
        let savedInterval = defaults.double(forKey: "intervalSeconds")
        intervalSeconds = savedInterval > 0 ? savedInterval : 300
        let savedMax = defaults.integer(forKey: "maxIssues")
        maxIssues = savedMax > 0 ? savedMax : 15
        let savedClient = defaults.string(forKey: "oauthClientID") ?? ""
        oauthClientID = savedClient.isEmpty ? DeviceFlow.centinelaClientID : savedClient
        let savedExpiry = defaults.double(forKey: "tokenExpiresAt")
        tokenExpiresAt = savedExpiry > 0 ? Date(timeIntervalSince1970: savedExpiry) : nil
        let savedLife = defaults.double(forKey: "tokenLife")
        tokenLife = savedLife > 0 ? savedLife : 3600
        let savedProject = defaults.string(forKey: "selectedProject") ?? ""
        selectedProjectID = savedProject.isEmpty ? nil : savedProject
        let savedEnvironment = defaults.string(forKey: "selectedEnvironment") ?? ""
        selectedEnvironment = savedEnvironment.isEmpty ? nil : savedEnvironment
        token = (try? store.read(account: tokenAccount)).flatMap { $0 } ?? ""
        if token.isEmpty { token = adoptTokenFromOldAccount() }
    }

    /// The preference keys were Spanish until they were not, and a rename that quietly forgets
    /// somebody's organization and refresh interval is not a rename, it is data loss.
    ///
    /// Copy rather than read-through: it runs once, the old key is removed, and after that
    /// nothing in the class has to know two names for the same thing.
    private static let renamedKeys = [
        ("organizacion", "organization"),
        ("ventana", "window"),
        ("intervaloSegundos", "intervalSeconds"),
        ("maximoIssues", "maxIssues"),
        ("clientIDOAuth", "oauthClientID"),
        ("venceElToken", "tokenExpiresAt"),
        ("vidaDelToken", "tokenLife"),
        ("proyectoElegido", "selectedProject"),
        ("entornoElegido", "selectedEnvironment")
    ]

    private static func renameOldKeys(in defaults: UserDefaults) {
        for (old, new) in renamedKeys where defaults.object(forKey: new) == nil {
            guard let value = defaults.object(forKey: old) else { continue }
            defaults.set(value, forKey: new)
            defaults.removeObject(forKey: old)
        }
    }

    /// The Keychain accounts were renamed with the preference keys, and this moves a session
    /// across instead of silently signing somebody out.
    ///
    /// It costs no extra password dialog: reading the new account finds no item at all, which
    /// never prompts, and reading the old one is the single read this init used to do anyway.
    private func adoptTokenFromOldAccount() -> String {
        guard let old = try? store.read(account: legacyTokenAccount),
              !old.isEmpty else { return "" }
        return move(old, from: legacyTokenAccount, to: tokenAccount)
    }

    /// Copies a secret to its new account and only then removes the old one.
    ///
    /// The order is the whole point. Written as `try? save` followed by an unconditional
    /// `delete`, a Keychain that refuses the write — which this project has documented refusing
    /// things — took the only copy with it and signed somebody out for good, silently. Keeping
    /// the old one costs a duplicate item until the next launch retries; losing it costs the
    /// session.
    private func move(_ secret: String, from old: String, to new: String) -> String {
        do {
            try store.save(secret, account: new)
        } catch {
            lastStorageError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return secret
        }
        try? store.delete(account: old)
        return secret
    }

    public var refreshToken: String? {
        if let current = (try? store.read(account: refreshAccount)).flatMap({ $0 }) { return current }
        // Migrated here and not in `init` on purpose: reading it is a Keychain read, and the whole
        // point of checking the clock first in `shouldRefresh` is to keep those off the startup
        // path. This runs the first time a renewal is actually due.
        guard let old = (try? store.read(account: legacyRefreshAccount)).flatMap({ $0 })
        else { return nil }
        return move(old, from: legacyRefreshAccount, to: refreshAccount)
    }

    /// Returns `true` when the Keychain accepted the write. Callers must NOT assume it did.
    @discardableResult
    public func saveToken(_ newToken: String) -> Bool {
        do {
            if newToken.isEmpty {
                try store.delete(account: tokenAccount)
            } else {
                try store.save(newToken, account: tokenAccount)
            }
            token = newToken
            lastStorageError = nil
            return true
        } catch {
            lastStorageError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Stores a token somebody pasted, and takes the app out of whatever OAuth session it was
    /// in. Separate from `saveToken` because that one is also the device flow's own write.
    ///
    /// Clearing the expiry and dropping the refresh token is not tidiness. `shouldRefresh` is
    /// true when there is an expiry in the past AND a refresh token, so pasting on top of a stale
    /// OAuth session left both behind and the next cycle renewed the old session straight over
    /// the token that had just been pasted.
    @discardableResult
    public func saveManualToken(_ newToken: String) -> Bool {
        guard saveToken(newToken) else { return false }
        tokenExpiresAt = nil
        try? store.delete(account: refreshAccount)
        return true
    }

    /// Stores what the device flow handed back. Returns `false` when the Keychain refused
    /// anything, same contract as `saveToken`.
    @discardableResult
    public func saveSession(_ grant: DeviceFlow.Grant) -> Bool {
        guard saveToken(grant.accessToken) else { return false }
        do {
            if let refresh = grant.refreshToken {
                try store.save(refresh, account: refreshAccount)
            }
            tokenLife = max(grant.expiresAt.timeIntervalSinceNow, 60)
            tokenExpiresAt = grant.expiresAt
            return true
        } catch {
            lastStorageError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    public func signOut() {
        saveToken("")
        try? store.delete(account: refreshAccount)
        tokenExpiresAt = nil
        // A rate limit belongs to the token that hit it. Left behind, signing in with a
        // different one would sit silent until a deadline earned by somebody else expired.
        askAgainAfter = nil
    }

    /// `true` when there is an OAuth session and the token has less than 10% of its life left.
    /// The clock is consulted before the Keychain, and the order is the whole point.
    ///
    /// `refreshToken` is a Keychain read, this runs on every cycle, and with no team identifier
    /// every Keychain read after an update costs a password dialog. Asking whether a renewal is
    /// even due first turns two dialogs per update into one, and takes a synchronous system call
    /// off a path that runs every five minutes for the ninety-odd per cent of a token's life when
    /// there is nothing to renew.
    public var shouldRefresh: Bool {
        guard let expiresAt = tokenExpiresAt,
              DeviceFlow.shouldRefresh(expiresAt: expiresAt, life: tokenLife) else { return false }
        return refreshToken != nil
    }

    /// Which of the two ways in produced the token being held.
    ///
    /// Derived from stored state on purpose. `LoginController.stage` is session state and resets
    /// to `.idle` on every launch, so a UI driven by it offers "Sign in" to somebody who is
    /// already signed in and hides their way back out. `token` and `tokenExpiresAt` are both
    /// observed and both survive a restart.
    ///
    /// `refreshToken` is deliberately not part of this: reading it hits the Keychain, and a view
    /// body evaluates this on every render.
    public var authMethod: AuthMethod {
        if token.isEmpty { return .signedOut }
        return tokenExpiresAt == nil ? .pastedToken : .deviceFlow
    }

    /// Everything that changes WHAT Sentry is asked, as one comparable value.
    ///
    /// Changing the window, the project, the environment or the issue limit used to change
    /// nothing on screen until the next cycle, up to five minutes later: the value was stored,
    /// the panel kept showing the answer to the previous question, and the only clue was that
    /// the numbers did not match the controls. Views key their work on this so a change is a
    /// change, and a preference that does not shape a query — the refresh interval, launch at
    /// login — deliberately stays out of it and does not cost a request.
    public struct QueryShape: Equatable, Sendable {
        public let configured: Bool
        let window: TimeWindow
        let project: String?
        let environment: String?
        let maxIssues: Int
    }

    public var queryShape: QueryShape {
        QueryShape(
            configured: isConfigured,
            window: window,
            project: selectedProjectID,
            environment: selectedEnvironment,
            maxIssues: maxIssues
        )
    }

    /// When Sentry said not to ask again before, or `nil` when it has not said so.
    ///
    /// Not persisted: a rate limit is measured in seconds and the app can be closed for days, so
    /// carrying it across launches would only ever delay a cycle that Sentry would have accepted.
    public var askAgainAfter: Date?

    /// `true` while Sentry's own `Retry-After` has not elapsed. Asking anyway is what that header
    /// exists to prevent, and the answer would be another 429.
    public var isRateLimited: Bool {
        guard let until = askAgainAfter else { return false }
        return until > Date()
    }

    public var isConfigured: Bool { !organization.isEmpty && !token.isEmpty }

    public func credentials() -> Credentials? {
        guard !token.isEmpty, !organization.isEmpty, let url = URL(string: host) else { return nil }
        return Credentials(token: token, organization: organization, host: url)
    }
}

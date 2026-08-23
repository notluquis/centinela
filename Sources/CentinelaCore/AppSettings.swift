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
    public static let defaultTokenAccount = "token-de-organizacion"
    public static let defaultRefreshAccount = "token-de-refresco"

    public var organization: String {
        didSet { defaults.set(organization, forKey: "organizacion") }
    }

    public var host: String {
        didSet { defaults.set(host, forKey: "host") }
    }

    public var window: TimeWindow {
        didSet { defaults.set(window.rawValue, forKey: "ventana") }
    }

    /// Five minutes by default. With the measured API limits (40 requests per window per route,
    /// 25 concurrent) it could ask far more often; the ceiling is not Sentry but battery, plus
    /// the fact that an error from three minutes ago is not handled differently from one from
    /// five.
    public var intervalSeconds: TimeInterval {
        didSet { defaults.set(intervalSeconds, forKey: "intervaloSegundos") }
    }

    public var maxIssues: Int {
        didSet { defaults.set(maxIssues, forKey: "maximoIssues") }
    }

    /// OAuth client id for the device flow. Empty in `UserDefaults` means "use Centinela's", not
    /// "there is none". It is not a secret (RFC 8628 treats these clients as public), which is
    /// why it lives here and not in the Keychain.
    public var oauthClientID: String {
        didSet { defaults.set(oauthClientID, forKey: "clientIDOAuth") }
    }

    /// When the access token expires. Only applies to tokens obtained through OAuth; a pasted
    /// token does not expire on its own and this stays `nil`.
    public var tokenExpiresAt: Date? {
        didSet { defaults.set(tokenExpiresAt?.timeIntervalSince1970 ?? 0, forKey: "venceElToken") }
    }

    /// How long the token was good for when issued, so "less than 10% of its life" has meaning.
    public var tokenLife: TimeInterval {
        didSet { defaults.set(tokenLife, forKey: "vidaDelToken") }
    }

    /// The project to ask about, or `nil` for every one. Stored as the numeric id Sentry uses.
    public var selectedProjectID: String? {
        didSet { defaults.set(selectedProjectID ?? "", forKey: "proyectoElegido") }
    }

    /// The environment to ask about, or `nil` for every one. Today the organization has only
    /// `production`, so the control stays hidden until there is something to choose between.
    public var selectedEnvironment: String? {
        didSet { defaults.set(selectedEnvironment ?? "", forKey: "entornoElegido") }
    }

    /// The last thing the Keychain said when it refused. `nil` when the last write went fine.
    ///
    /// It exists because an earlier version used `try?` in both directions: a failed write left
    /// the UI showing "Saved to the Keychain" with its checkmark, having saved nothing, and the
    /// app sat at "not configured" forever with no error anywhere.
    /// The last thing the Keychain said when it refused. `nil` when the last write went fine.
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

    /// Exposed so a test can rebuild a second `AppSettings` over the same store.
    public var tokenAccountName: String { tokenAccount }
    public var refreshAccountName: String { refreshAccount }

    /// The Keychain accounts are injectable so tests and probes never touch the real ones. They
    /// were not, and a layout probe overwrote and then deleted a live session token.
    public init(
        defaults: UserDefaults = .standard,
        tokenAccount: String = AppSettings.defaultTokenAccount,
        refreshAccount: String = AppSettings.defaultRefreshAccount
    ) {
        self.defaults = defaults
        self.tokenAccount = tokenAccount
        self.refreshAccount = refreshAccount
        organization = defaults.string(forKey: "organizacion") ?? ""
        host = defaults.string(forKey: "host") ?? "https://sentry.io"
        window = TimeWindow(rawValue: defaults.string(forKey: "ventana") ?? "") ?? .twentyFourHours
        let savedInterval = defaults.double(forKey: "intervaloSegundos")
        intervalSeconds = savedInterval > 0 ? savedInterval : 300
        let savedMax = defaults.integer(forKey: "maximoIssues")
        maxIssues = savedMax > 0 ? savedMax : 15
        let savedClient = defaults.string(forKey: "clientIDOAuth") ?? ""
        oauthClientID = savedClient.isEmpty ? DeviceFlow.centinelaClientID : savedClient
        let savedExpiry = defaults.double(forKey: "venceElToken")
        tokenExpiresAt = savedExpiry > 0 ? Date(timeIntervalSince1970: savedExpiry) : nil
        let savedLife = defaults.double(forKey: "vidaDelToken")
        tokenLife = savedLife > 0 ? savedLife : 3600
        let savedProject = defaults.string(forKey: "proyectoElegido") ?? ""
        selectedProjectID = savedProject.isEmpty ? nil : savedProject
        let savedEnvironment = defaults.string(forKey: "entornoElegido") ?? ""
        selectedEnvironment = savedEnvironment.isEmpty ? nil : savedEnvironment
        token = (try? Keychain.read(account: tokenAccount)).flatMap { $0 } ?? ""
    }

    public var refreshToken: String? {
        (try? Keychain.read(account: refreshAccount)).flatMap { $0 }
    }

    /// Returns `true` when the Keychain accepted the write. Callers must NOT assume it did.
    @discardableResult
    public func saveToken(_ newToken: String) -> Bool {
        do {
            if newToken.isEmpty {
                try Keychain.delete(account: tokenAccount)
            } else {
                try Keychain.save(newToken, account: tokenAccount)
            }
            token = newToken
            lastStorageError = nil
            return true
        } catch {
            lastStorageError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Stores what the device flow handed back. Returns `false` when the Keychain refused
    /// anything, same contract as `saveToken`.
    @discardableResult
    public func saveSession(_ grant: DeviceFlow.Grant) -> Bool {
        guard saveToken(grant.accessToken) else { return false }
        do {
            if let refresh = grant.refreshToken {
                try Keychain.save(refresh, account: refreshAccount)
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
        try? Keychain.delete(account: refreshAccount)
        tokenExpiresAt = nil
    }

    /// `true` when there is an OAuth session and the token has less than 10% of its life left.
    public var shouldRefresh: Bool {
        guard let expiresAt = tokenExpiresAt, refreshToken != nil else { return false }
        return DeviceFlow.shouldRefresh(expiresAt: expiresAt, life: tokenLife)
    }

    public var isConfigured: Bool { !organization.isEmpty && !token.isEmpty }

    public func credentials() -> Credentials? {
        guard !token.isEmpty, !organization.isEmpty, let url = URL(string: host) else { return nil }
        return Credentials(token: token, organization: organization, host: url)
    }
}

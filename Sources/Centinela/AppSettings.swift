import CentinelaCore
import Foundation
import Observation

/// User preferences. The token is NOT here: it lives in the Keychain (see `Keychain`).
/// `UserDefaults` gets backed up and synced; a Sentry organization token should not.
@MainActor
@Observable
final class AppSettings {
    static let tokenAccount = "token-de-organizacion"
    static let refreshAccount = "token-de-refresco"

    var organization: String {
        didSet { defaults.set(organization, forKey: "organizacion") }
    }

    var host: String {
        didSet { defaults.set(host, forKey: "host") }
    }

    var window: TimeWindow {
        didSet { defaults.set(window.rawValue, forKey: "ventana") }
    }

    /// Five minutes by default. With the measured API limits (40 requests per window per route,
    /// 25 concurrent) it could ask far more often; the ceiling is not Sentry but battery, plus
    /// the fact that an error from three minutes ago is not handled differently from one from
    /// five.
    var intervalSeconds: TimeInterval {
        didSet { defaults.set(intervalSeconds, forKey: "intervaloSegundos") }
    }

    var maxIssues: Int {
        didSet { defaults.set(maxIssues, forKey: "maximoIssues") }
    }

    /// OAuth client id for the device flow. Empty in `UserDefaults` means "use Centinela's",
    /// not "there is none". It is not a secret (RFC 8628 treats these clients as public), which
    /// is why it lives here and not in the Keychain.
    var oauthClientID: String {
        didSet { defaults.set(oauthClientID, forKey: "clientIDOAuth") }
    }

    /// When the access token expires. Only applies to tokens obtained through OAuth; a pasted
    /// token does not expire on its own and this stays `nil`.
    var tokenExpiresAt: Date? {
        didSet { defaults.set(tokenExpiresAt?.timeIntervalSince1970 ?? 0, forKey: "venceElToken") }
    }

    /// How long the token was good for when issued, so "less than 10% of its life" has meaning.
    var tokenLife: TimeInterval {
        didSet { defaults.set(tokenLife, forKey: "vidaDelToken") }
    }

    /// The last thing the Keychain said when it refused. `nil` when the last write went fine.
    ///
    /// It exists because the previous version of this used `try?` in both directions: a failed
    /// write left the UI showing "Saved to the Keychain" with its checkmark, having saved
    /// nothing, and the app sat at "not configured" forever with no error anywhere. The failure
    /// mode is not theoretical: an ad-hoc signature carries no `application-identifier`, and
    /// without one the Keychain access group may not exist (`errSecMissingEntitlement`, -34018).
    var lastKeychainError: String?

    @ObservationIgnored private let defaults: UserDefaults

    /// In-memory copy of the token. The Keychain is a synchronous system call and `token` is
    /// read by `isConfigured`, which SwiftUI re-evaluates on EVERY draw of the panel: without
    /// this cache the panel hits the Keychain dozens of times a second while it is open.
    @ObservationIgnored private var cachedToken: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
    }

    var token: String {
        if let cachedToken { return cachedToken }
        let value = (try? Keychain.read(account: Self.tokenAccount)).flatMap { $0 } ?? ""
        cachedToken = value
        return value
    }

    var refreshToken: String? {
        (try? Keychain.read(account: Self.refreshAccount))
    }

    /// Returns `true` when the Keychain accepted the write. Callers must NOT assume it did.
    @discardableResult
    func saveToken(_ newToken: String) -> Bool {
        do {
            if newToken.isEmpty {
                try Keychain.delete(account: Self.tokenAccount)
            } else {
                try Keychain.save(newToken, account: Self.tokenAccount)
            }
            cachedToken = newToken
            lastKeychainError = nil
            return true
        } catch {
            cachedToken = nil
            lastKeychainError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Stores what the device flow handed back. Returns `false` when the Keychain refused
    /// anything, same contract as `saveToken`.
    @discardableResult
    func saveSession(_ grant: DeviceFlow.Grant) -> Bool {
        guard saveToken(grant.accessToken) else { return false }
        do {
            if let refresh = grant.refreshToken {
                try Keychain.save(refresh, account: Self.refreshAccount)
            }
            tokenLife = max(grant.expiresAt.timeIntervalSinceNow, 60)
            tokenExpiresAt = grant.expiresAt
            return true
        } catch {
            lastKeychainError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func signOut() {
        saveToken("")
        try? Keychain.delete(account: Self.refreshAccount)
        tokenExpiresAt = nil
    }

    /// `true` when there is an OAuth session and the token has less than 10% of its life left.
    var shouldRefresh: Bool {
        guard let expiresAt = tokenExpiresAt, refreshToken != nil else { return false }
        return DeviceFlow.shouldRefresh(expiresAt: expiresAt, life: tokenLife)
    }

    var isConfigured: Bool { !organization.isEmpty && !token.isEmpty }

    func credentials() -> Credentials? {
        let current = token
        guard !current.isEmpty, !organization.isEmpty, let url = URL(string: host) else { return nil }
        return Credentials(token: current, organization: organization, host: url)
    }
}

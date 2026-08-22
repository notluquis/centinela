import AppKit
import CentinelaCore
import Observation

/// Drives the device flow from the UI and stores the result.
@MainActor
@Observable
final class LoginController {
    enum Stage: Equatable {
        case idle
        case requestingCode
        case waitingForApproval(code: String, url: URL)
        case done
        case failed(String)
    }

    private(set) var stage: Stage = .idle

    /// Filled in when the token reaches more than one organization and someone has to pick.
    private(set) var organizationsToPick: [Organization] = []

    private let settings: AppSettings
    @ObservationIgnored private var task: Task<Void, Never>?

    init(settings: AppSettings) { self.settings = settings }

    var inProgress: Bool {
        switch stage {
        case .requestingCode, .waitingForApproval: true
        default: false
        }
    }

    private var flow: DeviceFlow {
        DeviceFlow(
            host: URL(string: settings.host) ?? URL(string: "https://sentry.io")!,
            clientID: settings.oauthClientID
        )
    }

    func signIn() {
        cancel()
        stage = .requestingCode
        let flow = flow
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let code = try await flow.requestCode()
                stage = .waitingForApproval(code: code.userCode, url: code.verificationURL)
                // The URL with the code already embedded is opened when the server sends it, so
                // the person approves with a click instead of typing eight characters. The code
                // is shown anyway, because the browser may open on another profile with no
                // session.
                NSWorkspace.shared.open(code.completeURL ?? code.verificationURL)

                let grant = try await flow.waitForApproval(code)
                guard settings.saveSession(grant) else {
                    stage = .failed(settings.lastKeychainError ?? "could not write to the Keychain")
                    return
                }
                await resolveOrganization()
                stage = .done
            } catch is CancellationError {
                stage = .idle
            } catch {
                stage = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// The device flow hands back a token and NOTHING ELSE: no organization, no project.
    ///
    /// Without this step, someone signed in successfully and the app kept showing "not
    /// configured" forever, because `AppSettings.isConfigured` requires an organization and no
    /// layer reported an error: the token was stored, the stage said `.done`, and the cycle bailed
    /// out at `guard let client`. A silent failure with everything green.
    private func resolveOrganization() async {
        guard settings.organization.isEmpty else { return }
        // The organization is deliberately empty: this call does NOT hang off one, and it is
        // precisely the call made to find out which one it is.
        let credentials = Credentials(
            token: settings.token,
            organization: "",
            host: URL(string: settings.host) ?? URL(string: "https://sentry.io")!
        )

        do {
            let organizations = try await SentryClient(credentials: credentials).organizations()
            switch organizations.count {
            case 0:
                stage = .failed("The token does not reach any organization.")
            case 1:
                settings.organization = organizations[0].slug
            default:
                // With several there is nothing to guess: they are shown and someone picks.
                organizationsToPick = organizations
            }
        } catch {
            stage = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func pick(_ organization: Organization) {
        settings.organization = organization.slug
        organizationsToPick = []
    }

    func cancel() {
        task?.cancel()
        task = nil
        stage = .idle
    }

    /// Renews the token when little life is left. Returns the error when there was one, so the
    /// caller decides where to show it.
    ///
    /// It is called before each cycle rather than on its own timer: if the app was asleep for
    /// three days, what matters is renewing when it comes back, not having tried while there
    /// was no network.
    @discardableResult
    func refreshIfNeeded() async -> String? {
        guard settings.shouldRefresh, let refreshToken = settings.refreshToken else { return nil }
        do {
            settings.saveSession(try await flow.refresh(refreshToken))
            return nil
        } catch {
            // A failed renewal does NOT sign the user out: there may simply be no network. The
            // old token stays stored and the next cycle tries again. If it really was revoked,
            // the API answers 401 and that does get shown.
            //
            // And `stage` is NOT touched: that is what the Settings window looks at, so a
            // two-second network blip during a background cycle would flip "Signed in" to an
            // error with a retry button, which is a lie. The notice goes to the panel, alongside
            // the rest of the network errors.
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

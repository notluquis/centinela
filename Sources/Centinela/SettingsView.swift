import CentinelaCore
import SwiftUI

/// Settings window with tabs, which is the macOS convention for a menu bar app's preferences
/// (Stats and TheBoringNotch do the same with a sidebar, the variant for many more sections
/// than these three).
struct SettingsView: View {
    let state: AppState

    var body: some View {
        // `.tabItem` rather than the `Tab` type: that one arrived in macOS 15 and the
        // deployment target is 14. They look the same.
        TabView {
            AccountTab(state: state)
                .tabItem { Label("Account", systemImage: "person.badge.key") }
            QueryTab(state: state)
                .tabItem { Label("Query", systemImage: "slider.horizontal.3") }
            AboutView(state: state)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 430)
    }
}

// MARK: - Account

private struct AccountTab: View {
    let state: AppState
    @State private var token = ""
    @State private var saved = false

    private var settings: AppSettings { state.settings }
    private var login: LoginController { state.login }

    var body: some View {
        Form {
            Section("Organization") {
                TextField("Slug", text: Binding(
                    get: { settings.organization },
                    set: { settings.organization = $0.trimmingCharacters(in: .whitespaces) }
                ))
                .help("The slug in the URL: sentry.io/organizations/HERE/")

                TextField("Server", text: Binding(
                    get: { settings.host },
                    set: { settings.host = $0.trimmingCharacters(in: .whitespaces) }
                ))
            }

            Section("Signing in") {
                switch login.stage {
                case .waitingForApproval(let code, let url):
                    LabeledContent("Code") {
                        Text(code)
                            .font(.system(.title3, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Text("Approve it in the browser. If it did not open by itself, go to"
                        + " \(url.absoluteString) and type the code.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Cancel", role: .cancel, action: login.cancel)

                case .requestingCode:
                    HStack { ProgressView().controlSize(.small); Text("Requesting a code…") }

                case .done:
                    Label("Signed in. Sentry granted only the read scopes it was asked for.",
                          systemImage: "checkmark.seal")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    if !login.organizationsToPick.isEmpty {
                        Picker("Pick the organization", selection: Binding(
                            get: { settings.organization },
                            set: { picked in
                                if let org = login.organizationsToPick.first(where: { $0.slug == picked }) {
                                    login.pick(org)
                                }
                            }
                        )) {
                            Text("Not picked").tag("")
                            ForEach(login.organizationsToPick) { Text($0.name).tag($0.slug) }
                        }
                    }
                    Button("Sign out", role: .destructive) { settings.signOut() }

                case .failed(let error):
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again", action: login.signIn)

                case .idle:
                    Button("Sign in with Sentry", action: login.signIn)
                        .disabled(settings.oauthClientID.isEmpty)
                }

                TextField("OAuth client", text: Binding(
                    get: { settings.oauthClientID },
                    set: { settings.oauthClientID = $0.trimmingCharacters(in: .whitespaces) }
                ))
                .help("Centinela's is filled in. Change it only if you registered your own.")
            }

            Section("Or paste a token") {
                SecureField("Token", text: $token)
                HStack {
                    Button("Save token") {
                        // The checkmark is only drawn when the Keychain accepted. See
                        // `AppSettings.lastKeychainError`.
                        saved = settings.saveToken(token.trimmingCharacters(in: .whitespaces))
                        if saved {
                            token = ""
                            Task {
                                await state.checkTokenPower()
                                await state.refreshCheap()
                            }
                        }
                    }
                    .disabled(token.isEmpty)

                    if saved {
                        Label("Saved to the Keychain", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear", role: .destructive) {
                        settings.signOut()
                        token = ""
                        saved = false
                    }
                }
                if let error = settings.lastKeychainError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Give it only `org:read`, `project:read` and `event:read`: Centinela writes"
                    + " nothing to Sentry. The token is stored in the Keychain, never in a file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Query

private struct QueryTab: View {
    let state: AppState
    @State private var launchAtLogin = LaunchAtLogin()

    private var settings: AppSettings { state.settings }

    var body: some View {
        Form {
            Section {
                Picker("Window", selection: Binding(
                    get: { settings.window },
                    set: { settings.window = $0 }
                )) {
                    ForEach(TimeWindow.allCases, id: \.self) { Text($0.label).tag($0) }
                }

                Picker("Refresh every", selection: Binding(
                    get: { settings.intervalSeconds },
                    set: { settings.intervalSeconds = $0; state.reschedule() }
                )) {
                    Text("1 minute").tag(TimeInterval(60))
                    Text("5 minutes").tag(TimeInterval(300))
                    Text("15 minutes").tag(TimeInterval(900))
                    Text("1 hour").tag(TimeInterval(3600))
                }

                Stepper("Show \(settings.maxIssues) issues", value: Binding(
                    get: { settings.maxIssues },
                    set: { settings.maxIssues = $0 }
                ), in: 5...50, step: 5)
            } footer: {
                Text("Each cycle asks for two cheap routes (the error series and uptime status)."
                    + " The issue list, which is ten times heavier, is only fetched when the"
                    + " panel opens. Sentry offers no webhooks to a desktop app: its"
                    + " notifications need a publicly reachable URL.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("System") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.toggle($0) }
                ))
                if launchAtLogin.needsApproval {
                    HStack {
                        Text("Still needs approval in System Settings. An app cannot approve itself.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open", action: launchAtLogin.openSystemSettings)
                    }
                }
                if let error = launchAtLogin.lastError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}

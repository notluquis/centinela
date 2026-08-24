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
        .task { await state.loadEnvironments() }
        // On the window and not inside a tab. It lived on the Account tab's `Form`, and a
        // `TabView` does not keep the tabs nobody is looking at alive, so changing the window or
        // the project — which happens on the Query tab — reached nothing. Here it is alive for
        // as long as Settings is open, which is exactly as long as any of this can be changed.
        .onChange(of: state.settings.queryShape) { was, now in
            guard now.configured else { return }
            Task {
                // Only when a session appears, not on every change of shape. Whether the token
                // reaches the audit log is a fact about the token, and asking again because
                // somebody moved the window picker spends a request on the wrong question — the
                // one route in this app that exists to check permissions, on a control that
                // changes none.
                if !was.configured { await state.checkTokenPower() }
                await state.refreshCheap()
            }
        }
    }
}

// MARK: - Account

/// The account tab branches on `AppSettings.authMethod`, never on `LoginController.stage`.
///
/// The stage is session state: it resets to `.idle` on every launch, so the previous version
/// showed "Sign in with Sentry" to somebody who was already signed in, and put the only way back
/// out inside a branch that only existed right after a fresh device flow. The stage is still
/// used, but only for what it actually knows: the transient steps of a sign-in in progress.
private struct AccountTab: View {
    let state: AppState
    @State private var token = ""
    @State private var offerTokenField = false

    private var settings: AppSettings { state.settings }
    private var login: LoginController { state.login }

    var body: some View {
        Form {
            Section("Account") {
                account
                if let error = settings.lastStorageError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                TextField("Organization", text: Binding(
                    get: { settings.organization },
                    set: { settings.organization = $0.trimmingCharacters(in: .whitespaces) }
                ))
                .help("The slug in the URL: sentry.io/organizations/HERE/")
                TextField("Server", text: Binding(
                    get: { settings.host },
                    set: { settings.host = $0.trimmingCharacters(in: .whitespaces) }
                ))
                TextField("OAuth client", text: Binding(
                    get: { settings.oauthClientID },
                    set: { settings.oauthClientID = $0.trimmingCharacters(in: .whitespaces) }
                ))
                .help("Centinela's is filled in. Change it only if you registered your own.")
            } header: {
                Text("Connection")
            } footer: {
                Caption("Signing in with Sentry fills the organization in; a pasted token needs"
                    + " it typed. All three stay editable while signed in.")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var account: some View {
        switch settings.authMethod {
        case .signedOut:
            signingIn
        case .deviceFlow:
            signedIn("Signed in with Sentry", detail: expiry)
        case .pastedToken:
            signedIn("Signed in with a pasted token",
                     detail: "A pasted token does not expire on its own. Revoke it in Sentry to"
                        + " end it there as well.")
        }
    }

    /// One body for both signed-in states, so the way out is the same button, with the same
    /// label, in the same place, whichever way somebody got in.
    @ViewBuilder private func signedIn(_ title: String, detail: String) -> some View {
        Label(title, systemImage: "checkmark.seal")
            .fixedSize(horizontal: false, vertical: true)
        Caption(detail)
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
        Button("Sign out", role: .destructive, action: signOut)
    }

    /// Only reached while signed out. The two ways in are offered one at a time: the device flow
    /// is the front door and the token field is behind a disclosure, so there is never a screen
    /// showing both with no way to tell which one is in effect.
    @ViewBuilder private var signingIn: some View {
        switch login.stage {
        case .requestingCode:
            HStack { ProgressView().controlSize(.small); Text("Requesting a code…") }

        case .waitingForApproval(let code, let url):
            LabeledContent("Code") {
                Text(code).font(.system(.title3, design: .monospaced)).textSelection(.enabled)
            }
            Caption("Approve it in the browser. If it did not open by itself, go to"
                + " \(url.absoluteString) and type the code.")
            Button("Cancel", role: .cancel, action: login.cancel)

        case .failed(let error):
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again", action: login.signIn)

        case .idle, .done:
            Button("Sign in with Sentry", action: login.signIn)
                .disabled(settings.oauthClientID.isEmpty)
            DisclosureGroup("Use a token instead", isExpanded: $offerTokenField) {
                SecureField("Token", text: $token)
                Button("Save token", action: saveToken).disabled(token.isEmpty)
            }
            Caption("Either way Centinela gets only `org:read`, `project:read` and `event:read`,"
                + " and keeps the token in the Keychain — never in `UserDefaults`, never in a"
                + " file.")
        }
    }

    private var expiry: String {
        guard let expiresAt = settings.tokenExpiresAt else { return "" }
        let formatter = RelativeDateTimeFormatter()
        return "Renews by itself. The current token expires"
            + " \(formatter.localizedString(for: expiresAt, relativeTo: Date()))."
    }

    private func saveToken() {
        // No checkmark: on success the section itself switches to the signed-in body, which is
        // the feedback. A checkmark next to a field that had not changed was how an earlier
        // version claimed a write the Keychain had refused.
        guard settings.saveManualToken(token.trimmingCharacters(in: .whitespaces)) else { return }
        token = ""
        offerTokenField = false
    }

    private func signOut() {
        settings.signOut()
        login.cancel()
        // Straight away, not at the next cycle five minutes from now.
        state.forgetSession()
        token = ""
        offerTokenField = false
    }
}

/// Secondary explanatory text. Every one of these was the same four modifiers.
private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(.init(text))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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

                Picker("Project", selection: Binding(
                    get: { settings.selectedProjectID ?? "" },
                    set: { settings.selectedProjectID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("All projects").tag("")
                    ForEach(state.data.errorsByProject) { entry in
                        Text(entry.slug ?? entry.projectID).tag(entry.projectID)
                    }
                }

                // Only offered when there is something to choose between. With a single
                // environment the control would be a dropdown with one entry, and picking it
                // would change nothing.
                if state.data.environments.count > 1 {
                    Picker("Environment", selection: Binding(
                        get: { settings.selectedEnvironment ?? "" },
                        set: { settings.selectedEnvironment = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("All environments").tag("")
                        ForEach(state.data.environments, id: \.self) { Text($0).tag($0) }
                    }
                }
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

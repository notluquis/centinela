import AppKit
import CentinelaCore
import SwiftUI

/// The "About" tab, with the same content Stats and TheBoringNotch put in theirs: which version
/// is running, where the code lives, and whether something newer is out.
struct AboutView: View {
    private static let license = URL(
        string: "https://github.com/\(AppState.repository)/blob/main/LICENSE"
    )!
    private static let releases = URL(
        string: "https://github.com/\(AppState.repository)/releases"
    )!

    let state: AppState
    @State private var updater = Updater()

    var body: some View {
        VStack(spacing: 14) {
            if let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
                    // Decoration. The name is right underneath it, and VoiceOver reading an app
                    // icon adds a stop that says nothing the next line does not.
                    .accessibilityHidden(true)
            }
            Text("Centinela").font(.title2.weight(.semibold))
            Text("Version \(state.installedVersion)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            // The releases page rather than this version's tag. A development build reports
            // 0.0.0, and a link that 404s from inside the app is worse than one that lands on a
            // list with the newest at the top.
            Link("What is new", destination: Self.releases)
                .font(.callout)

            Button("Check for updates", action: updater.checkNow)
                .disabled(!updater.canCheck)

            if let last = updater.lastCheck {
                Text("Last checked \(last, format: .relative(presentation: .numeric))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // This said the ad-hoc signature was not in the way. Builds stopped being ad-hoc in
            // 0.5.0 — they carry a self-signed certificate now — so the sentence described a
            // version of the app that no longer existed, in the app itself.
            Text("Updates are verified with an EdDSA signature of this project's own, not with an"
                + " Apple certificate. The build is signed with a self-signed certificate, which"
                + " is not a Developer ID: macOS still asks for right click, Open the first time.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Link("Source", destination: URL(string: "https://github.com/\(AppState.repository)")!)
                Link("MIT licence", destination: Self.license)
                Link("Report something", destination: URL(string: "https://github.com/\(AppState.repository)/issues")!)
            }
            .font(.callout)

            Text("Not affiliated with Sentry (Functional Software, Inc.). Uses its public read API.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

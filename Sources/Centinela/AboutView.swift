import AppKit
import CentinelaCore
import SwiftUI

/// The "About" tab, with the same content Stats and TheBoringNotch put in theirs: which version
/// is running, where the code lives, and whether something newer is out.
struct AboutView: View {
    private static let license = URL(
        string: "https://github.com/\(AppState.repository)/blob/main/LICENSE"
    )!

    let state: AppState
    @State private var updater = Updater()

    var body: some View {
        VStack(spacing: 14) {
            if let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }
            Text("Centinela").font(.title2.weight(.semibold))
            Text("Version \(state.installedVersion)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Button("Check for updates", action: updater.checkNow)
                .disabled(!updater.canCheck)

            if let last = updater.lastCheck {
                Text("Last checked \(last, format: .relative(presentation: .numeric))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("Updates are verified with an EdDSA signature of our own, not with an Apple"
                + " certificate, so the ad-hoc signature is not in the way.")
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

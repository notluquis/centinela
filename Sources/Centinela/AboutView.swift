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
    @State private var checking = false

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

            if let update = state.update {
                Link("Version \(update.version.description) is out", destination: update.page)
                    .font(.callout)
            } else {
                HStack(spacing: 6) {
                    if checking { ProgressView().controlSize(.small) }
                    Button("Check for updates") {
                        checking = true
                        Task {
                            await state.checkForUpdate(force: true)
                            checking = false
                        }
                    }
                    .disabled(checking)
                }
            }

            // Not Sparkle: its sandboxing documentation says an ad-hoc signature is not suitable
            // for distribution, and it wants `Installer.xpc` embedded plus two `mach-lookup`
            // exceptions. This tells you and opens the page; downloading and replacing is yours.
            Text("Centinela tells you about new versions, it does not update itself: the"
                + " signature is ad-hoc and an automatic installer would hit Gatekeeper anyway.")
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

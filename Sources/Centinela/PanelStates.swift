import CentinelaCore
import SwiftUI

// What the panel shows when it has nothing from Sentry to show. Three different statements that
// were one before: there is no session yet, the answer has not arrived, and the answer was
// nothing. Split out of `PanelRows.swift` when that file crossed 400 lines, along the seam that
// means something — rows that draw data on one side, everything drawn in place of data on the
// other.

/// A sub-header inside a section ("Errors by project", "Replays", "Slowest by p95"). One place so
/// the three of them share a weight, a colour and a rhythm instead of each section inventing its
/// own — they had drifted to two different font sizes.
struct SectionHeader: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            // Uppercase and letter-spaced, the way Stats and iStat Menus label the bands inside a
            // menu-bar panel ("USAGE HISTORY", "DETAILS"). It reads as a divider between kinds of
            // rows rather than as one more row of content.
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 3)
    }
}

struct Notice: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            // `fixedSize` so a long deprecation notice wraps instead of truncating: inside a
            // fixed-width container a `Text` prefers a single line unless told it may grow down.
            Text(text).font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        // A tinted, bordered banner rather than loose text: a notice is something the reader has
        // to see (an over-privileged token, a route Sentry is retiring), so it carries its own
        // surface instead of floating over the list like one more row.
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(0.22), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

struct NotConfigured: View {
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // The sentinel, not looking at anything yet. Echoes the crossed-out eye the menu
                // bar shows in this same state.
                Image(systemName: "binoculars")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text("Not configured yet").font(.headline)
            }
            Text("Centinela needs your Sentry organization and a read-only token.")
                .font(.callout)
                .foregroundStyle(.secondary)
                // Without this the text truncates with an ellipsis instead of wrapping: inside
                // a fixed-width container a `Text` prefers a single line unless told it may
                // grow downwards.
                .fixedSize(horizontal: false, vertical: true)
            // The one thing to do here, so it gets the prominent style.
            Button("Open Settings", action: open)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }
}

/// Everything that answers "is anything on fire right now": uptime, cron monitors, crash-free
/// sessions and where the errors are coming from.
///
/// They are one section rather than four segments because they are one question. Splitting them
/// would put "Crons" next to "Releases" as if a person browsing had to choose between them.

struct PlaceholderRows: View {
    /// How many lines each row has, so the block matches the section it stands in for: three for
    /// an issue (title, culprit, metadata), two for a release or a transaction.
    let lines: Int
    var count: Int = 3

    var body: some View {
        ForEach(0..<count, id: \.self) { row in
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.caption)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    // Widths vary per row. Three identical blocks read as a rendering artefact
                    // rather than as text that has not arrived; real titles are never the same
                    // length twice.
                    // Clamped, and not for tidiness: `String(repeating:count:)` traps on a
                    // negative count, so `28 - row * 5` crashes the panel from the seventh row
                    // on. Nothing asks for seven today, and `count` is a parameter, so today is
                    // the only thing standing between this and a crash.
                    Text(String(repeating: "M", count: max(28 - row * 5, 8)))
                        .font(.callout)
                    if lines > 2 {
                        Text(String(repeating: "M", count: max(20 - row * 3, 6)))
                            .font(.caption2)
                    }
                    Text(String(repeating: "M", count: max(24 - row * 2, 6)))
                        .font(.caption2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
        }
        .redacted(reason: .placeholder)
        // A placeholder has nothing to read out and nothing to click.
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// The same four lines were written out in each of the four sections. Now that each of them also
/// has a loading branch, the pair belongs together in one place.
struct EmptySection: View {
    /// The default is deliberately flat ("Nothing here."); the issue list overrides it with
    /// something reassuring, because an empty issue list is good news, not an absence.
    var message: String = "Nothing here."
    var symbol: String = "tray"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        // Centred in the list area rather than stranded in the top-left corner. The section is
        // the only thing on screen when it is empty, so it reads as a state, not a stray label.
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

struct PanelFooter: View {
    let state: AppState
    let openSettings: () -> Void

    var body: some View {
        HStack {
            if let when = state.lastUpdated {
                // Forced into the past: `lastUpdated` is essentially `now` when the panel
                // draws, and the relative formatter read it as the future ("updated in 0
                // seconds"). One second back tells the truth and reads properly.
                Text("Updated \(min(when, Date().addingTimeInterval(-1)), format: .relative(presentation: .numeric))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            GlassGroup {
                Button {
                    Task {
                        await state.refreshCheap()
                        await state.refreshExpensive()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .glassButton()
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh (⌘R)")
                .accessibilityLabel("Refresh")

                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .glassButton()
                    .help("Settings")
                    .accessibilityLabel("Settings")

                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "power")
                }
                .glassButton()
                .help("Quit")
                // `.help` is a tooltip and a hint. Without a label VoiceOver falls back to the
                // symbol's own name, so this announced itself as "power".
                .accessibilityLabel("Quit Centinela")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

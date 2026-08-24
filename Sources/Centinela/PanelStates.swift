import CentinelaCore
import SwiftUI

// What the panel shows when it has nothing from Sentry to show. Three different statements that
// were one before: there is no session yet, the answer has not arrived, and the answer was
// nothing. Split out of `PanelRows.swift` when that file crossed 400 lines, along the seam that
// means something — rows that draw data on one side, everything drawn in place of data on the
// other.

struct Notice: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.caption)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

struct NotConfigured: View {
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not configured yet").font(.headline)
            Text("Centinela needs your Sentry organization and a read-only token.")
                .font(.callout)
                .foregroundStyle(.secondary)
                // Without this the text truncates with an ellipsis instead of wrapping: inside
                // a fixed-width container a `Text` prefers a single line unless told it may
                // grow downwards.
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings", action: open)
        }
        .padding(12)
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
    var body: some View {
        Text("Nothing here.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }
}

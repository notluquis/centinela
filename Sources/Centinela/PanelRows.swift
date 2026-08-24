import CentinelaCore
import SwiftUI

struct IssueSection: View {
    let issues: [SentryIssue]
    let loading: Bool

    /// Sentry's triage reaches the eye only as a tint, and this is the system switch for people
    /// who cannot tell those tints apart. The severity symbol already varies by shape, but that
    /// is a different axis: an escalating warning and a one-off error can carry the same symbol
    /// and differ only in colour. With the setting on, the word goes in the metadata line.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    /// What VoiceOver reads for a row, in the order somebody would want it: how bad Sentry
    /// thinks it is, what broke, where, and how much.
    private func spoken(_ issue: SentryIssue) -> String {
        var parts: [String] = []
        parts.append(issue.triage.label + " priority")
        parts.append(issue.title)
        if let culprit = issue.culprit, !culprit.isEmpty {
            parts.append("in " + culprit)
        }
        parts.append(issue.count == 1 ? "1 event" : "\(issue.count) events")
        if issue.userCount > 0 {
            parts.append(issue.userCount == 1 ? "1 person" : "\(issue.userCount) people")
        }
        return parts.joined(separator: ", ")
    }

    private func color(for triage: Triage) -> Color {
        switch triage {
        case .high: .red
        case .medium: .orange
        case .low: .secondary
        }
    }

    var body: some View {
        if issues.isEmpty {
            if loading {
                PlaceholderRows(lines: 3)
            } else {
                EmptySection()
            }
        }
        ForEach(issues) { issue in
            Link(destination: issue.permalink) {
                HStack(alignment: .top, spacing: 8) {
                    // Tinted by Sentry's triage rather than by the event level: a warning that
                    // keeps escalating outranks a one-off error, and that is the call Sentry
                    // already made.
                    Image(systemName: issue.severity.symbol)
                        .foregroundStyle(color(for: issue.triage))
                        .font(.caption)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(issue.title)
                            .lineLimit(2)
                            .font(.callout)
                        // `culprit` says where it happened, which is the next thing anyone wants
                        // after the title. It was decoded from the first commit and never shown.
                        if let culprit = issue.culprit, !culprit.isEmpty {
                            Text(culprit)
                                .lineLimit(1)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            // The short id is what you paste into a message when asking someone
                            // about it. It was decoded from the first commit and never shown.
                            if differentiateWithoutColor {
                                Text(issue.triage.label)
                            }
                            Text(issue.shortId)
                                .font(.system(.caption2, design: .monospaced))
                            Text("·")
                            Text(issue.project.slug)
                            Text("·")
                            // `inflect` so one event is not "1 events".
                            Text("^[\(issue.count) event](inflect: true)")
                            if issue.userCount > 0 {
                                Text("·")
                                Text("^[\(issue.userCount) person](inflect: true)")
                            }
                            Text("·")
                            Text(issue.lastSeen, format: .relative(presentation: .numeric))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            // One element, not six. Without this VoiceOver reads the title, the file, the short
            // id, the project, the event count, the people count and the time as seven separate
            // stops, and getting past a list of fifteen issues takes a hundred swipes.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spoken(issue))
            .accessibilityHint("Opens the issue in Sentry")
        }
    }
}

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
struct HealthSection: View {
    let state: AppState

    var body: some View {
        if let rate = state.crashFree {
            HStack {
                Circle()
                    .fill(rate >= 0.99 ? .green : rate >= 0.95 ? .orange : .red)
                    .frame(width: 7, height: 7)
                Text("Crash-free sessions")
                Spacer()
                Text(rate, format: .percent.precision(.fractionLength(1)))
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
        }

        ForEach(state.monitors.filter(\.isActive)) { monitor in
            HealthRow(
                healthy: monitor.isHealthy,
                name: monitor.url.host() ?? monitor.name,
                detail: monitor.isHealthy ? "up" : "down"
            )
        }

        ForEach(state.crons.filter(\.isActive)) { cron in
            // Sentry's schema types the status as a free-form string, so anything that is not
            // plainly a failure is shown as fine rather than guessed at.
            HealthRow(
                healthy: cron.status != "error",
                name: cron.name,
                detail: cron.status
            )
        }

        if !state.errorsByProject.isEmpty {
            Text("Errors by project")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            ForEach(state.errorsByProject) { entry in
                HStack {
                    Text(entry.slug ?? entry.projectID)
                        .font(.callout)
                    Spacer()
                    Text(entry.count, format: .number)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
            }
        }

        if state.crashFree == nil && state.monitors.isEmpty && state.crons.isEmpty
            && state.errorsByProject.isEmpty {
            if state.loading {
                PlaceholderRows(lines: 2)
            } else {
                EmptySection()
            }
        }
    }
}

private struct HealthRow: View {
    let healthy: Bool
    let name: String
    let detail: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(healthy ? .green : .red)
                .frame(width: 7, height: 7)
            Text(name).font(.callout)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}

/// The slowest transactions by 95th percentile.
///
/// p95 and not the average: an average hides the tail, and the tail is what someone is
/// complaining about. Sentry's own performance views default to the same percentile.
struct PerformanceSection: View {
    let transactions: [TransactionStat]
    let loading: Bool
    /// Sentry's own duration threshold for the project, in milliseconds. Colouring against a
    /// number this project invented would be a number nobody agreed on; this one is configured in
    /// Sentry and moves when they move it.
    let thresholdMilliseconds: Double

    var body: some View {
        if !transactions.isEmpty {
            HStack {
                Text("Slowest by p95")
                Spacer()
                Text("over \(Int(thresholdMilliseconds)) ms is slow, per Sentry")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        if transactions.isEmpty {
            if loading {
                PlaceholderRows(lines: 2)
            } else {
                EmptySection()
            }
        }
        ForEach(transactions) { row in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.transaction)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.callout)
                    Text("^[\(row.count) sample](inflect: true)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(duracion(row.p95))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(
                        row.p95 > thresholdMilliseconds ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
        }
    }

    /// Milliseconds under a second, seconds above it. `1170 ms` reads as noise; `1.17 s` reads as
    /// slow.
    private func duracion(_ milisegundos: Double) -> String {
        milisegundos >= 1000
            ? String(format: "%.2f s", milisegundos / 1000)
            : String(format: "%.0f ms", milisegundos)
    }
}

/// User feedback and session replays.
///
/// Both are decoded from Sentry's published schema rather than from a response: the organization
/// has none of either. The section only appears when something arrives, so nobody stares at an
/// empty tab in the meantime.
struct FeedbackSection: View {
    let feedback: [UserFeedback]
    let replays: [Replay]

    var body: some View {
        ForEach(feedback) { item in
            VStack(alignment: .leading, spacing: 1) {
                Text(item.comments)
                    .lineLimit(3)
                    .font(.callout)
                HStack(spacing: 6) {
                    Text(item.name ?? item.email ?? "anonymous")
                    Text("·")
                    Text(item.dateCreated, format: .relative(presentation: .numeric))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }

        if !replays.isEmpty {
            Text("Replays")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            ForEach(replays) { replay in
                HStack {
                    Text(replay.id)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if replay.errorCount > 0 {
                        Text("^[\(replay.errorCount) error](inflect: true)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
            }
        }
    }
}

/// Placeholder rows in the shape of the real ones, for the moment between opening the panel and
/// the answer arriving.
///
/// The four sections used to say "Nothing here." while the request was still in flight, which is
/// a different statement from "this is still loading" and the wrong one. The list route is the
/// most expensive in the API at 1047 ms measured, so that wrong statement was on screen for about
/// a second every time somebody opened the panel.
///
/// `.redacted(reason: .placeholder)` is SwiftUI's own version of what a skeleton component does
/// elsewhere: it draws the layout with its text replaced by blocks, so the shape on screen is the
/// shape that is coming. Nothing is drawn by hand, which is why these cannot drift away from the
/// rows they stand in for the way a hand-drawn skeleton would.
///
/// The animation is the one thing it does not bring. The header already shows a spinner while a
/// request is in flight, so the movement that says "working" is there; a shimmer of our own would
/// be a second, unsynchronised animation saying the same thing.
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
                    Text(String(repeating: "M", count: 28 - row * 5))
                        .font(.callout)
                    if lines > 2 {
                        Text(String(repeating: "M", count: 20 - row * 3))
                            .font(.caption2)
                    }
                    Text(String(repeating: "M", count: 24 - row * 2))
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

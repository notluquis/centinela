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

    /// The project only earns its place when the rows do not all come from the same one. In an
    /// organization with one busy project it says the same thing on every line, and that is the
    /// width the short id needs to fit whole.
    private var showsProject: Bool { Set(issues.map(\.project.slug)).count > 1 }

    /// What VoiceOver reads for a row, in the order somebody would want it: how bad Sentry
    /// thinks it is, what broke, where, and how much.
    private func spoken(_ issue: SentryIssue) -> String {
        var parts: [String] = []
        parts.append(issue.triage.label + " priority")
        parts.append(issue.title)
        if issue.isUnhandled == true {
            parts.append("unhandled, a crash")
        }
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
                                Text("·")
                            }
                            // Decoded since the first commit and never shown until now. An
                            // unhandled error is a crash rather than something the code caught
                            // and carried on from, which is the next thing worth knowing after
                            // the title, and Sentry sends it for free on every issue.
                            if issue.isUnhandled == true {
                                // A symbol and not the word "crash". The word fits until it
                                // does not: with it in place this line wrapped and pushed the
                                // timestamp onto a second row at the panel's 380 pt. The meaning
                                // is carried by the tooltip for a pointer and by the row's
                                // accessibility label for VoiceOver, which both say it in full.
                                // No separator after it. A dot between two words is a
                                // separator; a dot between an icon and a word is a character
                                // nobody reads, and it costs the width that keeps the short id
                                // whole on the rows that carry this marker.
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .foregroundStyle(.orange)
                                    .help("Unhandled: this one crashed")
                            }
                            // A real short id is `BIOALERGIA-API-1W`, not `API-41`. Measured
                            // against live data this line ran past 380 points and wrapped in the
                            // middle of a word, leaving the crash marker alone on a line of its
                            // own. Shrinking every field was worse: the id truncated to
                            // `EXAMPLE…` is the part somebody copies, made useless. So the field
                            // that repeats on every row is the one that goes.
                            Text(issue.shortId)
                                .font(.system(.caption2, design: .monospaced))
                            if showsProject {
                                Text("·")
                                Text(issue.project.slug)
                                    .truncationMode(.middle)
                                    .layoutPriority(-1)
                            }
                            Text("·")
                            // `inflect` so one event is not "1 events".
                            Text("^[\(issue.count) event](inflect: true)")
                                .layoutPriority(1)
                            if issue.userCount > 0 {
                                Text("·")
                                Text("^[\(issue.userCount) person](inflect: true)")
                                    .layoutPriority(1)
                            }
                            Text("·")
                            Text(issue.lastSeen, format: .relative(presentation: .numeric))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        // One line, always. Wrapping put the timestamp under the id and made two
                        // rows out of one.
                        .lineLimit(1)
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

struct HealthSection: View {
    let state: AppState

    var body: some View {
        if let rate = state.data.crashFree {
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

        ForEach(state.data.monitors.filter(\.isActive)) { monitor in
            HealthRow(
                healthy: monitor.isHealthy,
                name: monitor.url.host() ?? monitor.name,
                detail: monitor.isHealthy ? "up" : "down"
            )
        }

        ForEach(state.data.crons.filter(\.isActive)) { cron in
            // Sentry's schema types the status as a free-form string, so anything that is not
            // plainly a failure is shown as fine rather than guessed at.
            HealthRow(
                healthy: cron.status != "error",
                name: cron.name,
                detail: cron.status
            )
        }

        if !state.data.errorsByProject.isEmpty {
            Text("Errors by project")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            ForEach(state.data.errorsByProject) { entry in
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

        if state.data.crashFree == nil && state.data.monitors.isEmpty && state.data.crons.isEmpty
            && state.data.errorsByProject.isEmpty {
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
                Text(duration(row.p95))
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
    private func duration(_ milliseconds: Double) -> String {
        milliseconds >= 1000
            ? String(format: "%.2f s", milliseconds / 1000)
            : String(format: "%.0f ms", milliseconds)
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

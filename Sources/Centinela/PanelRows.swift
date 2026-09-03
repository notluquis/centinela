import CentinelaCore
import SwiftUI

/// The latest releases, newest first, with the project they went to and how many new issues each
/// brought in.
struct ReleaseSection: View {
    let releases: [Release]
    let loading: Bool

    /// The project earns its place on the row only when the releases do not all come from the same
    /// one — the same rule the issue rows use. In a single-project org it would say the same slug
    /// on every line.
    private let showsProject: Bool

    init(releases: [Release], loading: Bool) {
        self.releases = releases
        self.loading = loading
        self.showsProject = Set(releases.flatMap { $0.projects ?? [] }.map(\.slug)).count > 1
    }

    var body: some View {
        if releases.isEmpty {
            if loading {
                PlaceholderRows(lines: 2)
            } else {
                EmptySection()
            }
        }
        ForEach(releases) { release in
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(release.label).font(.system(.callout, design: .monospaced))
                    if showsProject, let slug = release.primaryProjectSlug {
                        Text(slug)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text("^[\(release.newGroups) new issue](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(release.newGroups > 0 ? .orange : .secondary)
                Text(release.dateCreated, format: .relative(presentation: .numeric))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
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
            SectionHeader("Errors by project")
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
            SectionHeader(
                "Slowest by p95",
                trailing: "over \(Int(thresholdMilliseconds)) ms is slow, per Sentry"
            )
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
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        // A backend transaction carries its HTTP method — badge it the way an API
                        // client colours GET/POST, so the verb reads at a glance and the route
                        // starts on a common column. A page-load transaction has no method and
                        // just shows its path.
                        if let method = row.method {
                            Text(method)
                                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                .foregroundStyle(methodColor(method))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(methodColor(method).opacity(0.15), in: Capsule())
                        }
                        Text(row.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.callout)
                    }
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

    /// The convention an API client uses: GET reads (green), POST writes (blue), PUT/PATCH change
    /// (orange), DELETE removes (red). Anything else stays neutral rather than inventing a colour.
    private func methodColor(_ method: String) -> Color {
        switch method {
        case "GET": .green
        case "POST": .blue
        case "PUT", "PATCH": .orange
        case "DELETE": .red
        default: .secondary
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
            SectionHeader("Replays")
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

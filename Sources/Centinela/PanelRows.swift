import CentinelaCore
import SwiftUI

struct IssueSection: View {
    let issues: [SentryIssue]

    var body: some View {
        if issues.isEmpty {
            Text("Nothing here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
        ForEach(issues) { issue in
            Link(destination: issue.permalink) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: issue.severity.symbol)
                        .foregroundStyle(issue.severity == .warning ? .orange : .red)
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
            Text("Nothing here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
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

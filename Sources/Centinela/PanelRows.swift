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

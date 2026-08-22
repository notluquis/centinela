import CentinelaCore
import SwiftUI

// MARK: - What shows up in the menu bar

struct MenuBarLabel: View {
    let state: AppState

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            if state.totalErrors > 0 {
                Text(state.totalErrors, format: .number)
            }
            // As an image rather than a live `Path`: a `MenuBarExtra` label is drawn by the
            // system, and up there `Text` and `Image` are the only things that render
            // reliably. A vector shape showed up in the panel and NOT in the bar, which is
            // exactly where it was wanted.
            if let sparkline = Sparkline.image(state.series.points.map(\.count)) {
                Image(nsImage: sparkline)
            }
        }
        .accessibilityLabel(accessibleDescription)
        // No fixed colour: in the macOS 26 and 27 menu bar the background is transparent with
        // the wallpaper behind it, so a colour of our own stops contrasting depending on the
        // desktop. A template symbol is resolved by the system, which knows whether things are
        // light or dark. Only an outage is painted red, the one state that justifies breaking
        // the rule.
        .foregroundStyle(state.hasOutage ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
    }

    private var symbol: String {
        if state.hasOutage { return "bolt.horizontal.circle.fill" }
        return state.totalErrors > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal"
    }

    private var accessibleDescription: String {
        var parts = [Sparkline.summary(state.series.points.map(\.count), window: state.settings.window)]
        if state.hasOutage { parts.insert("A service is down.", at: 0) }
        return parts.joined(separator: " ")
    }
}

/// Draws the sparkline inside the panel. The arithmetic lives in `Sparkline.normalize`, which
/// does have tests.
struct SparklinePath: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let points = Sparkline.normalize(values)
                guard points.count > 1 else { return }
                for (index, point) in points.enumerated() {
                    // `y` comes with 0 at the bottom; in Core Graphics 0 is the top.
                    let spot = CGPoint(x: point.x * geo.size.width, y: (1 - point.y) * geo.size.height)
                    if index == 0 { path.move(to: spot) } else { path.addLine(to: spot) }
                }
            }
            .stroke(style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The panel

struct MainPanel: View {
    let state: AppState
    @Environment(\.openSettings) private var openSettings

    /// An `LSUIElement` app is not the active app, so the Settings window opens BEHIND
    /// everything else: the user clicks, nothing visibly happens, and they conclude the button
    /// is broken. You have to activate before asking for it.
    private func openSettingsInFront() {
        NSApplication.shared.activate()
        openSettings()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !state.settings.isConfigured {
                NotConfigured(open: openSettingsInFront)
            } else {
                PanelHeader(state: state)
                Divider()
                PanelContent(state: state)
            }
            Divider()
            PanelFooter(state: state, openSettings: openSettingsInFront)
        }
        .frame(width: 380)
        // The panel is the only thing that asks for the expensive route: 1047 ms and 10.6 KB
        // per opening.
        .task { await state.refreshExpensive() }
    }
}

private struct PanelHeader: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(state.totalErrors) errors")
                    .font(.title2.weight(.semibold))
                Text("in the last \(state.settings.window.label)")
                    .foregroundStyle(.secondary)
                Spacer()
                if state.loading { ProgressView().controlSize(.small) }
            }
            SparklinePath(values: state.series.points.map(\.count))
                .frame(height: 34)
                .foregroundStyle(.tint)
            ForEach(state.monitors.filter(\.isActive)) { monitor in
                HStack(spacing: 6) {
                    Circle()
                        .fill(monitor.isHealthy ? .green : .red)
                        .frame(width: 7, height: 7)
                    Text(monitor.url.host() ?? monitor.name)
                        .font(.callout)
                    Spacer()
                    Text(monitor.isHealthy ? "up" : "down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }
}

private struct PanelContent: View {
    let state: AppState

    var body: some View {
        ScrollView {
            // `VStack` rather than `LazyVStack`: the cap here is about 65 rows, so laziness
            // buys nothing, and a lazy stack only materializes visible rows, which makes any
            // attempt to measure the content's height circular.
            VStack(alignment: .leading, spacing: 0) {
                if let error = state.lastError {
                    Notice(text: error, symbol: "exclamationmark.triangle", color: .orange)
                }
                if let update = state.update {
                    Link(destination: update.page) {
                        Notice(
                            text: "Version \(update.version.description) is out."
                                + " You are on \(state.installedVersion).",
                            symbol: "arrow.down.circle",
                            color: .accentColor
                        )
                    }
                    .buttonStyle(.plain)
                }
                if let notice = state.deprecation {
                    // See `DeprecationNotice`: Sentry warns via a header before retiring a
                    // route. Without this the app would find out the day it breaks.
                    Notice(
                        text: "Sentry is retiring `\(notice.path)` on \(notice.date)."
                            + (notice.replacement.map { " Replacement: \($0)." } ?? ""),
                        symbol: "clock.badge.exclamationmark",
                        color: .orange
                    )
                }
                if state.tokenTooPowerful {
                    Notice(
                        text: "This token can read the audit log, which means it carries write"
                            + " access. A widget does not need that.",
                        symbol: "key.slash",
                        color: .orange
                    )
                }
                IssueSection(title: "Unresolved", issues: state.issues)
                if !state.forReview.isEmpty {
                    IssueSection(title: "For review", issues: state.forReview)
                }
                if !state.releases.isEmpty {
                    Text("Latest releases")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    ForEach(state.releases) { release in
                        HStack {
                            Text(release.label).font(.system(.callout, design: .monospaced))
                            Spacer()
                            Text("\(release.newGroups) new")
                                .font(.caption)
                                .foregroundStyle(release.newGroups > 0 ? .orange : .secondary)
                            Text(release.dateCreated, format: .relative(presentation: .numeric))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        // `maxHeight` and nothing else. A previous attempt measured the content with a
        // `PreferenceKey` and fed that back into `.frame(height:)`, on the theory that the
        // `ScrollView` was collapsing. Measured with `NSHostingView` on the real layout, that
        // is exactly backwards: this arrangement lays out to its full 250 pt, and the
        // measured-and-fed-back version sits at 91 pt, because the loop "the frame height
        // depends on the preference, which depends on the frame height" never converges.
        .frame(maxHeight: 420)
    }
}

private struct IssueSection: View {
    let title: String
    let issues: [SentryIssue]

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
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
                            Text("\(issue.count) events")
                            if issue.userCount > 0 {
                                Text("·")
                                Text("\(issue.userCount) people")
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

private struct Notice: View {
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

private struct NotConfigured: View {
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

private struct PanelFooter: View {
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
                .help("Refresh")

                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .glassButton()
                    .help("Settings")

                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "power")
                }
                .glassButton()
                .help("Quit")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

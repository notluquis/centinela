import CentinelaCore
import SwiftUI

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

struct PanelHeader: View {
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
            // Uptime used to be repeated here. It lives in the Health section now, and the menu
            // bar icon already turns red when something is down, so the header stays the count
            // and the shape of the last few hours.
        }
        .padding(12)
    }
}

/// The three lists the panel can show.
///
/// A segmented picker and not one long scroll: Apple's own guidance for `.segmented` is "use
/// this style when there are two to five options", and there are exactly three. Stats does the
/// same with an `NSSegmentedControl` in its window. Scrolling past one category to reach the
/// next is the thing this replaces.
/// The panel's top-level lists.
///
/// A segmented picker and not one long scroll: Apple's guidance for `.segmented` is "use this
/// style when there are two to five options", and grouping by what someone is looking for keeps it
/// inside that. Stats organizes its window the same way with an `NSSegmentedControl`.
///
/// The four issue states live one level down rather than as four more segments, which would blow
/// past the five and put "Regressed" next to "Releases" as if they were the same kind of thing.
enum PanelSection: String, CaseIterable, Identifiable {
    case issues
    case health
    case releases

    var id: Self { self }

    /// Sentence-style capitalization and no ending punctuation, which is what the picker style
    /// documentation asks for.
    var label: String {
        switch self {
        case .issues: "Issues"
        case .health: "Health"
        case .releases: "Releases"
        }
    }
}

/// Which issues to show. All four are the same route with a different search query.
enum IssueFilter: String, CaseIterable, Identifiable {
    case unresolved
    case forReview
    case escalating
    case regressed

    var id: Self { self }

    var label: String {
        switch self {
        case .unresolved: "Unresolved"
        case .forReview: "For review"
        case .escalating: "Escalating"
        case .regressed: "Regressed"
        }
    }
}

struct PanelContent: View {
    let state: AppState
    @State private var section: PanelSection = .issues
    @State private var filter: IssueFilter = .unresolved

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The notices sit ABOVE the pickers and outside the scroll area: an over-privileged
            // token or a route Sentry is retiring is not a category you browse to, it is
            // something you have to see.
            notices

            Picker("Section", selection: $section) {
                ForEach(PanelSection.allCases) { option in
                    Text(count(option) > 0 ? "\(option.label) \(count(option))" : option.label)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if section == .issues {
                Picker("Issues", selection: $filter) {
                    ForEach(IssueFilter.allCases) { option in
                        Text(issues(option).isEmpty ? option.label : "\(option.label) \(issues(option).count)")
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch section {
                    case .issues:
                        IssueSection(issues: issues(filter))
                    case .health:
                        HealthSection(state: state)
                    case .releases:
                        ReleaseSection(releases: state.releases)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            // `minHeight` is the load-bearing half, and it is what decides the panel's size.
            //
            // The panel is a `VStack` and this `ScrollView` is its only flexible child, so
            // whatever the window shaves off comes out of here. The instrumented app reported a
            // viewport of **0.5 pt** while the content wanted 54, which is why the issue list
            // was invisible while the header and footer looked fine.
            //
            // It is 300 and not something smaller because `MenuBarExtra` sizes its window once,
            // when the panel opens, and does not grow it afterwards: the same instrumentation
            // showed the content going 54 → 226 → 533 as the data arrived while the viewport
            // stayed pinned at whatever the minimum was. So the minimum IS the height of the
            // list area.
            //
            // Do NOT replace this with a measured height fed back from a `PreferenceKey`: that
            // was tried, and the loop "the frame height depends on the preference, which depends
            // on the frame height" never converges (91 pt against the 250 pt of the plain
            // arrangement, measured with `NSHostingView`).
            .frame(minHeight: 300, maxHeight: 420)
        }
    }

    private func issues(_ option: IssueFilter) -> [SentryIssue] {
        switch option {
        case .unresolved: state.issues
        case .forReview: state.forReview
        case .escalating: state.escalating
        case .regressed: state.regressed
        }
    }

    private func count(_ option: PanelSection) -> Int {
        switch option {
        case .issues: state.issues.count
        case .health: state.monitors.filter(\.isActive).count + state.crons.filter(\.isActive).count
        case .releases: state.releases.count
        }
    }

    @ViewBuilder private var notices: some View {
        if let error = state.lastError {
            Notice(text: error, symbol: "exclamationmark.triangle", color: .orange)
        }
        if let notice = state.deprecation {
            // See `DeprecationNotice`: Sentry warns via a header before retiring a route.
            // Without this the app would find out the day it breaks.
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
    }
}

struct ReleaseSection: View {
    let releases: [Release]

    var body: some View {
        if releases.isEmpty {
            Text("Nothing here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
        ForEach(releases) { release in
            HStack {
                Text(release.label).font(.system(.callout, design: .monospaced))
                Spacer()
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

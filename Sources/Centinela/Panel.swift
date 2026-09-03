import CentinelaCore
import SwiftUI

struct MainPanel: View {
    /// Which section is showing when the panel is built. It exists so `make screenshot` can put
    /// two of them side by side without redrawing the panel by hand — the picture in the README
    /// is worth having only if it is this view and not a copy of it.
    var initialSection: PanelSection = .issues
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
                PanelContent(state: state, section: initialSection)
            }
            Divider()
            PanelFooter(state: state, openSettings: openSettingsInFront)
        }
        .frame(width: 380)
        // The panel is the only thing that asks for the expensive route: 1047 ms and 10.6 KB
        // per opening.
        //
        // Keyed on `isConfigured` rather than a bare `.task`, which runs once per appearance and
        // never again. Signing in with the panel already open ran it while there was no client,
        // it returned at the guard, and the issue list stayed empty over a menu bar counting 539
        // errors until somebody closed and reopened the panel. The key makes it run again the
        // moment there is something to ask.
        .task(id: state.settings.queryShape) { await state.refreshExpensive() }
    }
}

struct PanelHeader: View {
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Noun follows what the number counts (`badgeMetric`): "147 errors" or "3
                // unresolved issues". `inflect` pluralizes the singular noun by the count, the
                // same way the release and issue rows do.
                Text("^[\(state.badgeValue) \(state.badgeNoun)](inflect: true)")
                    .font(.title2.weight(.semibold))
                    // The digits roll instead of being replaced. A count that jumps from 228 to
                    // 231 with no motion reads as a redraw; rolling says a number changed.
                    .contentTransition(.numericText(value: Double(state.badgeValue)))
                    .panelMotion(state.badgeValue)
                Text("in the last \(state.settings.window.label)")
                    .foregroundStyle(.secondary)
                    // Read as one sentence. Two Texts are two stops for VoiceOver, and "228
                    // errors" followed by a pause and "in the last 24 hours" is not how anybody
                    // would say it.
                    .accessibilityElement(children: .combine)
                Spacer()
                if state.loading {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity)
                }
            }
            SparklinePath(points: state.data.series.points)
                .frame(height: 40)
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
    case performance
    case releases
    /// Shown only when there is something in it. A permanently empty tab is a tab that teaches
    /// people not to look: the organization this was built against has no replays and no user
    /// feedback, and may never have any, since both need the browser SDK on a frontend.
    case feedback

    var id: Self { self }

    /// Sentence-style capitalization and no ending punctuation, which is what the picker style
    /// documentation asks for.
    var label: String {
        switch self {
        case .issues: "Issues"
        case .health: "Health"
        case .performance: "Perf"
        case .releases: "Releases"
        case .feedback: "Feedback"
        }
    }
}

/// Which issues to show. All four are the same route with a different search query.
enum IssueFilter: String, CaseIterable, Identifiable {
    case unresolved
    case forReview
    case escalating
    case regressed
    case resolved
    case archived
    case all

    var id: Self { self }

    var label: String {
        switch self {
        case .unresolved: "Unresolved"
        case .forReview: "For review"
        case .escalating: "Escalating"
        case .regressed: "Regressed"
        case .resolved: "Resolved"
        case .archived: "Archived"
        case .all: "All"
        }
    }
}

struct PanelContent: View {
    let state: AppState
    @State private var section: PanelSection

    init(state: AppState, section: PanelSection = .issues) {
        self.state = state
        _section = State(initialValue: section)
    }
    @State private var filter: IssueFilter = .unresolved

    /// Keyboard navigation of the issue list: the id of the highlighted row, whether the list has
    /// keyboard focus, and the environment opener that ↩ uses to open the selected issue.
    @State private var selected: String?
    @FocusState private var listFocused: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The notices sit ABOVE the pickers and outside the scroll area: an over-privileged
            // token or a route Sentry is retiring is not a category you browse to, it is
            // something you have to see.
            notices

            Picker("Section", selection: $section) {
                ForEach(visibleSections) { option in
                    Text(count(option) > 0 ? "\(option.label) \(count(option))" : option.label)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if section == .issues {
                // Right-aligned behind a funnel, so it reads as a refinement OF the Issues tab
                // rather than a second row of tabs stacked under the first — which is what a
                // left-aligned, full-looking control next to the segmented bar read as.
                //
                // A menu and NOT a second segmented control: Apple's guidance is to avoid
                // focusable elements close to a segmented control, because segments select on
                // focus rather than on click, and two touching bars stole each other's selection.
                HStack(spacing: 0) {
                    Spacer()
                    // One `Menu`, funnel and label together, so the funnel is part of the button
                    // instead of a dead icon beside it — clicking anywhere on it opens the list.
                    // The inline `Picker` inside gives the four options their selected checkmark.
                    Menu {
                        Picker("Filter issues", selection: $filter) {
                            ForEach(IssueFilter.allCases) { option in
                                Text(issues(option).isEmpty
                                     ? option.label
                                     : "\(option.label) (\(issues(option).count))")
                                    .tag(option)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease")
                            Text(issues(filter).isEmpty
                                 ? filter.label
                                 : "\(filter.label) (\(issues(filter).count))")
                        }
                        .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }

            ScrollViewReader { proxy in
             ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch section {
                    case .issues:
                        IssueSection(issues: issues(filter), loading: state.loading, selected: selected)
                    case .health:
                        HealthSection(state: state)
                    case .performance:
                        PerformanceSection(
                            transactions: state.data.transactions,
                            loading: state.loading,
                            thresholdMilliseconds: state.data.transactionThreshold
                        )
                    case .releases:
                        ReleaseSection(releases: state.data.releases, loading: state.loading)
                    case .feedback:
                        FeedbackSection(feedback: state.data.feedback, replays: state.data.replays)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                // Both the section switch and the swap from placeholder rows to real ones cross
                // fade instead of snapping. The `id` is what tells SwiftUI these are different
                // contents rather than the same view with new text.
                .id(section)
                .transition(.opacity)
            }
            .panelMotion(section)
            .panelMotion(state.loading)
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
             // Arrow keys move the selection, Return opens it in Sentry — the way a dev drives a
             // list like this in Raycast. Focusable only on the Issues tab; the other tabs have
             // nothing to select. Focus is claimed when the tab is shown so the keys work without
             // a click first, and given up when leaving Issues so the pickers keep their own.
             .focusable(section == .issues)
             .focused($listFocused)
             // No focus ring around the scroll area — the selected row's own highlight is the
             // cue. Without this the whole list draws a blue border when it takes key focus.
             .focusEffectDisabled()
             .onKeyPress(.upArrow) { moveSelection(-1, proxy); return .handled }
             .onKeyPress(.downArrow) { moveSelection(1, proxy); return .handled }
             .onKeyPress(.return) { openSelected(); return .handled }
             .onChange(of: section) { listFocused = section == .issues }
             .onChange(of: filter) { selected = nil }
             .onAppear { listFocused = section == .issues }
            }
        }
    }

    /// Moves the keyboard selection within the current filter's list and scrolls it into view.
    /// From no selection, the first press lands on the top row.
    private func moveSelection(_ delta: Int, _ proxy: ScrollViewProxy) {
        let list = issues(filter)
        guard !list.isEmpty else { return }
        let ids = list.map(\.id)
        let current = selected.flatMap { ids.firstIndex(of: $0) } ?? -1
        let next = max(0, min(ids.count - 1, current + delta))
        selected = ids[next]
        withAnimation { proxy.scrollTo(ids[next], anchor: .center) }
    }

    /// Opens the selected issue in Sentry, the same destination its row's `Link` points at.
    private func openSelected() {
        guard let id = selected, let issue = issues(filter).first(where: { $0.id == id }) else { return }
        openURL(issue.permalink)
    }

    /// Feedback drops out when empty. Positions shift the day it appears, which is a day worth
    /// noticing.
    private var visibleSections: [PanelSection] {
        PanelSection.allCases.filter { $0 != .feedback || count(.feedback) > 0 }
    }

    private func issues(_ option: IssueFilter) -> [SentryIssue] {
        switch option {
        case .unresolved: state.data.issues
        case .forReview: state.data.forReview
        case .escalating: state.data.escalating
        case .regressed: state.data.regressed
        case .resolved: state.data.resolved
        case .archived: state.data.archived
        case .all: state.data.allIssues
        }
    }

    private func count(_ option: PanelSection) -> Int {
        switch option {
        case .issues: state.data.issues.count
        // Counts the rows that are actually drawn, crash-free and the per-project breakdown
        // included. It used to count only monitors, so the badge said 1 above a section showing
        // four lines.
        case .health:
            state.data.monitors.filter(\.isActive).count
                + state.data.crons.filter(\.isActive).count
                + (state.data.crashFree == nil ? 0 : 1)
                + state.data.errorsByProject.count
        case .performance: state.data.transactions.count
        case .releases: state.data.releases.count
        case .feedback: state.data.feedback.count + state.data.replays.count
        }
    }

    @ViewBuilder private var notices: some View {
        if let error = state.data.lastError {
            Notice(text: error, symbol: "exclamationmark.triangle", color: .orange)
        }
        if let notice = state.data.deprecation {
            // See `DeprecationNotice`: Sentry warns via a header before retiring a route.
            // Without this the app would find out the day it breaks.
            Notice(
                text: "Sentry is retiring `\(notice.path)` on \(notice.date)."
                    + (notice.replacement.map { " Replacement: \($0)." } ?? ""),
                symbol: "clock.badge.exclamationmark",
                color: .orange
            )
        }
        if state.data.tokenTooPowerful {
            Notice(
                text: "This token can read the audit log, which means it carries write"
                    + " access. A widget does not need that.",
                symbol: "key.slash",
                color: .orange
            )
        }
    }
}

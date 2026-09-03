import AppKit
import CentinelaCore
import SwiftUI

// The issue list and its row. Split out of `PanelRows.swift` when that file crossed the 400-line
// limit, along the seam that means something: the issues are the panel's primary content and the
// one list whose rows are interactive (a `Link` into Sentry, a copy menu, a hover state), where
// Health, Perf and the rest are read-only readouts.

struct IssueSection: View {
    let issues: [SentryIssue]
    let loading: Bool
    /// The id of the keyboard-selected row, if any. Highlighted like a hovered row so arrow-key
    /// navigation and the pointer share one visual language.
    var selected: String?

    /// The project only earns its place when the rows do not all come from the same one. In an
    /// organization with one busy project it says the same thing on every line, and that is the
    /// width the short id needs to fit whole.
    ///
    /// Stored and not computed: as a computed property it was read inside the `ForEach`, so it
    /// built a `Set` of every slug once per row — quadratic in the list, re-run on every pass of
    /// `body`, and `body` runs on every frame of an animation. Fifty issues came to two and a
    /// half thousand string hashes a frame for an answer that cannot change while the view
    /// exists.
    private let showsProject: Bool

    init(issues: [SentryIssue], loading: Bool, selected: String? = nil) {
        self.issues = issues
        self.loading = loading
        self.selected = selected
        self.showsProject = Set(issues.map(\.project.slug)).count > 1
    }

    var body: some View {
        if issues.isEmpty {
            if loading {
                PlaceholderRows(lines: 3)
            } else {
                // An empty issue list is good news, so it says so instead of "Nothing here."
                EmptySection(message: "All clear", symbol: "checkmark.circle")
            }
        }
        ForEach(issues) { issue in
            IssueRow(issue: issue, showsProject: showsProject, isSelected: issue.id == selected)
        }
    }
}

/// One issue in the list. Extracted from `IssueSection` so each row can hold its own hover state:
/// a row that lights up under the pointer reads as a thing you can click, which is what it is (a
/// `Link` into Sentry), and is how Linear, Raycast and the like draw a list like this.
private struct IssueRow: View {
    let issue: SentryIssue
    let showsProject: Bool
    var isSelected = false

    /// Sentry's triage reaches the eye only as a tint, and this is the system switch for people
    /// who cannot tell those tints apart. With it on, the word goes in the metadata line.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var hovering = false

    var body: some View {
        Link(destination: issue.permalink) {
            HStack(alignment: .top, spacing: 8) {
                // Tinted by Sentry's triage rather than by the event level: a warning that keeps
                // escalating outranks a one-off error, and that is the call Sentry already made.
                // Left bare, at the original width: a disc badge here reads nicely but pushes
                // every title ~6 pt right, and the metadata line below is tuned to the pixel
                // against the panel's 380 pt (see the short-id note). Prettiness that costs that
                // line a wrap is not a trade this row makes.
                Image(systemName: issue.severity.symbol)
                    .foregroundStyle(color(for: issue.triage))
                    .font(.caption)
                    .padding(.top, 2)
                    // Sentry's two highest-signal states — escalating (getting worse) and
                    // regressed (a resolved issue came back) — as a small corner badge ON the
                    // severity icon rather than a chip in the row. A chip would eat the metadata
                    // line's width, which is tuned to the pixel; a badge on the existing glyph
                    // costs no layout width at all. The arrow shape differs between the two, so
                    // the cue is not colour alone.
                    .overlay(alignment: .bottomTrailing) {
                        if let badge = substatusBadge {
                            Image(systemName: badge.symbol)
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(2)
                                .background(badge.color, in: Circle())
                                .overlay(Circle().strokeBorder(.background, lineWidth: 0.5))
                                .offset(x: 3, y: 3)
                                .help(badge.help)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.title)
                        .lineLimit(2)
                        .font(.callout.weight(.medium))
                    // `culprit` says where it happened, which is the next thing anyone wants
                    // after the title. It was decoded from the first commit and never shown.
                    if let culprit = issue.culprit, !culprit.isEmpty {
                        Text(culprit)
                            .lineLimit(1)
                            // Middle, not tail: a culprit is a path (`src/services/billing.ts`)
                            // and the filename at the end is the half worth keeping, so a long one
                            // loses its middle rather than the name.
                            .truncationMode(.middle)
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
                        // An unhandled error is a crash rather than something the code caught
                        // and carried on from, which is the next thing worth knowing after the
                        // title, and Sentry sends it for free on every issue.
                        if issue.isUnhandled == true {
                            // A symbol and not the word "crash": with the word in place this
                            // line wrapped and pushed the timestamp onto a second row at the
                            // panel's 380 pt. The meaning is carried by the tooltip and the
                            // row's accessibility label, which both say it in full. No separator
                            // after it — a dot between an icon and a word is a character nobody
                            // reads, and it costs the width that keeps the short id whole.
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundStyle(.orange)
                                .help("Unhandled: this one crashed")
                        }
                        // A real short id is `BIOALERGIA-API-1W`, not `API-41`. Measured against
                        // live data this line ran past 380 points and wrapped mid-word, so the
                        // field that repeats on every row — the project — is the one that goes,
                        // not this one.
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
                    // Tabular figures so the event and people counts line up column-wise down the
                    // list instead of jittering with each digit width, the way Stats aligns its
                    // numbers.
                    .monospacedDigit()
                    // One line, always. Wrapping put the timestamp under the id and made two
                    // rows out of one.
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
            // Text stays inset 12 from the panel edge — the width the metadata line was tuned
            // against. The hover tint is a separate, slightly inset rounded fill so it reads as a
            // highlighted row rather than a full-bleed band.
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(isSelected ? 0.10 : hovering ? 0.06 : 0))
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // The short id is the thing a dev grabs to paste into a PR or a message, so right-click
        // hands it over without a trip to the browser. Read-only to the bone: it writes to the
        // pasteboard, never to Sentry.
        .contextMenu {
            Button("Copy issue ID") { copy(issue.shortId) }
            Button("Copy title") { copy(issue.title) }
            Button("Copy link") { copy(issue.permalink.absoluteString) }
        }
        // One element, not six. Without this VoiceOver reads the title, the file, the short id,
        // the project, the event count, the people count and the time as seven separate stops.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
        .accessibilityHint("Opens the issue in Sentry")
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func color(for triage: Triage) -> Color {
        switch triage {
        case .high: .red
        case .medium: .orange
        case .low: .secondary
        }
    }

    /// Sentry's two highest-signal substatuses, as a corner badge. `nil` for the ordinary states
    /// (new, ongoing) so only the ones worth a second look carry a mark.
    private var substatusBadge: SubstatusBadge? {
        switch issue.substatus {
        case "escalating":
            SubstatusBadge(symbol: "arrow.up.right", color: .red, help: "Escalating: getting worse")
        case "regressed":
            SubstatusBadge(symbol: "arrow.counterclockwise", color: .purple,
                           help: "Regressed: came back after being resolved")
        default:
            nil
        }
    }

    /// What VoiceOver reads for a row, in the order somebody would want it: how bad Sentry thinks
    /// it is, what broke, where, and how much.
    private var spoken: String {
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
}

/// The mark on a row for Sentry's escalating / regressed states. A named type, not a tuple, so it
/// stays under the two-member tuple limit and reads at the call site.
private struct SubstatusBadge {
    let symbol: String
    let color: Color
    let help: String
}

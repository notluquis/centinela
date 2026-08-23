# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Semantic versioning.

The release workflow reads the section for the tag being published out of this file and refuses to publish when it is missing, so a release never goes out with an empty body.

## [Unreleased]

## [0.5.0] — 2026-08-23

### Fixed

- **macOS stopped asking for the Keychain password on every update.** The cause was not a bug to work around: with an ad-hoc signature the app's designated requirement is literally its code hash, so every build was, to the Keychain, a different application asking for someone else's item. Builds are signed with a self-signed certificate now, which makes the requirement identity-based and stable. Measured on the same read: 7709 ms and a dialog before, 18 ms and none after. The release workflow fails if a build ever comes out hash-signed, because a release signed ad-hoc would put the dialog back for everyone who updates.

  Three documented alternatives were tried first and none works without a stable identity: the data protection keychain returns `errSecMissingEntitlement`, `SecAccessCreate(nil)` trusts only the app that is about to stop existing, and `security -A` did not remove the delay. The certificate is **not** a Developer ID: Gatekeeper still asks for right-click-to-open, notarization is still impossible, and `disable-library-validation` is still required, because library validation wants a real team identifier and a self-signed certificate has none. All of it is in `SECURITY.md` with the numbers.

### Changed

- The update dialog shows the changelog itself instead of GitHub's release page. It was pointing at the page, so Sparkle rendered its chrome too: "Compare", "github-actions released this" and a commit list around the actual notes. Sparkle accepts `sparkle:format="markdown"` on `<description>`, so the section goes in verbatim with no conversion step to get wrong.

## [0.4.0] — 2026-08-23

Six more Sentry surfaces, all verified against the live organization except the one that has no data to verify against, which says so.

### Added

- **A Performance section**: the slowest transactions by 95th percentile span duration. Measured against the live organization: an outbound Microsoft Graph call at 1170 ms p95 over 150 samples, next to an endpoint doing 650 samples at 71 ms. p95 and not the average, because an average hides the tail and the tail is what someone is complaining about.
- **A Feedback section** for user feedback and session replays, which **appears only when there is something in it**. A permanently empty tab teaches people not to look, and this organization has neither, since both need the browser SDK on a frontend.
- **Escalating and regressed issues.** Sentry's own triage: escalating means it decided the issue is getting worse, regressed means it came back after being resolved. Same route as the other lists with a different search.
- **A Health section**: uptime, cron monitors, crash-free session rate, and errors broken down by project. One question ("is anything on fire") rather than four segments.
- **Filter by project and by environment.** Every query goes through one place that carries both, so no route can quietly ignore what was picked. The environment control only appears when there is more than one to choose between.
- Issue rows show `culprit` (where the error happened) and `shortId` (what you paste into a message when asking someone about it). Both were decoded from the first commit and never shown.
- The icon on each row is tinted by `priority`, Sentry's own triage, rather than by the event level. A `warning` that keeps escalating outranks a one-off `error`, and that is a call Sentry already made. `priority` was also being decoded and discarded.

### Changed

- **The panel is three sections with a sub-filter** instead of one flat list of categories: Issues (unresolved, for review, escalating, regressed), Health and Releases.
- Uptime moved out of the header, where it was about to be duplicated, into Health. The menu bar icon already turns red when something is down.
- Cron monitors join the cheap cycle (349 ms measured): a failing cron belongs next to an outage, not behind a click. Crash-free and the per-project breakdown are fetched when the panel opens.

### Not verified

The rule these follow: **with live data it is verified, with a published schema it is implemented and marked, with neither it is not written.**

| | Why | What unblocks it |
|---|---|---|
| **Cron monitors** | The organization has none. The decoder comes from Sentry's published OpenAPI schema (`getsentry/sentry-api-schema`) and the fixture is derived from it | One cron existing. Then the real response gets compared against the fixture and the mark comes off |
| **Replays and user feedback** | Zero of either. Same treatment: schema-derived, and the section stays hidden until something arrives | One replay or one piece of feedback |
| **Incidents and alert rules** | Deliberately absent. No data **and no published schema either**: zero paths for both, so a decoder would be a guess | One alert being configured. Until then no code goes in |

### Fixed

- CI was not red, it was starved: every push asked for four macOS runners and two of them sat queued for over ten minutes while the Linux job finished in five seconds. swiftlint moved into the build job, the without-Xcode guard became weekly, and the appcast commit the release bot pushes no longer triggers `ci.yml`. Two runners per push instead of four, and a full run went from over ten minutes queued to 1 min 20 s.

  One caveat, measured rather than assumed: **`[skip ci]` does not stop CodeQL.** Its runs arrive with the event `dynamic` and GitHub's default setup ignores the marker, so the appcast commit still gets scanned. `paths-ignore` is no help either, since default setup has no path filter to configure. Stopping it would mean switching CodeQL to advanced setup, which is a workflow file to maintain in exchange for one macOS runner per release.

## [0.3.0] — 2026-08-23

### Added

- **Centinela updates itself**, through Sparkle. The previous release only told you a new version existed.

### Changed

- The README's claim that Sparkle could not work without a Developer ID was **wrong**, and it came from reading a summary instead of the source. Sparkle's `SUUpdateValidator.m` says the opposite: "if no Apple Code Signing certificate is available, adhoc signing can be used at minimum". Updates are verified with an EdDSA signature of this project's own, which does not involve Apple.
- Two entitlements are new and both are documented with what they give up. The one that costs something is `com.apple.security.cs.disable-library-validation`: without it dyld refuses to load Sparkle, because the hardened runtime wants every loaded library to share the app's Team ID and two ad-hoc signatures count as different teams.
- `SECURITY.md` now states what the Keychain does and does not buy. Measured: any process running as you reads the token with no prompt, because the item is not bound to the app's signature.

### Removed

- The hand-rolled update checker that read GitHub's releases API, along with its ten tests. Sparkle does the same job and also installs.

## [0.2.0] — 2026-08-22

### Changed

- **The whole project is in English**: interface, source, comments, documentation and CI. It was written in Spanish and this is a public repository.

### Fixed

- **The issue list was invisible in the panel.** Two guesses were wrong before the app was instrumented and asked. It reported a scroll viewport of **0.5 pt** while the content wanted 54: the panel is a `VStack` and the scroll area is its only flexible child, so everything the window shaved off came out of the list. It has a minimum height now. Along the way, an earlier attempt that measured the content with a `PreferenceKey` and fed it back into `.frame(height:)` turned out to make it worse (91 pt against 250 pt, measured with `NSHostingView`), and that is written down in the code so nobody tries it again.
- **The panel said "Not configured yet" while the menu bar counted errors above it.** Both read the same two values. The token had been cached behind `@ObservationIgnored`, so `isConfigured` depended on something SwiftUI cannot observe: the panel was built while the Keychain was empty and nothing ever told it to look again. The token is an observed stored property now, loaded once, with a regression test that fails against the old design.
- The footer said "Updated in 0 seconds": `lastUpdated` is essentially `now` when the panel draws, and the relative formatter read it as the future.
- "1 events" and "1 people": counts are inflected now.

### Added

- **The panel's three lists are a segmented picker instead of one long scroll**: Unresolved, For review and Releases, each with its count, so a category is one click away rather than a scroll away. Apple's guidance for `.segmented` is "use this style when there are two to five options", and Stats organizes its window the same way with an `NSSegmentedControl`.
- Warnings that are not a category you browse to (an over-privileged token, a route Sentry is retiring, a network error) sit above the picker, always visible.
- The Keychain accounts are injectable, so tests and probes never touch the real ones. They were not, and a layout probe overwrote and then deleted a live session token.
- Release notes are assembled automatically: the CHANGELOG section for the tag plus the list GitHub generates from merged pull requests, categorized by `.github/release.yml`.
- The release workflow checks that the version inside the bundle matches the tag. A mistyped tag used to ship an artifact claiming something else.
- `make lint` fails when swiftlint is missing instead of skipping in silence, and points `DYLD_FRAMEWORK_PATH` at the swiftly toolchain, without which swiftlint dies looking for `sourcekitdInProc` inside Xcode.

## [0.1.0] — 2026-08-22

First published version. Ad-hoc signature, not notarized: the first time, macOS asks for confirmation (right click on the app, Open).

### In the menu bar

- Error count for the chosen window, with a sparkline of the series next to it.
- Red icon when an uptime monitor is down.
- The icon sets no colours of its own: in macOS 26 and 27 the bar is transparent with the wallpaper behind it, so contrast is the system's call. The only colour of our own is the red of an outage.

### In the panel

- Unresolved issues with project, event count and affected people. A click opens the issue in Sentry.
- New issues for review (`is:for_review`).
- Latest releases and how many new issues each one brought.
- Uptime monitor status.
- A notice when Sentry announces it is retiring one of the routes the app uses.

### Signing in

- OAuth 2.0 device flow (RFC 8628), the same one `sentry-cli` uses. The app declares `org:read`, `project:read` and `event:read`; Sentry hands back a token with exactly those and nothing more.
- The client id is built in: there is nothing to configure. Anyone who prefers to register their own pastes it in Settings.
- Automatic renewal below 10% of remaining life. A failed renewal does not sign you out: there may simply be no network.
- Pasting a token by hand still works, and is the only way on instances older than Sentry 26.1.0.
- Warns when the token can read the organization's audit log, meaning it carries write access the app does not need.

### Security

- Access and refresh tokens in the macOS Keychain, only while the machine is unlocked and never synced to iCloud.
- Sandbox with two permissions: reach the network, and nothing else. They can be read end to end in `Centinela.entitlements`.
- Ephemeral network session: nothing Sentry returns is written to disk.

### Performance

- The periodic cycle asks only for the two cheap routes: the error series (378 ms, 937 B) and uptime status (490 ms). The issue list (1047 ms, 10.6 KB) is fetched only when the panel opens.
- The timer carries 20% tolerance so the system can coalesce the wake-up with others.
- Zero requests while the machine sleeps, and an immediate refresh on wake.

### System

- Launch at login through `SMAppService`, with the "needs approval" state handled separately instead of shown as off.
- New-version notice read from GitHub's releases API, once a day. It does not update itself.
- Settings window with tabs, and an About tab.

### How it is built

- SwiftPM plus a `Makefile`, no `.xcodeproj`.
- **Xcode is not required**: the [swiftly](https://www.swift.org/install/macos/swiftly/) toolchain is enough, and a CI job keeps that honest by building without it.
- 45 tests in Swift Testing, including eleven integration tests of the sign-in flow against a stub server.

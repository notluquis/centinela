# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Semantic versioning.

The release workflow reads the section for the tag being published out of this file and refuses
to publish when it is missing, so a release never goes out with an empty body.

## [Unreleased]

## [0.2.0] — 2026-08-22

### Changed

- **The whole project is in English**: interface, source, comments, documentation and CI. It was
  written in Spanish and this is a public repository.

### Fixed

- **The issue list was invisible in the panel.** Two guesses were wrong before the app was
  instrumented and asked. It reported a scroll viewport of **0.5 pt** while the content wanted
  54: the panel is a `VStack` and the scroll area is its only flexible child, so everything the
  window shaved off came out of the list. It has a minimum height now. Along the way, an earlier
  attempt that measured the content with a `PreferenceKey` and fed it back into
  `.frame(height:)` turned out to make it worse (91 pt against 250 pt, measured with
  `NSHostingView`), and that is written down in the code so nobody tries it again.
- **The panel said "Not configured yet" while the menu bar counted errors above it.** Both read
  the same two values. The token had been cached behind `@ObservationIgnored`, so `isConfigured`
  depended on something SwiftUI cannot observe: the panel was built while the Keychain was empty
  and nothing ever told it to look again. The token is an observed stored property now, loaded
  once, with a regression test that fails against the old design.
- The footer said "Updated in 0 seconds": `lastUpdated` is essentially `now` when the panel
  draws, and the relative formatter read it as the future.
- "1 events" and "1 people": counts are inflected now.

### Added

- **The panel's three lists are a segmented picker instead of one long scroll**: Unresolved, For
  review and Releases, each with its count, so a category is one click away rather than a scroll
  away. Apple's guidance for `.segmented` is "use this style when there are two to five options",
  and Stats organizes its window the same way with an `NSSegmentedControl`.
- Warnings that are not a category you browse to (an over-privileged token, a route Sentry is
  retiring, a network error) sit above the picker, always visible.
- The Keychain accounts are injectable, so tests and probes never touch the real ones. They were
  not, and a layout probe overwrote and then deleted a live session token.
- Release notes are assembled automatically: the CHANGELOG section for the tag plus the list
  GitHub generates from merged pull requests, categorized by `.github/release.yml`.
- The release workflow checks that the version inside the bundle matches the tag. A mistyped tag
  used to ship an artifact claiming something else.
- `make lint` fails when swiftlint is missing instead of skipping in silence, and points
  `DYLD_FRAMEWORK_PATH` at the swiftly toolchain, without which swiftlint dies looking for
  `sourcekitdInProc` inside Xcode.

## [0.1.0] — 2026-08-22

First published version. Ad-hoc signature, not notarized: the first time, macOS asks for
confirmation (right click on the app, Open).

### In the menu bar

- Error count for the chosen window, with a sparkline of the series next to it.
- Red icon when an uptime monitor is down.
- The icon sets no colours of its own: in macOS 26 and 27 the bar is transparent with the
  wallpaper behind it, so contrast is the system's call. The only colour of our own is the red
  of an outage.

### In the panel

- Unresolved issues with project, event count and affected people. A click opens the issue in
  Sentry.
- New issues for review (`is:for_review`).
- Latest releases and how many new issues each one brought.
- Uptime monitor status.
- A notice when Sentry announces it is retiring one of the routes the app uses.

### Signing in

- OAuth 2.0 device flow (RFC 8628), the same one `sentry-cli` uses. The app declares `org:read`,
  `project:read` and `event:read`; Sentry hands back a token with exactly those and nothing more.
- The client id is built in: there is nothing to configure. Anyone who prefers to register their
  own pastes it in Settings.
- Automatic renewal below 10% of remaining life. A failed renewal does not sign you out: there
  may simply be no network.
- Pasting a token by hand still works, and is the only way on instances older than Sentry 26.1.0.
- Warns when the token can read the organization's audit log, meaning it carries write access the
  app does not need.

### Security

- Access and refresh tokens in the macOS Keychain, only while the machine is unlocked and never
  synced to iCloud.
- Sandbox with two permissions: reach the network, and nothing else. They can be read end to end
  in `Centinela.entitlements`.
- Ephemeral network session: nothing Sentry returns is written to disk.

### Performance

- The periodic cycle asks only for the two cheap routes: the error series (378 ms, 937 B) and
  uptime status (490 ms). The issue list (1047 ms, 10.6 KB) is fetched only when the panel opens.
- The timer carries 20% tolerance so the system can coalesce the wake-up with others.
- Zero requests while the machine sleeps, and an immediate refresh on wake.

### System

- Launch at login through `SMAppService`, with the "needs approval" state handled separately
  instead of shown as off.
- New-version notice read from GitHub's releases API, once a day. It does not update itself.
- Settings window with tabs, and an About tab.

### How it is built

- SwiftPM plus a `Makefile`, no `.xcodeproj`.
- **Xcode is not required**: the [swiftly](https://www.swift.org/install/macos/swiftly/)
  toolchain is enough, and a CI job keeps that honest by building without it.
- 45 tests in Swift Testing, including eleven integration tests of the sign-in flow against a
  stub server.

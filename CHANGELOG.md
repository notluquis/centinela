# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Semantic versioning.

The release workflow reads the section for the tag being published out of this file and refuses to publish when it is missing, so a release never goes out with an empty body.

## [Unreleased]

Issues that crashed say so, Dependabot watches the pinned actions, and mutation testing turned out never to have run.
### Fixed

- **Three measured numbers in the documentation had gone stale.** The suite is 73 tests and two files said 59; the bundle is 5.6 MB and the README said 5.3; and the memory table said 19 MB less than the app now uses with the panel never opened, which is what happens when a number is written without a date and read as a fact forever. All re-measured, and the tables now carry the date they were taken on, including one column that says plainly it could not be re-run.
- **The token-shaped-string guard fired on the test written to prove tokens never leak.** It is the one file with a reason to carry that shape, so the literal is assembled from pieces: the test still exercises a realistic value and no line in the tree matches the pattern. It passed locally and failed on the runner because the `grep` on this machine is `ugrep` and does not match what the runner's does — which is now written down in `AGENTS.md`, because believing a guard that was never run under CI's tools is how this got shipped in the first place.
- **Changing the window, the project, the environment or the issue limit changed nothing on screen.** The value was stored and the panel kept showing the answer to the previous question, for up to five minutes, with the only clue being that the numbers no longer matched the controls. Reported with a screenshot: the header still said 539 errors after the settings had moved. Those four preferences are one comparable value now, and both the panel's expensive fetch and the settings window key their work on it, so a change is a change. The refresh interval and launch at login stay out of it on purpose and cost no request — there is a test for that half, because folding the interval in would make the app re-ask Sentry every time somebody moves a slider.
- **The handler that noticed was on a tab nobody was looking at.** It sat on the Account tab's form, and a `TabView` does not keep unselected tabs alive, so a change made on the Query tab — which is where all four of these live — reached nothing at all. It is on the window now, alive for as long as Settings is open.

### Changed

- **The update dialog shows a summary line, not the whole changelog.** v0.7.0's notes were 7334 characters in a dialog Sparkle draws at about 600 points: a wall nobody reads with a "see all" link right underneath it. Every version now opens with one line between its heading and the first `###`, the dialog gets that line — 127 characters for 0.7.0 — and the GitHub release keeps everything, because that one is read on a page by somebody who came looking. A version written without a summary line still publishes the whole section rather than an empty dialog, and the workflow says so in a warning.

### Added

- **An issue that crashed says so.** `isUnhandled` had been decoded since the first commit and shown nowhere: an unhandled error is a crash rather than something the code caught and carried on from, which is the next thing worth knowing after the title, and Sentry sends it on every issue for free. It is a marker rather than the word "crash", because the word fit until it did not — with it in place the metadata line wrapped and pushed the timestamp onto a second row at the panel's 380 pt. The full sentence is in the tooltip and in what VoiceOver reads. With that, nothing decoded from Sentry goes unused: the other five candidates a sweep turns up are all read through a computed property.
- **Dependabot, for the pinned actions.** Every action in the workflows is pinned to a full commit SHA, which is the right call because a tag can be moved underneath you, and it is also a version nobody will ever notice going stale. Swift Package Manager is **not** one of Dependabot's supported ecosystems — checked against GitHub's own table rather than assumed, the same lesson the muter config just taught — so Sparkle stays watched by hand.

### Fixed

- **Mutation testing had never run once, and four of its five failures were real defects.** The workflow was weekly and was added days before the first Monday, so the first execution was triggered by hand. `--output-json` is not a muter flag, so it died before mutating a line. Muter mutates a copy and resolves dependencies there, so with nothing in SwiftPM's cache that copy tried to clone Sparkle over the network. `mutateFilesInDirectories` is ignored, so it mutated the SwiftUI target the config excludes and emitted Swift that does not compile. And `swift test` in debug makes SwiftPM code-sign the executable, a spawn that fails inside muter, where a release build — which is what `make test` runs anyway — never reaches it. All four fixed; the fifth, a baseline failure in one test that passes locally, in CI, and from a copied checkout, is written up in `docs/notes.md` and the weekly schedule is off until it is understood. A job that fails every Monday teaches people to ignore Monday.
- **Two Spanish identifiers the English sweep missed**, `duracion(_ milisegundos:)`. Found because muter emitted broken Swift inside that function and printed the name. The sweep before it used a dictionary chosen by hand and could only find words somebody thought of; a re-sweep over all 428 declared identifiers now finds none.

## [0.7.0] — 2026-08-24

The panel is usable with VoiceOver, glass switches off under Reduce Transparency, and signing out can no longer forget a field.
### Added

- **Four more tests, and now every route has one.** `replays`, `userFeedback` and the transaction threshold were the last three without. The first two have never been seen with live data, so their decoders came from Sentry's published schema; pinning the shape is the honest half of that debt, so the day real data arrives there is something written down to compare it against. The threshold test also pins the second field Sentry sends as **text** where a number is expected, after `issue.count`.

### Changed

- **Signing out is one assignment instead of eighteen.** Everything a Sentry session told the app is one `SessionData` value now, so forgetting it is `data = SessionData()` and cannot miss a field. The previous version listed eighteen by hand, which is exactly how the menu bar ended up counting 539 errors from an account it no longer reached. There is deliberately no test for this: a test would assert what the type already makes true, and the fix is the construction rather than a check bolted on beside it. `lastUpdated` stays out of the value on purpose — it is persisted so the panel can say how old the data on screen is after a restart.
- `PanelRows.swift` crossed 400 lines and is split along a seam that means something: rows that draw Sentry data stay, and everything drawn *in place of* data — no session yet, answer not arrived, answer was nothing — moves to `PanelStates.swift`.

- **The panel is usable with VoiceOver, which it was not.** An issue row was seven separate stops — title, file, short id, project, event count, people count, time — so getting past a list of fifteen took a hundred swipes. Each row is one element now, and reads in the order somebody would want it: how bad Sentry thinks it is, what broke, where, how much. The three footer buttons had a tooltip and no label, so they announced themselves as "arrow clockwise", "gearshape" and "power".
- **Liquid Glass switches off under Reduce Transparency.** Apple's own documentation for `accessibilityReduceTransparency` says elements "should not be semi-transparent; they should be rendered as opaque instead", and the footer controls ignored it. Neither of the two repositories this project was modelled on handles that setting: zero files mention it in one, none in the other.
- **Sentry's triage stops being colour-only.** The severity symbol varies by shape, but the tint carries a different axis — Sentry's own priority — so an escalating warning and a one-off error could look identical apart from colour. With Differentiate Without Colour on, the word joins the metadata line.

- **Nine tests for routes and guards that had none.** The list came from counting every public symbol in `CentinelaCore` against every name mentioned anywhere under `Tests/`: twenty were never named once. Two of the new tests are guards rather than coverage. **No error message carries the token**, checked across four failure modes, which until now was a rule in `AGENTS.md` with nothing holding it up — two of the six error cases build their text out of whatever Sentry sent back. And **the read-only check actually distinguishes**: the panel warns when a token can read the organization's audit log, and nothing stopped that check from quietly answering "read-only" for every token. Both were verified by breaking them.
- **One motion vocabulary, and it honours reduce motion.** `Motion.curve` is the single curve, and `.panelMotion(_:)` applies it or applies nothing at all when the system says to reduce motion. Counts roll their digits with `.contentTransition(.numericText())` instead of being replaced; sections and the swap from placeholder rows to real ones cross fade instead of snapping.

### Fixed

- **The panel said "Nothing here." while it was still asking.** Four sections did it, and the issue list is the most expensive route in the API at 1047 ms measured, so a statement that was simply untrue sat on screen for about a second every time somebody opened the panel. Each section now draws placeholder rows in the shape of what is coming, and keeps "Nothing here." for when the answer really was nothing.

### Changed

- The placeholders are `.redacted(reason: .placeholder)`, which is SwiftUI's own version of a skeleton component: it draws the real layout with its text replaced by blocks. Nothing is hand-drawn, so these cannot drift away from the rows they stand in for. The animation is the one thing it does not bring, and the header already spins while a request is in flight — a shimmer of our own would be a second, unsynchronised animation saying the same thing.
- The four copies of the empty-state text are one `EmptySection`. They were identical before and each of them now has a loading branch next to it.

### Changed

- **The README has the screenshot it was missing**, generated by `make screenshot` from invented data rather than pasted from a live organization. The tool compiles against the app's own sources, so a picture that stops matching the UI is a compile error instead of an image that quietly lies. Two things had to be found out first, both now commented where they bite: rendered offscreen the panel draws nothing at all, and rendered without a background of its own every label resolves to white, which is why the first attempts came out with a sparkline, the level icons, and not one letter.
- **The README is a front page again, not an engineering diary.** It opened with the search that proved no such app existed, then API timings, then a memory comparison against SwiftBar, and reached "how do I install this" on line 54 of 311. It is 108 lines now: badges, install, what it shows, signing in, building, what it deliberately does not do, and an index. Every measurement moved rather than disappeared — into `docs/notes.md`, or into `SECURITY.md` where the entitlement trade belongs — and a check confirms all thirty figures and proper names from the old file still exist somewhere.
- **Every persisted key is in English, and the old values move across.** Nine `UserDefaults` keys and both Keychain accounts were Spanish. A rename that quietly forgets somebody's organization and refresh interval is data loss, not a rename, so the old names are copied forward once and then removed. The Keychain accounts move too, and it costs no extra password dialog: reading the new account finds no item, which never prompts, and reading the old one is the read that init already did. The refresh token migrates on first use rather than at startup, which is where the clock-before-Keychain rule from 0.6.0 wants it. The old names survive verbatim in one migration table and the test that exercises it, because there they are data.
- Comments and local names in `Centinela.entitlements`, `Tools/appcast.py`, `Tools/generate-icon.swift` and the issue fixture are English.

### Fixed

- **The README claimed the Keychain token was already readable by any process running as you, and it was not.** Measured on a throwaway item created by a signed build: `/usr/bin/security` reading it prompts, and `securityd` logs `displaying keychain prompt for /usr/bin/security`. The item is bound to a signature. That inverts the paragraph resting on it: `disable-library-validation` costs more than was written, not less, because code inside the process is exactly the identity the Keychain admits without asking.

## [0.6.1] — 2026-08-23

Signing in with the panel already open no longer leaves the issue list empty.
### Fixed

- **Signing in with the panel already open left the issue list empty over a menu bar counting 539 errors.** The cheap cycle was fixed in 0.6.0 to run the moment a session appears, but the expensive route hangs off the panel's `.task`, which runs once per appearance and never again: it had already run and returned at `guard let client` while there was still no token. It is keyed on the session being usable now, so it runs again the moment there is something to ask. Same shape as the bug above it, one level down, which is the argument for keying rather than adding another call site.

## [0.6.0] — 2026-08-23

Signing out actually clears the panel, one Sign out replaces two, and the menu bar stops claiming everything is fine when there is no session.
### Fixed

- **The signed-out menu bar icon was drawn in secondary grey and washed out.** The menu bar background is the wallpaper, so a dimmed glyph loses its contrast against a light desktop and reads as a rendering fault rather than as a state. It is drawn at full strength now; the crossed-out eye already carries the meaning without the dimming.
- **The release workflow asked GitHub for Sparkle's latest release to find its signing tools.** Unauthenticated, from a shared runner, that call hits the rate limit and returns a JSON error object, which surfaced as `KeyError: 'tag_name'` in the middle of a step named after signing. It reads the version out of `Package.resolved` now, which also fixes a quieter problem: the tools that sign an update were never guaranteed to be the version the app is built against.
- **Correction to 0.5.0: the Keychain dialog did not stop.** That release said the self-signed certificate ended it, and `SECURITY.md` carried a table with "Dialog: none". Both were wrong. There are two independent checks and the certificate fixes one. `securityd` names the other on a real update, same install path, both builds carrying the certificate: `ACL partition mismatch: client cdhash:553e48cc…`, then `displaying keychain prompt for /Applications/Centinela.app`. A keychain item has a partition list next to its access control list, and an application with no team identifier can only be identified there by its code hash, which every build changes. "Always Allow" adds that build's hash, which is why it asks once per update instead of once ever. The certificate still earns its place: it fixes the designated requirement, which is the other check.
- **The measurement that produced the wrong claim, and why it produced it.** The two binaries under test lived at different paths, and the ACL subject stores the path next to the requirement, so the probe never modelled an update, where the path never changes. Re-run today the same two binaries prompt. Both documents now say to print the value that is supposed to differ and assert it differs before trusting a result.
- **Two Keychain password dialogs per update instead of one.** The app holds two items, the access token and the refresh token, and `shouldRefresh` read the second one on every cycle before checking the clock. Reordering it so the clock goes first means the refresh token is only read when a renewal is actually due, which is once an hour rather than every five minutes, and one dialog after an update rather than two, confirmed on the real 0.5.0 → 0.6.0 update rather than on a probe. `Keychain.reads` exists so that ordering can be tested at all: the reorder changes no answer the function gives, only whether the Keychain was touched, so without a counter the test passes just as happily with the wrong order.
- **Signing out left the previous account's numbers in the menu bar.** It showed 539 errors above a panel that already said "Not configured yet". Not staleness: `refreshCheap` bailed out at `guard let client` before touching anything, so the series belonged to an account the app no longer had. Signing out now drops everything the session owned, straight away rather than at the next cycle five minutes later.
- **The menu bar showed a tick inside a seal while signed out.** A seal with a tick reads as "everything is fine", and with no session nothing is known to be fine: it was vouching for an account the app could no longer reach. Signed out it now shows a crossed-out eye in secondary grey, with no count and no sparkline, which says the app is not looking rather than that all is well.
- **Pasting a token on top of an OAuth session let the next cycle renew the old session over it.** `shouldRefresh` needs an expiry in the past AND a refresh token, and a pasted token cleared neither, so the token somebody had just typed was replaced by a renewal of the session they were leaving. Pasting now ends the OAuth session: expiry cleared, refresh token deleted. The device flow's own write is untouched, which is why this is a separate call and not a change to the shared one.
- **Signing in with Sentry left the app idle until the next five-minute tick.** Asking again was wired to the "Save token" button, so the device flow, which does not go through that button, signed somebody in and then showed them nothing. Measured on a real sign-in: the stored timestamp of the last refresh was still zero with a live session. It now hangs off the session becoming usable rather than off a button, which covers both ways in and is one rule instead of two. The condition is `isConfigured` and not `authMethod`, because the device flow stores the token first and resolves the organization second: the moment there is something to ask is when the second half arrives.
- **The account tab claimed the token lives in the app's container and pointed at `SECURITY.md` for why it is not in the Keychain.** It has been in the Keychain since 0.1.0. The claim was false in every release that carried it.

### Changed

- **The account tab branches on stored state instead of session state.** It used to switch on the sign-in controller's stage, which resets on every launch, so somebody already signed in was offered "Sign in with Sentry" and the only way back out lived in a branch that existed only right after a fresh device flow. `AppSettings.authMethod` is derived from the token and its expiry, both of which survive a restart.
- **One way out, and one way in at a time.** There were two sign-out affordances with different visibility rules and the same effect; now there is a single Sign out, same label and same place whichever way somebody signed in. The two ways in are no longer shown side by side with nothing to say which one is in effect: the device flow is the front door and the token field sits behind a disclosure.
- Organization, server and OAuth client are one Connection section, and all three stay editable while signed in: a self-hosted address typed wrong is exactly the case where a stored session cannot be used and the field is what needs fixing. As separate sections with a header and a footer each they did not fit the 430 pt window, and the render probe showed the last one cut off at the edge in all three states.

## [0.5.0] — 2026-08-23

Builds are signed with a stable identity, and the update dialog shows the changelog instead of GitHub's page.
### Fixed

- **macOS asks for the Keychain password less often.** (This entry said "stopped". It did not stop, and the correction is under Unreleased.) The cause was not a bug to work around: with an ad-hoc signature the app's designated requirement is literally its code hash, so every build was, to the Keychain, a different application asking for someone else's item. Builds are signed with a self-signed certificate now, which makes the requirement identity-based and stable. Measured on the same read: 7709 ms before, 18 ms after. **The claim that the dialog stopped was wrong and is corrected under Unreleased below.** The release workflow fails if a build ever comes out hash-signed, because a release signed ad-hoc would put the dialog back for everyone who updates.

  Three documented alternatives were tried first and none works without a stable identity: the data protection keychain returns `errSecMissingEntitlement`, `SecAccessCreate(nil)` trusts only the app that is about to stop existing, and `security -A` did not remove the delay. The certificate is **not** a Developer ID: Gatekeeper still asks for right-click-to-open, notarization is still impossible, and `disable-library-validation` is still required, because library validation wants a real team identifier and a self-signed certificate has none. All of it is in `SECURITY.md` with the numbers.

### Changed

- The update dialog shows the changelog itself instead of GitHub's release page. It was pointing at the page, so Sparkle rendered its chrome too: "Compare", "github-actions released this" and a commit list around the actual notes. Sparkle accepts `sparkle:format="markdown"` on `<description>`, so the section goes in verbatim with no conversion step to get wrong.

## [0.4.0] — 2026-08-23

Six more Sentry surfaces: performance, feedback, escalating and regressed issues, health, and filtering by project and environment.
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

Centinela updates itself through Sparkle, and `SECURITY.md` says what the Keychain does and does not buy.
### Added

- **Centinela updates itself**, through Sparkle. The previous release only told you a new version existed.

### Changed

- The README's claim that Sparkle could not work without a Developer ID was **wrong**, and it came from reading a summary instead of the source. Sparkle's `SUUpdateValidator.m` says the opposite: "if no Apple Code Signing certificate is available, adhoc signing can be used at minimum". Updates are verified with an EdDSA signature of this project's own, which does not involve Apple.
- Two entitlements are new and both are documented with what they give up. The one that costs something is `com.apple.security.cs.disable-library-validation`: without it dyld refuses to load Sparkle, because the hardened runtime wants every loaded library to share the app's Team ID and two ad-hoc signatures count as different teams.
- `SECURITY.md` now states what the Keychain does and does not buy. Measured: any process running as you reads the token with no prompt, because the item is not bound to the app's signature.

### Removed

- The hand-rolled update checker that read GitHub's releases API, along with its ten tests. Sparkle does the same job and also installs.

## [0.2.0] — 2026-08-22

The whole project is in English, and signing in goes through Sentry's OAuth device flow.
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

First release: the error count, a sparkline and the issue list in the menu bar.
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

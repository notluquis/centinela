# Engineering notes

Everything here was in `README.md` and was moved so the front page answers "what is this and how do I run it" first. Nothing was rewritten on the way: the measurements, the failures and the reasons are the same ones, and they are the point of keeping them.

## What it costs to ask Sentry

Measured against a real organization:

| API route | Time | Size |
|---|---|---|
| `events-stats` (the count and the sparkline) | 378 ms | 937 B |
| `uptime` | 490 ms | 591 B |
| `issues` (the list) | 1047 ms | 10.6 KB |

The issue list is **the most expensive route in the whole API**: three times slower and eleven times heavier than the series. That is why the periodic cycle never touches it and it is only fetched when the panel opens. The split is the architecture, not an optimization.

Reproduce it with your own token:

```bash
curl -s -o /dev/null -w '%{time_total}s %{size_download}B\n' \
  -H "Authorization: Bearer $TOKEN" \
  'https://sentry.io/api/0/organizations/YOUR_ORG/events-stats/?statsPeriod=24h&interval=1h&yAxis=count()&query=event.type:error&project=-1'
```

Worth knowing before trying to optimize: **Sentry's API exposes no `ETag` on any of these routes**, so there is no conditional revalidation (304) to exploit. Staying light means asking for little, not asking cheaply. `gzip` is there, and `URLSession` negotiates it on its own.

The measured limits, in case you raise the frequency: 40 requests per window per route (20 on `stats_v2`), 25 concurrent, and the window resets in under a second. The real ceiling is not Sentry, it is battery.

## Why it polls instead of waiting to be told

Sentry does have webhooks, and they are no use here. Its notifications are a POST to a URL, and to receive one you have to be **reachable from the public internet**: a server, a tunnel, something always on. A desktop app is none of those, and standing up a relay to avoid a five-minute poll trades a cheap request for a piece of infrastructure to maintain and pay for.

There is no streaming API either: no SSE, no websocket for issues.

What is done instead to avoid asking too much:

| Measure | Effect |
|---|---|
| The panel fetches when it opens | When you look, the data is from that second, not from the last cycle |
| The cycle asks only for the two cheap routes | 1.5 KB, not 10.6 KB |
| `Timer` with 20% tolerance | Lets the system coalesce the wake-up instead of pulling the CPU out of idle just for this |
| Stops on sleep, refreshes on wake | Zero requests while the lid is closed |

## What "native" means here, concretely

| | Centinela | SwiftBar plus a script |
|---|---|---|
| On disk | **5.3 MB** (2.8 is Sparkle, 1.1 the icon) | 7.1 MB |
| Resident, panel never opened | 7.6 MB | 6–8 MB |
| Resident, after opening it | ~25 MB | 6–8 MB |
| Per cycle | nothing: `async` inside the process | **+19 MB and 1.5 s**, an interpreter starting from scratch |
| Depends on | nothing | SwiftBar staying installed and staying working |

**Opening the panel triples memory and it does not come back down.** SwiftUI builds the window the first time it is shown and keeps it. Before that, both apps cost the same. If your criterion is steady-state RAM, SwiftBar wins, and that is worth knowing before installing anything.

- `MenuBarExtra` with `.menuBarExtraStyle(.window)`: an `NSMenu` cannot draw a sparkline or two-line rows.
- `@Observable` (Observation), not `ObservableObject`.
- Keychain for the token, not a dotfile. `SECURITY.md` has what that does and does not buy, with the measurements.
- `SMAppService` for launch at login. The old way (`SMLoginItemSetEnabled` plus a helper binary) was deprecated in macOS 13. The status is not a boolean: `.requiresApproval` means registered but pending the user's approval, and the UI says so instead of showing the switch off.
- Liquid Glass following the three rules in Apple's official [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) guide:
  1. *"Instead of creating buttons with custom Liquid Glass effects […] use one of the button style APIs"*. Hence `.buttonStyle(.glass)` and not a hand-drawn background.
  2. *"Audit the backgrounds of sheets and popovers […] remove those custom background views"*. Hence the panel's background is left alone: `MenuBarExtra(.window)` already draws it, and stacking another material on top looks murky, not glassy.
  3. *"Combine custom Liquid Glass effects […] using a GlassEffectContainer"*. Hence the three footer buttons live in one container instead of loose.

  All behind `#available(macOS 26.0)`: on 14 and 15 it falls back to the plain style, which is the right one there.
- Ephemeral `URLSession`: no disk cache, no cookies, nothing written.

## The menu bar on macOS 26 and 27

- **macOS 26 (Tahoe)** made the bar transparent by default: icons sit on the wallpaper, not on a solid bar. That is why Centinela sets no colours on the icon and lets the system work out contrast. The only colour of its own is the red of an outage, the one state that justifies breaking the rule.
- **macOS 27 (Golden Gate)** reworked how the bar renders and added a native button to reveal icons that do not fit. On the way it broke Bartender, Ice, Thaw, Hidden Bar, Barbee, Sane Bar and Glow, all of which *manage* other apps' icons. Adding your own is a different operation and was unaffected — verified on macOS 27.0 beta (build 26A5416b).

## No global keyboard shortcut

It would be the natural thing for a menu bar app, and **it cannot be done**: `MenuBarExtra` exposes no way to open its window from code. It is an open request in Apple's feedback system ([FB10185203](https://github.com/feedback-assistant/reports/issues/328)), unresolved as of August 2026.

The way out would be dropping `MenuBarExtra` and driving an `NSStatusItem` with a panel of our own, which is a full redesign for one shortcut. Noted, not done.

## Building without Xcode

Xcode is not needed. [`swiftly`](https://www.swift.org/install/macos/swiftly/), the official Swift toolchain manager, is enough:

```bash
brew install swiftly
swiftly init
swiftly install 6.3.3 --use
```

That is about 60 s of download against Xcode's ~18 GB, and from there `swift build` compiles SwiftUI, AppKit and ServiceManagement without trouble. A clean release build takes **60 s** on Apple Silicon.

**The Command Line Tools alone are NOT enough**, and the error does not help:

```
error: failed to build module 'SwiftUI'; this SDK is not supported by the compiler
(the SDK is built with 'swiftlang-6.2.3.3.2', while this compiler is 'swiftlang-6.2.3.3.21')
```

The CLT compiler and the CLT's own SDK come from different builds. `softwareupdate --list` offers no fix, and pointing at an older SDK (`MacOSX15.4.sdk`) only swaps the error for `redefinition of module 'SwiftBridging'`. The swiftly toolchain solves it because it brings a compiler consistent with itself.

Aside: **Objective-C does compile** with the CLT alone (`clang -framework Cocoa`, 1.2 s, a 52 KB binary). The wall is specific to Swift modules.

### Three traps that cost time here

**`XCTest` does not exist outside Xcode.** It ships with Xcode, not with the toolchain. The suite uses **Swift Testing**, which does ship with it — and which has been the default since 2026. If you port old tests, this is not optional: with XCTest the suite stops running on a machine without Xcode.

**Swift Testing exports its own `Issue`.** That is why the model here is called `SentryIssue`: in a file with `import Testing`, the short name resolves to theirs. The symptom says nothing useful — the compiler emits `failed to produce diagnostic for expression` on the call to `decode` — and you lose a while going over the `Codable`.

**`swiftlint` needs `sourcekitdInProc.framework`**, which it only looks for inside Xcode. Without Xcode it has to be pointed at the swiftly toolchain; `make lint` already does that, and now fails loudly when swiftlint is missing instead of skipping in silence. That silence is how 80 violations reached CI without ever showing up locally.

### Why there is no `.xcodeproj`

A `project.pbxproj` is a generated file tens of thousands of lines long that nobody reviews in a diff and that conflicts just from opening it. For an app with one binary and no extensions, `swift build` plus a dozen lines of `Makefile` do the same and can be read end to end.

The package is split into two targets for a concrete reason: `CentinelaCore` imports neither AppKit nor SwiftUI, so its suite runs with no graphics session, in CI or over SSH. That is where everything that can be wrong in a way you cannot see lives (parsing the responses, the sparkline arithmetic, the Keychain); `Centinela` is only the shell that draws.

## Cutting a release

Tag and push:

```bash
git tag -a v0.7.0 -m "Centinela 0.7.0"
git push origin v0.7.0
```

The workflow does the rest, and refuses to publish when something does not add up:

| Check | Why |
|---|---|
| `CHANGELOG.md` has a `## [0.7.0]` section | Without it the release would go out with an empty body and nobody would notice until they read it |
| The bundle's version equals the tag | A mistyped tag used to ship an artifact claiming something else |
| The designated requirement is identity-based, not a hash | A release signed ad-hoc reintroduces a Keychain dialog for everyone who updates |
| `LSUIElement` is true and the signature verifies | Building is not proof the bundle is right |

The notes are assembled from two halves: the CHANGELOG section says **why** the change matters, and the list GitHub generates from merged pull requests says **what** changed, categorized by `.github/release.yml`. A list of commit subjects cannot explain that a token was over-privileged, so the changelog stays hand-written on purpose.

Sparkle's signing tools are pinned to the version in `Package.resolved` rather than fetched as "latest": signing with tools other than the ones the app is built against is not reproducible, and the unauthenticated API call that asked for the latest release hit the shared runner rate limit and failed a release.

## Distribution

Releases are signed with a self-signed certificate, no Developer ID and no notarization. macOS asks for confirmation the first time: right click, Open.

Notarizing costs 99 USD a year and, for a tool that runs on the Macs of whoever builds it, does not pay for itself. If that changes: a `Developer ID Application` in the runner's keychain and an `xcrun notarytool submit --wait` step. The `Makefile` already accepts `IDENTITY=` so it does not have to be touched. `SECURITY.md` has what the certificate does and does not fix, measured.

Check what you downloaded:

```bash
codesign -dv --verbose=4 Centinela.app
spctl -a -t exec -vvv Centinela.app
```

## There was no app to use

Searched on 2026-08-22, which is why this exists:

| Where | Result |
|---|---|
| GitHub repositories, 4 queries | Nothing. Everything that comes up uses "sentry" as a common noun: ports, notch, pomodoro |
| Sentry's Raycast extension | Both its commands are `mode: "view"`, i.e. a search box. No menu bar command |
| Homebrew casks | Only `sentry-cli` |
| xbar plugins | One, pointing at the legacy `app.getsentry.com` domain and a single project |

## Sparkle works without a Developer ID

An earlier version of the README claimed automatic updates were impossible without one. **That was wrong**, and it came from reading a summary instead of the source. Sparkle's own update policy, in `SUUpdateValidator.m`, only refuses to *remove* code signing or EdDSA keys, and says it outright:

> If no Apple Code Signing certificate is available, adhoc signing can be used at minimum.

Sparkle's framework ships ad-hoc signed itself (`codesign -dv` reports `Signature=adhoc`, `TeamIdentifier=not set`).

What an update is verified against is an **EdDSA signature** made with a key pair of this project: the public half sits in `Info.plist` as `SUPublicEDKey`, the private half exists only as a repo secret used by the release workflow. Apple is not involved in that check, which is why the signature Apple would care about is not in the way.

## Mutation testing, and why it is not running

`muter.conf.yml` and `.github/workflows/mutation.yml` have been in this repository since early on and **had never once executed**. The workflow was weekly and was added days before the first Monday, so the first real run was triggered by hand. It failed five times, each failure hiding the next:

| | What happened | Why |
|---|---|---|
| 1 | `Unknown option '--output-json'` | That flag does not exist. The real signature is `--format json --output <file>`, and the run died before mutating a line |
| 2 | `Failed to clone repository … Sparkle` | Muter mutates a **copy** and resolves dependencies there. Nothing had filled SwiftPM's shared cache, so the copy tried to clone over the network |
| 3 | Mutated `Sources/Centinela/PanelRows.swift` and emitted Swift that does not compile | `mutateFilesInDirectories` is ignored. Selection moved to `--files-to-mutate`, which muter's own `run --help` prints |
| 4 | `Applying debug entitlements … unable to spawn process` | `swift test` in debug makes SwiftPM code-sign the executable target, and that spawn fails inside muter. A release build never reaches it, and it is what `make test` runs anyway |
| 5 | The suite fails on the baseline, in `Renamed preference keys carry their old values over` | Unresolved |

The fifth was the last one that could be fixed here. Building muter from `main` instead of installing release 16 gets past it — release 16 is from September 2023 and predates Swift Testing entirely, so it parses XCTest output while this suite contains none, and `main` carries "Fix: detect Swift Testing failures in mutation test logs" from July 2026 that no release has.

The run then completes and produces a report, and the report says **0 of 45 mutants killed**.

That number is not about the tests. The mutants landed on lines that named tests cover:

| Mutant | Test that must kill it |
|---|---|
| `Keychain.swift:73`, `\|\|` → `&&` in `delete` | "Deleting twice does not fail the second time" |
| `Sparkline.swift:20` and `:29`, relational operators | The whole `Sparkline` suite |
| `Models.swift:203`, the connector in `CronMonitor.isActive` | The decoding tests |

Forty-five out of forty-five surviving, in code the suite exercises, means the mutated code never ran. That is filed upstream twice: #307, "Schemata silently never applied: ApplySchemata re-parses sources, so node-identity-keyed SchemataMutationMapping never matches (replays run unmutated code)", and #310, "Fix schemata never being applied after a re-parse (SPM score always 0%)". Both open.

So: mutation testing does not work on this project with any muter that exists, and the 0% is a property of the tool rather than a measurement of the suite. The workflow now fails when nothing is killed, because a green job reporting 0% teaches the opposite of what it should.

The original fifth failure is where it stood before that. That test passes locally, passes in CI, and passes when the tracked files are copied to another directory and run there with the same `swift test -c release`, which is the closest reproduction of what muter does. What is left that differs is muter's own transformation: it inserts every mutant into the source behind `ProcessInfo.processInfo.environment[…] != nil`, and failure 3 is direct evidence that those insertions can be malformed — it produced `return milliseconds >= 1000?`. A malformed insertion in `AppSettings.swift` that breaks the migration even with the mutant switched off would fail exactly this test and nothing else.

The schedule is off until a run gets past the baseline. A job that fails every Monday teaches people to ignore Monday.

**What it found anyway.** Four real defects in a configuration that had looked configured for weeks, and one thing no sweep of ours caught: failure 3 emitted broken Swift inside `duracion(_ milisegundos:)`, which is how the last two Spanish identifiers in the codebase were found. The English sweep before it used a dictionary chosen by hand, so it could only find words somebody thought of. The tool that knows no Spanish found the one that was missed.

# Centinela

Your Sentry issues in the macOS menu bar. A count, a sparkline of the last few hours, and the state of your uptime monitors, without opening a browser.

There is no official Sentry app for macOS, and no third-party one either. Searched on 2026-08-22:

| Where | Result |
|---|---|
| GitHub repositories, 4 queries | Nothing. Everything that comes up uses "sentry" as a common noun: ports, notch, pomodoro |
| Sentry's Raycast extension | Both its commands are `mode: "view"`, i.e. a search box. No menu bar command |
| Homebrew casks | Only `sentry-cli` |
| xbar plugins | One, pointing at the legacy `app.getsentry.com` domain and a single project |

This fills that gap.

**Actually native**: SwiftUI, `MenuBarExtra`, a 5.3 MB app. Not a web wrapper and not a script inside somebody else's app.

## What it shows

| Where | What | When it is fetched |
|---|---|---|
| Menu bar | Errors in the chosen window, with a sparkline | Every cycle (5 min by default) |
| Menu bar | Red icon when an uptime monitor or a cron is down | Every cycle |
| Panel, Issues | Unresolved, for review, **escalating**, **regressed** | When the panel opens |
| Panel, Health | Uptime, cron monitors, crash-free sessions, errors by project | Uptime and crons every cycle; the rest on open |
| Panel, Releases | Latest releases and how many new issues each brought | When the panel opens |

Escalating and regressed are Sentry's own triage rather than ours: the first means it decided an issue is getting worse, the second that it came back after being marked resolved. Both arrive with `substatus` set, which is how the rows tell them apart.

Everything can be narrowed **by project** and, when there is more than one, **by environment**. Both travel through a single place in the client so no query can quietly ignore them.

That split is where being light comes from, and it is measured against a real organization:

| API route | Time | Size |
|---|---|---|
| `events-stats` (the count and the sparkline) | 378 ms | 937 B |
| `uptime` | 490 ms | 591 B |
| `issues` (the list) | 1047 ms | 10.6 KB |

The issue list is **the most expensive route in the whole API**: three times slower and eleven times heavier than the series. That is why the periodic cycle never touches it and it is only fetched when the panel opens.

Reproduce the measurement with your own token:

```bash
curl -s -o /dev/null -w '%{time_total}s %{size_download}B\n' \
  -H "Authorization: Bearer $TOKEN" \
  'https://sentry.io/api/0/organizations/YOUR_ORG/events-stats/?statsPeriod=24h&interval=1h&yAxis=count()&query=event.type:error&project=-1'
```

Worth knowing before trying to optimize: **Sentry's API exposes no `ETag` on any of these routes**, so there is no conditional revalidation (304) to exploit. Staying light means asking for little, not asking cheaply. `gzip` is there, and `URLSession` negotiates it on its own.

The measured limits, in case you raise the frequency: 40 requests per window per route (20 on `stats_v2`), 25 concurrent, and the window resets in under a second. The real ceiling is not Sentry, it is battery.

## Install

```bash
git clone https://github.com/notluquis/centinela.git
cd centinela
make install          # builds, assembles the .app and copies it to /Applications
open /Applications/Centinela.app
```

Then: click the icon, **Open Settings**, sign in.

Requires macOS 14 or newer. **Xcode is not required** — see [Building](#building).

## Signing in

Centinela **only reads**, and there are two ways to give it access.

### With the device flow

Click "Sign in with Sentry": the app asks for a code, opens the browser, you approve, and Sentry hands back a token with **exactly** the scopes that were requested.

The ones Centinela asks for, and no others:

```
org:read  project:read  event:read
```

There is a test that goes red if anyone adds a write scope, because the scopes are part of the contract with whoever runs this, not an internal detail.

**There is nothing to configure.** The client id ships in the source, which is where it belongs: RFC 8628 treats these as public clients and there is no secret to protect. `sentry-cli` does the same with its own.

Verified against sentry.io on 2026-08-22:

```
POST /oauth/device/code/  {client_id, scope: "org:read project:read event:read"}
→ 200 {"device_code":"98f0…","user_code":"CZCS-FSLC",
       "verification_uri":"https://sentry.io/oauth/device/",
       "verification_uri_complete":"…?user_code=CZCS-FSLC",
       "expires_in":600,"interval":5}

POST /oauth/token/  (before approving)
→ 400 {"error":"authorization_pending"}
```

The token renews itself once less than 10% of its life remains, which is `sentry-cli`'s rule. Sentry rotates the refresh token, so renewal keeps the new one when it arrives and the old one when it does not; there is a test for each branch. A failed renewal does **not** sign you out: there may simply be no network, and the old token keeps working until Sentry answers 401.

#### Registering your own client

Only if you would rather the approval dialog said your name instead of "Centinela". What you create is an **API Application**, which is not where you would look for it:

| | |
|---|---|
| Where | `https://sentry.io/settings/account/api/applications/`, i.e. **your account's** settings, not the organization's |
| Type | **Public Client**. The one the screen itself describes as "for CLIs, native apps […] uses PKCE, device authorization, and refresh token rotation" |
| Redirect URIs | Leave empty. The device flow redirects nowhere, which is the point of it |
| What it is NOT | Not an internal or public integration under *Developer Settings*: those hand back a token, or are meant for the authorization-code flow |

The endpoint does `ApiApplication.objects.get(client_id=…, status=active)` and nothing else (`src/sentry/web/frontend/oauth_device_authorization.py`): nothing to tick, no need to publish the application. Paste the Client ID in Settings, Account tab.

### With a hand-pasted token

Still works, and it is the only way on instances older than Sentry 26.1.0 (there the endpoint does not exist and the app says so in those words rather than giving a generic error).

1. In Sentry: *Settings, Developer Settings, Organization Tokens, Create New Token*.
2. Give it exactly these scopes and no others:

| Scope | What for |
|---|---|
| `org:read` | The organization, the uptime monitors and the releases |
| `project:read` | The project list |
| `event:read` | Issues and the error series |

3. Paste it in Settings. It is stored in the macOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: it does not sync to iCloud and does not come back from a backup restored on another machine.

**Do not reuse `sentry-cli`'s token.** That one uploads sourcemaps and publishes releases, which means it carries write access. Centinela detects it and says so in the panel: if the token can read `/audit-logs/`, it is not read-only. The check exists because the first token used here was exactly that one, and it read the audit log without complaint.

## Building

```bash
make build     # swift build -c release
make test      # 63 tests, no graphics session needed
make lint      # swiftlint --strict
make app       # assembles build/Centinela.app and signs it ad-hoc
make run       # the above, then opens it
```

A clean release build takes **60 s** on Apple Silicon. The app comes out at 5.3 MB: 2.8 of that is Sparkle and 1.1 the `.icns`.

### Without Xcode, with swiftly

Xcode is not needed. [`swiftly`](https://www.swift.org/install/macos/swiftly/), the official Swift toolchain manager, is enough:

```bash
brew install swiftly
swiftly init
swiftly install 6.3.3 --use
```

That is about 60 s of download against Xcode's ~18 GB, and from there `swift build` compiles SwiftUI, AppKit and ServiceManagement without trouble.

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
- Keychain for the token, not a dotfile, which needs a stable signing identity to be usable: with an ad-hoc signature macOS asks for a password on every update. `SECURITY.md` has the measurements.
- `SMAppService` for launch at login. The old way (`SMLoginItemSetEnabled` plus a helper binary) was deprecated in macOS 13. The status is not a boolean: `.requiresApproval` means registered but pending the user's approval, and the UI says so instead of showing the switch off.
- Liquid Glass following the three rules in Apple's official [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) guide:
  1. *"Instead of creating buttons with custom Liquid Glass effects […] use one of the button style APIs"*. Hence `.buttonStyle(.glass)` and not a hand-drawn background.
  2. *"Audit the backgrounds of sheets and popovers […] remove those custom background views"*. Hence the panel's background is left alone: `MenuBarExtra(.window)` already draws it, and stacking another material on top looks murky, not glassy.
  3. *"Combine custom Liquid Glass effects […] using a GlassEffectContainer"*. Hence the three footer buttons live in one container instead of loose.

  All behind `#available(macOS 26.0)`: on 14 and 15 it falls back to the plain style, which is the right one there.
- Ephemeral `URLSession`: no disk cache, no cookies, nothing written.

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

## Updates

Centinela updates itself, through [Sparkle](https://sparkle-project.org).

An earlier version of this README claimed that was impossible without a Developer ID. **That was wrong**, and it came from reading a summary instead of the source. Sparkle's own update policy, in `SUUpdateValidator.m`, only refuses to *remove* code signing or EdDSA keys, and says it outright:

> If no Apple Code Signing certificate is available, adhoc signing can be used at minimum.

Sparkle's framework ships ad-hoc signed itself (`codesign -dv` reports `Signature=adhoc`, `TeamIdentifier=not set`).

What an update is verified against is an **EdDSA signature** made with a key pair of this project: the public half sits in `Info.plist` as `SUPublicEDKey`, the private half exists only as a repo secret used by the release workflow. Apple is not involved in that check, which is why the ad-hoc signature is not in the way.

### What it costs, stated plainly

Two entitlements that would not otherwise be here:

| Entitlement | Why | What it gives up |
|---|---|---|
| `com.apple.security.temporary-exception.mach-lookup.global-name` (`-spks`, `-spki`) | A sandboxed app cannot replace itself, so Sparkle installs from `Installer.xpc` and has to look it up by name | Little: it can talk to two named services, both shipped inside the bundle |
| `com.apple.security.cs.disable-library-validation` | Without it dyld refuses to load Sparkle: the hardened runtime requires every loaded library to share the app's Team ID, and two ad-hoc signatures count as different teams. The measured error is `mapping process and mapped file (non-platform) have different Team IDs` | Real: any code-signed library placed in the bundle can be loaded into the process |

That second one is the honest cost. It is worth weighing against what it protects:

**An earlier version of this section said the token was already readable by any process running as you, and that was wrong.** Measured on a throwaway item created by a signed build: `/usr/bin/security` reading it prompts for the login password, and `securityd` logs `displaying keychain prompt for /usr/bin/security`. The item **is** bound to a signature, so the Keychain does buy per-application isolation on top of storage that is not a plaintext file and that needs the machine unlocked.

Which makes the entitlement cost more than that older paragraph claimed, not less. Library validation is what stops a code-signed library from being loaded into this process, and code running inside the process is precisely the identity the Keychain lets through without asking. Placing such a library still requires write access to the bundle in `/Applications`, which is to say another process running as you — so the entitlement does not create the exposure on its own, it removes the last obstacle for something that already has a foothold. A Developer ID (99 USD a year) removes the need for the entitlement entirely; until then this is the trade, written down rather than buried, and now written down correctly.

## No global keyboard shortcut

It would be the natural thing for a menu bar app, and **it cannot be done**: `MenuBarExtra` exposes no way to open its window from code. It is an open request in Apple's feedback system ([FB10185203](https://github.com/feedback-assistant/reports/issues/328)), unresolved as of August 2026.

The way out would be dropping `MenuBarExtra` and driving an `NSStatusItem` with a panel of our own, which is a full redesign for one shortcut. Noted, not done.

## Releases

Tag and push:

```bash
git tag -a v0.2.0 -m "Centinela 0.2.0"
git push origin v0.2.0
```

The workflow does the rest, and refuses to publish when something does not add up:

| Check | Why |
|---|---|
| `CHANGELOG.md` has a `## [0.2.0]` section | Without it the release would go out with an empty body and nobody would notice until they read it |
| The bundle's version equals the tag | A mistyped tag used to ship an artifact claiming something else |
| `LSUIElement` is true and the signature verifies | Building is not proof the bundle is right |

The notes are assembled from two halves: the CHANGELOG section says **why** the change matters, and the list GitHub generates from merged pull requests says **what** changed, categorized by `.github/release.yml`. A list of commit subjects cannot explain that a token was over-privileged, so the changelog stays hand-written on purpose.

## The menu bar on macOS 26 and 27

- **macOS 26 (Tahoe)** made the bar transparent by default: icons sit on the wallpaper, not on a solid bar. That is why Centinela sets no colours on the icon and lets the system work out contrast. The only colour of its own is the red of an outage, the one state that justifies breaking the rule.
- **macOS 27 (Golden Gate)** reworked how the bar renders and added a native button to reveal icons that do not fit. On the way it broke Bartender, Ice, Thaw, Hidden Bar, Barbee, Sane Bar and Glow, all of which *manage* other apps' icons. Adding your own is a different operation and was unaffected — verified on macOS 27.0 beta (build 26A5416b).

## Distribution

CI builds are signed **ad-hoc**, with no Developer ID and no notarization. macOS asks for confirmation the first time: right click, Open.

Notarizing costs 99 USD a year and, for a tool that runs on the Macs of whoever builds it, does not pay for itself. If that changes: a `Developer ID Application` in the runner's keychain and an `xcrun notarytool submit --wait` step. The `Makefile` already accepts `IDENTITY=` so it does not have to be touched.

Check what you downloaded:

```bash
codesign -dv --verbose=4 Centinela.app
spctl -a -t exec -vvv Centinela.app
```

## What is not verified

Two things are in the code without live data behind them, and they say so rather than pretending:

| | Why |
|---|---|
| **Cron monitors** | The organization this was built against has none. The decoder comes from Sentry's published OpenAPI schema (`getsentry/sentry-api-schema`) and the fixture is derived from it, the same way the device flow was handled before there was a client id to try |
| **Incidents and alert rules** | Deliberately absent. No data to look at, and Sentry does not publish their schema either, so a decoder would be a guess. They get added when there is something to check them against |

## What it does NOT do, on purpose

| Does not | Why |
|---|---|
| Desktop notifications | Sentry already notifies by email and Slack. Duplicating that is two alarms for one event |
| Resolve, assign or mute issues | The token is read-only and that is the property worth keeping. It opens the issue in the browser, where there is a session with permissions |
| Store issues on disk | Error titles carry business data. The network session is ephemeral |
| Multiple organizations | One, the token's. It gets added when it is actually needed |
| Self-hosted Sentry | Should work by changing the server in Settings, but it is untested |

## Licence

MIT. See [LICENSE](LICENSE).

Not affiliated with Sentry (Functional Software, Inc.). Uses its public read API.

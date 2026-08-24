# Centinela

[![CI](https://github.com/notluquis/centinela/actions/workflows/ci.yml/badge.svg)](https://github.com/notluquis/centinela/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/notluquis/centinela?sort=semver)](https://github.com/notluquis/centinela/releases/latest)
[![Platform](https://img.shields.io/badge/macOS-14%2B-blue)](#requirements)
[![Licence](https://img.shields.io/github/license/notluquis/centinela)](LICENSE)

Your Sentry issues in the macOS menu bar. A count, a sparkline of the last few hours, and the state of your uptime monitors, without opening a browser.

<p align="center">
  <img src="docs/panel.png" alt="The panel, showing an error count, a sparkline of the last 24 hours and a list of unresolved issues" width="820">
</p>

Actually native: SwiftUI, `MenuBarExtra`, a 5.6 MB app, **read-only** access to Sentry. Not a web wrapper and not a script inside somebody else's app. There was no other one to use — [the search that says so](docs/notes.md#there-was-no-app-to-use) is written down.

## Install

Download `Centinela.zip` from the [latest release](https://github.com/notluquis/centinela/releases/latest), unzip it into `/Applications`, then **right click → Open** the first time. Builds are signed with a self-signed certificate rather than a Developer ID, so Gatekeeper asks once.

From source instead:

```bash
git clone https://github.com/notluquis/centinela.git
cd centinela
make install          # builds, assembles the .app and copies it to /Applications
open /Applications/Centinela.app
```

Then click the icon, **Open Settings**, and sign in.

It keeps itself up to date through [Sparkle](https://sparkle-project.org), verified against an EdDSA key of this project rather than against Apple.

## Requirements

macOS 14 or newer. **Xcode is not required** to build it — the [swiftly](https://www.swift.org/install/macos/swiftly/) toolchain is enough.

## What it shows

| Where | What | When it is fetched |
|---|---|---|
| Menu bar | Errors in the chosen window, with a sparkline | Every cycle (5 min by default) |
| Menu bar | Red icon when an uptime monitor or a cron is down | Every cycle |
| Menu bar | A crossed-out eye when there is no session | — |
| Panel, Issues | Unresolved, for review, **escalating**, **regressed** | When the panel opens |
| Panel, Health | Uptime, cron monitors, crash-free sessions, errors by project | Uptime and crons every cycle; the rest on open |
| Panel, Performance | Slowest transactions by p95 span duration | When the panel opens |
| Panel, Releases | Latest releases and how many new issues each brought | When the panel opens |
| Panel, Feedback | User feedback and session replays, only when there is any | When the panel opens |

Escalating and regressed are Sentry's own triage rather than ours: the first means it decided an issue is getting worse, the second that it came back after being marked resolved.

Everything can be narrowed **by project** and, when there is more than one, **by environment**. Both travel through a single place in the client so no query can quietly ignore them.

The periodic cycle only asks for the two routes measured as cheap; the issue list is the most expensive route in the whole API and is fetched when you open the panel. [The numbers](docs/notes.md#what-it-costs-to-ask-sentry).

## Signing in

Centinela **only reads**. Two ways in, offered one at a time:

- **Sign in with Sentry** — OAuth device flow ([RFC 8628](https://datatracker.ietf.org/doc/html/rfc8628)). It asks for `org:read`, `project:read` and `event:read`, and nothing else; a test fails if a write scope is ever added. Needs Sentry 26.1.0 or newer. There is nothing to configure: the client id ships in the source, which is where a public client's id belongs.
- **Paste a token** — the only way on older self-hosted instances. Give it the same three scopes.

Either way the token is kept in the Keychain, never in `UserDefaults` and never in a file. Centinela warns you if the token can read the organization's audit log, which means it carries write access it does not need. **Do not reuse `sentry-cli`'s token**: that one uploads source maps and can write.

What the Keychain does and does not buy, measured, is in [SECURITY.md](SECURITY.md).

## Building

```bash
make build     # swift build -c release
make test      # the whole suite, no graphics session needed
make lint      # swiftlint --strict
make app       # assembles build/Centinela.app and signs it
make run       # the above, then opens it
make screenshot # regenerates docs/panel.png from invented data
```

The package is two targets on purpose: `CentinelaCore` imports neither AppKit nor SwiftUI, so everything that can be wrong invisibly — parsing, the sparkline arithmetic, the Keychain — is tested without a graphics session. [Why there is no `.xcodeproj`, and the three toolchain traps that cost time here](docs/notes.md#building-without-xcode).

## What is not verified

Some of this is in the code without live data behind it, and says so rather than pretending:

| | Why |
|---|---|
| **Cron monitors** | The organization this was built against has none. The decoder comes from Sentry's published OpenAPI schema (`getsentry/sentry-api-schema`), the fixture is derived from it, and the test pins a shape nobody has seen live rather than proving it right |
| **Session replays and user feedback** | The same: none of either here, decoders written against the schema, tests that pin the shape |
| **Incidents and alert rules** | Deliberately absent. No data to look at, and Sentry does not publish their schema either, so a decoder would be a guess |
| **Mutation testing** | Configured, and it has never produced a usable number. Every muter that exists reports 0 of 45 mutants killed on code the suite demonstrably covers, which is [an open upstream bug](docs/notes.md#mutation-testing-and-why-it-is-not-running) and not a statement about the tests |

## What it does NOT do, on purpose

| Does not | Why |
|---|---|
| Write anything to Sentry | Not resolving, not assigning, not muting. The token being read-only is the property worth keeping |
| Desktop notifications | Sentry already notifies by email and Slack. Duplicating that is two alarms for one event |
| Store issues on disk | Error titles carry business data. The network session is ephemeral |
| Multiple organizations | One, the token's. It gets added when it is actually needed |
| A global keyboard shortcut | `MenuBarExtra` [exposes no way](docs/notes.md#no-global-keyboard-shortcut) to open its window from code |
| Self-hosted Sentry | Should work by changing the server in Settings, but it is untested |

## Documentation

| | |
|---|---|
| [CHANGELOG.md](CHANGELOG.md) | What changed and why, hand-written, including the claims that turned out to be wrong |
| [SECURITY.md](SECURITY.md) | Where the token lives, what the signing certificate fixes and what it does not, all measured |
| [docs/notes.md](docs/notes.md) | API costs, why it polls, what "native" costs in RAM, building without Xcode, cutting a release |
| [AGENTS.md](AGENTS.md) | The rules this repository is held to, each one naming something that already went wrong |

## Licence

MIT. See [LICENSE](LICENSE).

Not affiliated with Sentry (Functional Software, Inc.). Uses its public read API.

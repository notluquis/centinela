# Instructions for AI agents

This is a menu bar app that reads Sentry's API with a token. The rules below are not style preferences: each one names something that already happened.

## Non-negotiable

**1. Read-only, always.** Nothing that writes to Sentry: no resolving, no assigning, no muting, no publishing releases. The code must not exist, not even disabled and not behind a flag. The property being protected is that the token *can* be read-only; the moment there is a write path, the user needs a more powerful token and the guarantee is empty.

**2. The token lives in the Keychain.** Never in `UserDefaults`, never in a file, never in a log, never in an error message. A Sentry organization token does not expire on its own. This project started because the token was sitting in `~/.sentryclirc` in plain text.

**3. No real data in the repository.** The fixtures are invented and stay that way: real responses carry error titles with internal URLs and business data, and this is public. A CI job fails if something shaped like a Sentry token or a real name shows up in the fixtures. Both guards were probed by injecting the violation, not by watching them pass.

**4. Nothing is written to disk at run time.** `URLSessionConfiguration.ephemeral`, no cache, no cookies. If something ever has to be persisted, it should not be issue titles.

**5. A measured number or none at all.** The README states API timings and sizes. If you change one, run it; if you add one, measure it. A number copied out of Sentry's documentation is not a measured number.

**6. English.** Interface, source, comments, documentation, commit messages. This is a public repository.

## What to understand before touching the client

**The cheap/expensive split is the architecture, not an optimization.** `refreshCheap()` runs every cycle and asks for `events-stats` (378 ms / 937 B) and `uptime` (490 ms). `refreshExpensive()` asks for the issue list (1047 ms / 10.6 KB) and is called **only** when the panel opens. Moving the list into the periodic cycle multiplies the app's traffic elevenfold so that nobody looks at the result.

**There is no `ETag` in Sentry's API.** Measured: none of these routes returns one, so there is no 304. If someone proposes "cache with conditional revalidation", the answer is that there is nothing to revalidate against.

**Sentry announces deprecations through headers.** `X-Sentry-Deprecation-Date` and `X-Sentry-Replacement-Endpoint`. The client reads them and the panel says so. Do not drop that: without it the app finds out about a change on the day it breaks.

**The three odd shapes of the response.** They are commented in the code, at the exact spot where they bite, and each has a test:

| Field | What you would expect | What Sentry sends |
|---|---|---|
| `issue.count` | a number | **text** (`"13"`), while `userCount` really is a number |
| dates | one format | **two**: with and without fractional seconds, in the same response |
| `events-stats.data` | objects | heterogeneous pairs `[epoch, [{"count": n}]]` |

Declaring `count` as `Int` does not break that field: it fails the whole array with `typeMismatch`.

**Trailing slashes are load-bearing.** `…/projects` without one returns a flat 404 with no redirect (measured against sentry.io).

## Toolchain traps

**`XCTest` does not exist outside Xcode.** The suite uses Swift Testing and must keep doing so: with XCTest it stops running on a machine with only `swiftly`, which is the workflow the README documents.

**Swift Testing exports its own `Issue`.** That is why the model is called `SentryIssue`. If you rename it to `Issue`, any file with `import Testing` stops compiling with `failed to produce diagnostic for expression`, which mentions the ambiguity nowhere.

**A default parameter value is not evaluated on the main actor.** `init(settings: AppSettings = AppSettings())` on a `@MainActor` type gives `#ActorIsolatedCall`. It goes as `AppSettings? = nil` and is resolved inside.

**`swiftlint` needs `sourcekitdInProc.framework` from Xcode.** `make lint` points `DYLD_FRAMEWORK_PATH` at the swiftly toolchain and fails when swiftlint is missing. It used to skip in silence, which is how 80 violations reached CI unseen.

## SwiftUI traps, measured

**Do not "fix" the panel's `ScrollView` by measuring its content.** It was tried: a `PreferenceKey` measuring the content fed back into `.frame(height:)`. Measured with `NSHostingView` against the real layout, the original arrangement lays out to its full 250 pt and the measured version sits at 91 pt, because the loop "the frame height depends on the preference, which depends on the frame height" never converges. `.frame(maxHeight:)` and nothing else.

**A `MenuBarExtra` label only renders `Text` and `Image` reliably.** The sparkline is drawn as an `NSImage`: as a SwiftUI shape it showed up in the panel and not in the bar.

**An `LSUIElement` app has to activate itself before opening Settings**, or the window comes up behind everything and the button looks broken.

## Before calling something done

```bash
make build   # zero errors and zero warnings
make test    # 45 tests, all green
make lint    # zero violations
make app     # the bundle assembles and the signature verifies
```

And if you added a guard, break it once and confirm it goes red. A guard that cannot fail prints exactly the same thing as one that protects.

## Releases

`CHANGELOG.md` is written by hand and the release workflow reads the section for the tag out of it, refusing to publish when it is missing. The generated list of pull requests goes underneath, categorized by `.github/release.yml`. Do not replace the hand-written half with generated commit subjects: a subject line cannot explain why a change matters.

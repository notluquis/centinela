# Security

## What this app handles

A Sentry API token with read scopes, and the issue titles that token returns. Error titles often
carry internal URLs, identifiers and fragments of business data.

## How it is stored

| Data | Where | Detail |
|---|---|---|
| Access and refresh tokens | macOS Keychain | `kSecClassGenericPassword`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, not synchronized |
| Organization, server, interval, OAuth client id | `UserDefaults` | None of these are secrets |
| Issues, releases, uptime | Memory only | `URLSessionConfiguration.ephemeral`: no disk cache, no cookies |

Nothing Sentry returns is written to disk.

**What the Keychain does and does not buy here.** Measured, not assumed: any process running as
you can read the token with `security find-generic-password -s cl.bioalergia.centinela -a
token-de-organizacion -w`, with no prompt. The item is not bound to this app's signature. What the
Keychain buys is that the token is not a plaintext file in your home directory, that it does not
travel in a backup restored onto another machine, and that the machine has to be unlocked. It does
not buy isolation from other software you run. If that matters to you, give Centinela a token
scoped to a single project rather than the whole organization.

## What the app asks the system for

Sandbox on. Two permissions, and they can be read end to end in `Centinela.entitlements`:

| Entitlement | Why |
|---|---|
| `com.apple.security.app-sandbox` | |
| `com.apple.security.network.client` | Reach Sentry |
| `com.apple.security.temporary-exception.mach-lookup.global-name` | A sandboxed app cannot replace itself; Sparkle installs updates from `Installer.xpc` and looks it up by name. Both services ship inside the bundle |
| `com.apple.security.cs.disable-library-validation` | Without it dyld refuses to load Sparkle: the hardened runtime wants every loaded library to share the app's Team ID, and two ad-hoc signatures count as different teams |

No files, no camera, no contacts, no inbound network server. If one more ever appears, it shows
up in the diff.

The last one is the only entitlement here that gives something up: any code-signed library placed
inside the bundle can be loaded into the process. It buys automatic updates without a 99-USD-a-year
Developer ID. Given that the token is already readable by any process running as you (above), it
does not meaningfully change the token's exposure, but it does widen code injection in general.
With a Developer ID the entitlement is unnecessary and should be removed.

`keychain-access-groups` is deliberately not declared: `$(AppIdentifierPrefix)` only expands with
a provisioning profile and these builds are signed ad-hoc. Without the key, the default group is
the app's own identifier, which is what is wanted. Verified by running a sandboxed, ad-hoc-signed
bundle: `SecItemAdd` returns 0 and the value reads back.

## The token you give it

Signing in through the device flow requests `org:read`, `project:read` and `event:read`, and
nothing else. A test fails if a write scope is ever added.

Centinela checks whether the token can read the organization's `/audit-logs/`. If it can, it
carries write access and the panel says so. **Do not reuse `sentry-cli`'s token**: that one
uploads sourcemaps and publishes releases.

## Reporting a problem

Open an issue in the repository. If the finding exposes data, write to the address on the
author's GitHub profile instead of opening it in public.

## What this project does not promise

- Published builds are signed ad-hoc and not notarized. Check what you downloaded with
  `codesign -dv --verbose=4` and `spctl -a -t exec -vvv` before opening it.
- There are no automatic updates. Nothing is downloaded or executed on its own.

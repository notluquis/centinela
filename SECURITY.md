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

## What the app asks the system for

Sandbox on. Two permissions, and they can be read end to end in `Centinela.entitlements`:

- `com.apple.security.app-sandbox`
- `com.apple.security.network.client` — reach the network

No files, no camera, no contacts, no inbound network server. If one more ever appears, it shows
up in the diff.

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

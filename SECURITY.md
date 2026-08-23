# Security

## What this app handles

A Sentry API token with read scopes, and the issue titles that token returns. Error titles often
carry internal URLs, identifiers and fragments of business data.

## How it is stored

| Data | Where | Detail |
|---|---|---|
| Access and refresh tokens | macOS Keychain | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, not synchronized, never in a restored backup |
| Organization, server, interval, OAuth client id, project, environment | `UserDefaults` | None of these are secrets |
| Issues, releases, uptime, transactions | Memory only | `URLSessionConfiguration.ephemeral`: no disk cache, no cookies |

Nothing Sentry returns is written to disk.

### The signing certificate is part of this, not a build detail

The Keychain used to ask for a password on every update. That is not a bug to work around, it is
what an ad-hoc signature means: the app's designated requirement is literally its code hash.

```
ad-hoc:        designated => cdhash H"3b064b3123e1a5c873af1568fccbd8e7f31aa0ab"
certificate:   designated => identifier "cl.bioalergia.centinela" and certificate root = H"303ec746…"
```

Every build changes the hash, so each update was, to the Keychain, a different application asking
for someone else's item. Measured, same read, same item:

| | First access after a rebuild | Steady state | Dialog |
|---|---|---|---|
| Ad-hoc | 7709 ms | 5317 ms | yes, every update |
| Self-signed certificate | 4701 ms (one-time validation) | 18 ms | **none** |

Three documented alternatives were tried first and none works without a stable identity: the data
protection keychain (`kSecUseDataProtectionKeychain`, which Apple "highly recommends") returns
`errSecMissingEntitlement` because it needs a team identifier; `SecAccessCreate` with `nil` trusts
"only the calling app", which is the app that stops existing at the next build; and
`security add-generic-password -A` did not remove the delay.

Releases are signed with the same certificate, and the release workflow **fails** if the resulting
requirement is a hash. A release signed ad-hoc would put the dialog back for everyone who updates,
and nobody would connect it to a build step.

#### Creating one

```bash
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout key.pem -out cert.pem -config ext.cnf     # extendedKeyUsage = codeSigning
openssl pkcs12 -export -inkey key.pem -in cert.pem -out ident.p12 \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1   # macOS cannot read OpenSSL 3 defaults
security import ident.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign -A
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem
```

The trust is scoped to code signing with `-p codeSign`, not granted for everything. `make` picks
the identity up on its own and falls back to ad-hoc when it is absent, which builds and runs fine
and only costs the Keychain prompt.

**What it does not buy.** It is not a Developer ID: there is no team identifier, so Gatekeeper
still asks for right-click-to-open on a downloaded copy, notarization is still impossible, and
`com.apple.security.cs.disable-library-validation` is still required for Sparkle. Measured: with
both the app and Sparkle signed by this certificate, dyld still refuses with "mapping process and
mapped file (non-platform) have different Team IDs", because library validation wants a real team
and a self-signed certificate has none.

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

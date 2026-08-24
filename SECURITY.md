# Security

## What this app handles

A Sentry API token with read scopes, and the issue titles that token returns. Error titles often carry internal URLs, identifiers and fragments of business data.

## How it is stored

| Data | Where | Detail |
|---|---|---|
| Access and refresh tokens | macOS Keychain | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, not synchronized, never in a restored backup |
| Organization, server, interval, OAuth client id, project, environment | `UserDefaults` | None of these are secrets |
| Issues, releases, uptime, transactions | Memory only | `URLSessionConfiguration.ephemeral`: no disk cache, no cookies |

Nothing Sentry returns is written to disk.

### The signing certificate is part of this, not a build detail

The Keychain used to ask for a password on every update. That is not a bug to work around, it is what an ad-hoc signature means: the app's designated requirement is literally its code hash.

```
ad-hoc:        designated => cdhash H"3b064b3123e1a5c873af1568fccbd8e7f31aa0ab"
certificate:   designated => identifier "cl.bioalergia.centinela" and certificate root = H"303ec746…"
```

Every build changes the hash, so each update was, to the Keychain, a different application asking for someone else's item. Measured, same read, same item:

| | First access after a rebuild | Steady state |
|---|---|---|
| Ad-hoc | 7709 ms | 5317 ms |
| Self-signed certificate | 4701 ms (one-time validation) | 18 ms |

**The dialog does not go away, and an earlier version of this file said it did.** That row read "none" and it was wrong. The certificate fixes one of two independent checks. `securityd` names the other one on a real update, same install path, both builds signed with the certificate:

```
ACL partition mismatch: client cdhash:553e48cc9fc7585d64db3c54586cbb88a52205fd
displaying keychain prompt for /Applications/Centinela.app
```

A keychain item carries a **partition list** alongside its access control list, and for an application with no team identifier the only partition ID available is its code hash. The certificate makes the designated requirement stable; nothing makes the partition stable without a team identifier, so every build is a different partition and the prompt comes back. Answering "Always Allow" adds that build's hash to the list, which is why it asks once per update rather than once ever.

**What was tried instead, and measured.** None of it works, and one is worse than doing nothing:

| Attempt | Result |
|---|---|
| Same install path across builds | Still prompts. The path is not what is checked |
| Item written with an empty trusted-application list (`SecAccessCreate(name, [], …)`) | Prompts **even for the binary that wrote it**: 5646 ms against 10 ms for an ordinary item. An empty list means "ask", not "allow anyone" |
| Data protection keychain | `errSecMissingEntitlement`. `keychain-access-groups` needs a team identifier |
| Reading with an unrelated process (`/usr/bin/security`) | Prompts too, so the item is genuinely bound to a signature and not readable by anything running as the user |

Every combination reachable without a team identifier prompts once the code hash changes.

**What would actually end it.** The partition IDs are `teamid:<id>`, `cdhash:<hash>` and `apple:`; the first admits any build carrying that team identifier, the second exactly one build, the third only software signed by Apple. So the only stable partition for an application that is not Apple's is `teamid:`, which needs Apple Developer Program membership — the same thing already missing for Gatekeeper and notarization further down. Changing a partition list requires the keychain password, so the app cannot repair its own, and neither can the updater.

**How the wrong row got measured**, because the shape of the mistake is worth more than the correction: the two binaries under test lived at different paths. The ACL subject stores the path next to the requirement, so the probe was never a model of an update, where the path never changes. Re-run today, the same two binaries prompt. The generalisable rule is to print the value that is supposed to differ, assert it differs, and check that everything else does not.

Three documented alternatives were tried first and none works without a stable identity: the data protection keychain (`kSecUseDataProtectionKeychain`, which Apple "highly recommends") returns `errSecMissingEntitlement` because it needs a team identifier; `SecAccessCreate` with `nil` trusts "only the calling app", which is the app that stops existing at the next build; and `security add-generic-password -A` did not remove the delay.

Releases are signed with the same certificate, and the release workflow **fails** if the resulting requirement is a hash. That guard stays: a hash-based requirement is a second, worse failure on top of the partition one, and nobody would connect it to a build step.

#### Creating one

```bash
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout key.pem -out cert.pem -config ext.cnf     # extendedKeyUsage = codeSigning
openssl pkcs12 -export -inkey key.pem -in cert.pem -out ident.p12 \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1   # macOS cannot read OpenSSL 3 defaults
security import ident.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign -A
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem
```

The trust is scoped to code signing with `-p codeSign`, not granted for everything. `make` picks the identity up on its own and falls back to ad-hoc when it is absent, which builds and runs fine and only costs the Keychain prompt.

**What it does not buy.** It is not a Developer ID: there is no team identifier, so Gatekeeper still refuses the app, and since macOS 15 the way past it is System Settings → Privacy & Security → Open Anyway rather than Control-click → Open on a downloaded copy, notarization is still impossible, and `com.apple.security.cs.disable-library-validation` is still required for Sparkle. Measured: with both the app and Sparkle signed by this certificate, dyld still refuses with "mapping process and mapped file (non-platform) have different Team IDs", because library validation wants a real team and a self-signed certificate has none.

### What the two update entitlements cost

Two entitlements that would not otherwise be here:

| Entitlement | Why | What it gives up |
|---|---|---|
| `com.apple.security.temporary-exception.mach-lookup.global-name` (`-spks`, `-spki`) | A sandboxed app cannot replace itself, so Sparkle installs from `Installer.xpc` and has to look it up by name | Little: it can talk to two named services, both shipped inside the bundle |
| `com.apple.security.cs.disable-library-validation` | Without it dyld refuses to load Sparkle: the hardened runtime requires every loaded library to share the app's Team ID, and two ad-hoc signatures count as different teams. The measured error is `mapping process and mapped file (non-platform) have different Team IDs` | Real: any code-signed library placed in the bundle can be loaded into the process |

That second one is the honest cost. It is worth weighing against what it protects:

**An earlier version of this section said the token was already readable by any process running as you, and that was wrong.** Measured on a throwaway item created by a signed build: `/usr/bin/security` reading it prompts for the login password, and `securityd` logs `displaying keychain prompt for /usr/bin/security`. The item **is** bound to a signature, so the Keychain does buy per-application isolation on top of storage that is not a plaintext file and that needs the machine unlocked.

Which makes the entitlement cost more than that older paragraph claimed, not less. Library validation is what stops a code-signed library from being loaded into this process, and code running inside the process is precisely the identity the Keychain lets through without asking. Placing such a library still requires write access to the bundle in `/Applications`, which is to say another process running as you — so the entitlement does not create the exposure on its own, it removes the last obstacle for something that already has a foothold. A Developer ID (99 USD a year) removes the need for the entitlement entirely; until then this is the trade, written down rather than buried, and now written down correctly.

## What the app asks the system for

Sandbox on. Two permissions, and they can be read end to end in `Centinela.entitlements`:

| Entitlement | Why |
|---|---|
| `com.apple.security.app-sandbox` | |
| `com.apple.security.network.client` | Reach Sentry |
| `com.apple.security.temporary-exception.mach-lookup.global-name` | A sandboxed app cannot replace itself; Sparkle installs updates from `Installer.xpc` and looks it up by name. Both services ship inside the bundle |
| `com.apple.security.cs.disable-library-validation` | Without it dyld refuses to load Sparkle: the hardened runtime wants every loaded library to share the app's Team ID, and two ad-hoc signatures count as different teams |

No files, no camera, no contacts, no inbound network server. If one more ever appears, it shows up in the diff.

The last one is the only entitlement here that gives something up: any code-signed library placed inside the bundle can be loaded into the process. It buys automatic updates without a 99-USD-a-year Developer ID. Given that the token is already readable by any process running as you (above), it does not meaningfully change the token's exposure, but it does widen code injection in general. With a Developer ID the entitlement is unnecessary and should be removed.

`keychain-access-groups` is deliberately not declared: `$(AppIdentifierPrefix)` only expands with a provisioning profile and these builds are signed ad-hoc. Without the key, the default group is the app's own identifier, which is what is wanted. Verified by running a sandboxed, ad-hoc-signed bundle: `SecItemAdd` returns 0 and the value reads back.

## The token you give it

Signing in through the device flow requests `org:read`, `project:read` and `event:read`, and nothing else. A test fails if a write scope is ever added.

Centinela checks whether the token can read the organization's `/audit-logs/`. If it can, it carries write access and the panel says so. **Do not reuse `sentry-cli`'s token**: that one uploads sourcemaps and publishes releases.

## Reporting a problem

Open an issue in the repository. If the finding exposes data, write to the address on the author's GitHub profile instead of opening it in public.

## What this project does not promise

- Published builds are signed ad-hoc and not notarized. Check what you downloaded with `codesign -dv --verbose=4` and `spctl -a -t exec -vvv` before opening it.
- There are no automatic updates. Nothing is downloaded or executed on its own.

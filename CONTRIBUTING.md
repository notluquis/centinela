# Contributing

The rules that matter are in [AGENTS.md](AGENTS.md), and they apply to people as much as to the agents the file is named after. Each one names something that already went wrong here. This page is the short version plus the mechanics.

## Before writing anything

**Centinela only reads Sentry, and that is not negotiable.** No resolving, no assigning, no muting, no publishing releases — the code must not exist, not even disabled and not behind a flag. The property being protected is that the token *can* be read-only; the moment there is a write path, whoever runs this needs a more powerful token and the guarantee is empty.

**No real data in the repository.** Fixtures are invented and stay that way. Real responses carry error titles with internal URLs and, often, customer names, and this repository is public. A CI job fails if something shaped like a Sentry token, or a real organization name, reaches the fixtures. Both guards were probed by injecting the violation rather than by watching them pass.

**A measured number or none at all.** The documentation states API timings, sizes and memory. If you change one, run it. If you add one, measure it. A number copied out of Sentry's documentation is not a measured number, and a number written without a date rots: three of them in this repository had drifted by a factor of two before anybody looked.

**English.** Interface, source, comments, documentation, commit messages, and the repository's own description. This is public.

## The loop

```bash
make build     # no errors and no warnings
make test      # the whole suite
make lint      # swiftlint --strict
make app       # the bundle assembles and the signature verifies
```

Run `make lint` on its own and read what it prints. `make lint | tail -1 && echo ok` reports ok whatever lint did, because a pipeline's exit status is its last command's — that mistake put this repository's CI in the red for two pushes while `make lint` was reporting the violation correctly the whole time.

**Xcode is not required.** [swiftly](https://www.swift.org/install/macos/swiftly/) is enough, and the CI job that proves it stays green is the reason that claim can be made. The Command Line Tools alone are *not* enough and the error does not say so; [docs/notes.md](docs/notes.md#building-without-xcode) has that one and two other toolchain traps that each cost an afternoon.

## Guards

If you add one, **break it once and watch it go red**. A guard that cannot fail prints exactly the same thing as one that protects, and this repository has shipped both kinds. The two most recent examples are in the history: a test for a Keychain ordering that passed just as happily with the ordering reversed, and a lint check that could not report failure.

If a fix is untestable as written, that is a finding rather than an excuse — the seam usually wants to exist anyway.

## Changelog

`CHANGELOG.md` is hand-written and stays that way. The release workflow reads the section for the tag being published and refuses to publish without one.

Every version opens with **one line** between its heading and the first `###`. That line is what the in-app update dialog shows first; the detail follows underneath. A section that starts straight into `### Fixed` puts the reader in the middle of a wall, and the workflow warns when one does.

Entries say *why* a change matters. The list of what changed is generated from pull requests and appended automatically; a subject line cannot explain that a token was over-privileged or that a poll was waiting seven days for a network that was not there.

## Pull requests

There is a [template](.github/PULL_REQUEST_TEMPLATE.md). Fill in what was verified, and say what you left out — silence there reads as "nothing", which is rarely true.

Label the PR so the generated notes categorise it: `bug`, `fix`, `feature`, `enhancement`, `security`, `breaking`, `documentation`, or `no-notes` to keep it out.

## What is deliberately absent

[README.md](README.md) has the list, with a reason for each: desktop notifications, storing issues on disk, more than one organization, a global keyboard shortcut. An issue proposing one of those is welcome; it just starts from the reason rather than from zero.

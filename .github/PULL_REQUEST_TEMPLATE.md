<!--
`PULL_REQUEST_TEMPLATE.md` in `.github/` is one of the three paths GitHub actually reads. A file
named PULL_REQUEST.md is not, which is worth knowing because a well-known macOS project has one.
-->

## What changed, and why it matters

<!-- The why. A list of what moved is already in the diff. -->

## How it was verified

<!--
This repository asks for a measured number or none at all, so: what did you run, and what did it
say? If you added a guard, break it once and say that it went red — a guard that cannot fail
prints exactly what one that protects prints.
-->

- [ ] `make build` — no errors, no warnings
- [ ] `make test`
- [ ] `make lint` — run on its own and read it; `make lint | tail -1 && echo ok` says ok whatever lint did
- [ ] `make app` — the bundle assembles and the signature verifies

## Anything left out

<!-- Scope you decided against, and why. Silence here reads as "nothing", which is rarely true. -->

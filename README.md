# valkey-apt

Debian/Ubuntu packaging for [Valkey](https://github.com/valkey-io/valkey) that
tracks **several major.minor release lines in parallel** (e.g. 8.0.x, 8.1.x,
9.0.x, 9.1.x) in the same APT repository, so you can pick and upgrade within a
specific line via standard APT pinning instead of always getting whatever the
maintainers built most recently.

This is a rewrite of the single-version [greenSec `valkey-debian`
project](https://github.com/greensec/valkey-debian) it is derived from - see
"Design background" below for why a rewrite was necessary rather than an
incremental change.

## Repository information

Pre-built packages: `https://CHANGEME.github.io/valkey-apt/` (placeholder
until this project has a real publishing location - see "Open items").

## Supported Debian/Ubuntu versions

- Debian: `bookworm` (12), `trixie` (13)
- Ubuntu: `jammy` (22.04 LTS), `noble` (24.04 LTS), `resolute` (26.04 LTS)

Source of truth: [`.github/supported-releases.txt`](.github/supported-releases.txt).

## Tracked Valkey lines

Source of truth: [`tracked-lines.yaml`](tracked-lines.yaml). Each entry is a
major.minor line pinned to the newest upstream patch tag for that line; when
upstream ships a new patch, the line's `tag` is bumped in place (old patch
tags are not kept around indefinitely - see "Versioning" below).

## Installing

### Automatically via script

```bash
wget -O- https://CHANGEME.github.io/valkey-apt/add-repository.sh | bash
apt-get install valkey-server
```

With no pin, apt installs the highest-sorting available version, which is
always the newest tracked line (`default:` in `tracked-lines.yaml`).

### Manually

```bash
apt-get install wget ca-certificates
wget -O /usr/share/keyrings/valkey-apt.key https://CHANGEME.github.io/valkey-apt/public.key
source /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/valkey-apt.key] https://CHANGEME.github.io/valkey-apt/repo ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/valkey-apt.list
apt-get update && apt-get install valkey-server
```

## Pinning to a specific line

List every line currently available for your distro:

```bash
apt list -a valkey-server
```

Pin to one, e.g. the `9.0` line:

```
# /etc/apt/preferences.d/valkey-apt.pref
Package: valkey-server valkey-tools valkey-sentinel
Pin: origin "CHANGEME.github.io"
Pin: version 9.0.*
Pin-Priority: 1001
```

(Priority `1001` is intentionally above 1000 so `apt_preferences(5)` will also
force a *downgrade* if a newer line is currently installed.) Then:

```bash
apt-get update
apt-get install valkey-server valkey-tools valkey-sentinel
apt-cache policy valkey-server   # confirm the pin took effect
```

`add-repository.sh --pin <line>` writes this file for you during initial
install (see the script header for the one-liner).

### Switching to a different line later

Edit the `Pin: version` glob in the same file, then:

```bash
apt-get update
apt-get install --allow-downgrades valkey-server valkey-tools valkey-sentinel
```

(`--allow-downgrades` is only needed when moving to an *older* line than what
is currently installed.)

Only one Valkey version can be installed at a time - pinning selects which
version `install`/`upgrade` resolves to, it does not let two lines run
side-by-side on the same host.

## Repository layout

```
common/           version-agnostic packaging: control, rules, install files,
                  systemd-unit generator, man pages, DEP-8 tests, ...
lines/<line>/     per-line changelog + quilt patches/ (and an optional
                  overrides/ escape hatch for anything beyond patches)
tracked-lines.yaml   which lines are tracked, at which upstream tag
bin/materialize-debian.sh   merges common/ + lines/<line>/ into a normal
                             debian/ tree at build time
bin/build-in-lxc.sh          local build helper (see below)
bin/publish-repo.sh          adds new .debs to the pool, regenerates indices,
                              enforces the multi-version retention policy
.github/workflows/           CI: build.yml, build-deb.yml, cron-check-upstream.yml
```

`debian/` itself is never committed - it's generated on demand by
`bin/materialize-debian.sh <line> <target-dir>` (also used by CI). Patches
diverge per line on purpose: a fix needed for the 9.1 line's build must never
have to be reactively reconciled against 8.1's patch set, and vice versa.

## Versioning scheme

`<upstream_version>-<debian_revision>~<codename><build_nr>`, e.g.
`9.1.0-1~bookworm1`. This sorts correctly for `apt upgrade` within a pinned
line, and `Pin: version 9.1.*` selects exactly that line as a literal prefix
match (never `9.10.x`, since the glob's 4th character `.` doesn't match a
digit). No `+dfsg1` repack suffix is used, unlike real Debian's valkey
package, since this project builds directly from upstream GitHub tags.

## How new patches/lines get added

- **Patch release on an already-tracked line** (e.g. 9.1.0 -> 9.1.1): fully
  automated. `cron-check-upstream.yml` runs daily, bumps the line's `tag` in
  `tracked-lines.yaml`, commits, and triggers `build.yml`.
- **Brand-new major.minor line** (e.g. 9.2.0 ships upstream): **not**
  auto-added. New lines have historically needed patch rework and raise
  EOL-policy questions, both of which deserve a human decision. The cron job
  files/updates a tracking issue instead; a maintainer adds the line via a
  reviewed PR (new `tracked-lines.yaml` entry + `lines/<line>/patches/`,
  seeded from the newest existing line and verified before merging).

## EOL / retirement policy

Always keep the newest minor of the current major and the newest minor of
the immediately preceding major, plus any line still receiving upstream
patches or explicitly marked `lts: true`. A line moves to `status: eol` once
upstream stops patching it and it's no longer the newest minor of its major -
CI then stops rebuilding/checking it, but its last-built `.deb` stays
published indefinitely so pinned users can still reinstall/upgrade within
that line.

## Local build/test environment (LXC/LXD)

`bin/build-in-lxc.sh <line> <codename> <arch>` builds one combination inside
a local LXD system container instead of waiting on a GitHub Actions run - a
real Debian/Ubuntu container (with systemd) is more representative than a
Docker build container when debugging the generated systemd units
(`common/bin/generate-systemd-service-files`) or the maintainer scripts.
Requires `lxd` initialized on the host and either `yq` or Python's `PyYAML`.
It is not wired into CI and was not executed as part of scaffolding this
project - see "Verification status" below.

## Verification status

1. **Line 9.1 is build/install/run verified.** `bin/build-in-lxc.sh 9.1
   trixie amd64` was run for real in a local LXD `debian/trixie` container
   on 2026-07-09: all three `.deb`s built, installed cleanly (`dpkg -i` +
   `apt-get -f install`, no dependency errors), the generated
   `valkey-server.service` started under systemd, and `valkey-cli
   ping`/`info server` confirmed a working `valkey_version:9.1.0` server.
   This exercised `common/control`, `common/rules`, all of `lines/9.1/patches`
   (applied and unapplied cleanly), the systemd-unit generator, and the
   maintainer scripts end-to-end. See `lines/9.1/patches/NOTES.md`.
2. **Patches for the 8.0, 8.1, and 9.0 lines are still unverified** - they
   were seeded as a straight copy of the (now verified) 9.1 baseline. Check
   `lines/<line>/patches/NOTES.md` in each; the jemalloc patch
   (`0004-Add-support-for-USE_SYSTEM_JEMALLOC-flag.patch`) is the most likely
   to need adjustment, since it already needed rework once between 9.0 and
   9.1 upstream. `bin/build-in-lxc.sh <line> <codename> amd64` is the fastest
   way to check each one.
3. `bin/publish-repo.sh` (the multi-version retention + index regeneration
   logic) has been dry-run tested locally against fake `.deb` files, confirming
   several lines coexist correctly per codename and that a patch bump only
   evicts the superseded build within its own (line, codename) slot. It has
   **not** been tested against a real `apt-get update`/`apt-cache policy` run
   yet - do that (ideally inside an LXD container, see above) before
   production use.
4. The GitHub Actions workflows are new and have not been run - they build
   without syntax errors (workflow YAML + embedded Python checked), but real
   execution may surface issues (e.g. GPG signing flow, matrix sizing).
5. Only `amd64` has been exercised so far (this build machine's native arch);
   `arm64` goes through a different LXD image alias
   (`bin/build-in-lxc.sh` appends `/arm64`) and has not been tried.

## Open items

- Real repo name/hosting location (`CHANGEME` placeholders throughout).
- Reuse or regenerate the APT signing key/GitHub secrets.
- Re-confirm Valkey's actual upstream support policy against the EOL rule
  above at rollout time.
- `README.md`/`add-repository.sh` list supported distros separately from
  `.github/supported-releases.txt` by design (user-facing docs shouldn't
  silently change), but keep both in sync when editing.

## Acknowledgements

Based on the work of the Valkey developers, the Debian Valkey team (Lucas
Kanashiro et al.), and greenSec GmbH's `valkey-debian` project, from which
most of the version-agnostic packaging content here was carried over.

- [Valkey official website](https://valkey.io/)
- [Valkey GitHub repository](https://github.com/valkey-io/valkey)

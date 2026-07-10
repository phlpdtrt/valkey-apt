# valkey-apt

Debian/Ubuntu packaging for [Valkey](https://github.com/valkey-io/valkey) that
tracks **several major.minor release lines in parallel** (e.g. 8.0.x, 8.1.x,
9.0.x, 9.1.x) in the same APT repository, so you can pick and upgrade within a
specific line via standard APT pinning instead of always getting whatever the
maintainers built most recently. Every Valkey release that ever gets built
here stays published and installable indefinitely (not just the newest patch
per line) - see "Versioning scheme" and "Retention policy" below.

This is a rewrite of the single-version [greenSec `valkey-debian`
project](https://github.com/greensec/valkey-debian) it is derived from - see
"Design background" below for why a rewrite was necessary rather than an
incremental change.

## Repository information

Source: [github.com/phlpdtrt/valkey-apt](https://github.com/phlpdtrt/valkey-apt)

Pre-built packages: `https://phlpdtrt.github.io/valkey-apt/` (served from
the `gh-pages` branch - live).

## Supported Debian/Ubuntu versions

- Debian: `bookworm` (12), `trixie` (13)
- Ubuntu: `jammy` (22.04 LTS), `noble` (24.04 LTS), `resolute` (26.04 LTS)

Source of truth: [`.github/supported-releases.txt`](.github/supported-releases.txt).

## Tracked Valkey lines

Source of truth: [`tracked-lines.yaml`](tracked-lines.yaml). Each entry
records the newest upstream patch tag known for that line, used to detect
and build new patch releases (see "How new patches/lines get added"). It
does **not** control what stays published - every patch ever built is kept
forever (see "Retention policy").

## Installing

### Automatically via script

```bash
wget -O- https://phlpdtrt.github.io/valkey-apt/add-repository.sh | bash
apt-get install valkey-server
```

With no pin, apt installs the highest-sorting available version, which is
always the newest tracked line (`default:` in `tracked-lines.yaml`).

### Manually

```bash
apt-get install wget ca-certificates
wget -O /usr/share/keyrings/valkey-apt.key https://phlpdtrt.github.io/valkey-apt/public.key
source /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/valkey-apt.key] https://phlpdtrt.github.io/valkey-apt ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/valkey-apt.list
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
Pin: origin "phlpdtrt.github.io"
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

Since every patch ever built stays published (see "Retention policy"), you
can also pin to one *exact* version instead of a whole line, e.g.
`Pin: version 8.1.8-1*` - useful if you specifically don't want to move
past a known-good patch even within its own line.

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
bin/publish-repo.sh          adds new .debs to the pool, regenerates indices;
                              never removes anything (see "Retention policy")
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

## Retention policy

Every `(package, version, codename, arch)` combination ever published stays
in the pool and in the `Packages` index forever - `bin/publish-repo.sh` only
ever adds, it never deletes based on version. Concretely: when 8.1.9 ships,
8.1.8 is **not** removed; both remain installable/pinnable
(`Pin: version 8.1.8-1*` still works after 8.1.9 exists). The only way a
version disappears is a deliberate manual step (see the script header) -
e.g. if upstream retracts a release for some reason. This does mean the pool
and the `gh-pages` branch only ever grow; there is currently no pruning, by
design.

## EOL / retirement policy

`status: eol` in `tracked-lines.yaml` only controls whether
`cron-check-upstream.yml`/`build.yml` keep checking and building **new**
patches for that line - it has no effect on what's already published (see
"Retention policy" above; nothing is ever removed either way). Suggested
default: mark a line `eol` once upstream stops patching it and it's no
longer the newest minor of its major, keeping always the newest minor of
the current major and of the immediately preceding major as a floor, plus
any line explicitly marked `lts: true`.

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

1. **Fully live and working end-to-end as of 2026-07-10.** `build.yml` has
   run for real for all four lines (8.0, 8.1, 9.0, 9.1) across all five
   codenames and both arches (120 `.deb`s), and `publish-repo.sh` published
   them to the real `gh-pages` branch with a real GPG-signed `Release`.
   `apt-get update`/`apt-cache policy` against the live repo confirms all
   four lines show up as separate candidate versions. `add-repository.sh`
   works end-to-end via `wget | bash`.
2. Line 9.1 was additionally build/install/run tested inside a local LXD
   container before the first real CI run: package installed cleanly,
   `valkey-server.service` started under systemd, `valkey-cli ping` ->
   `PONG`. 8.0/8.1/9.0 have only been verified by the real CI build (not
   separately install/run tested locally) - see each
   `lines/<line>/patches/NOTES.md`.
3. Real bugs found and fixed via actual CI runs (not caught by earlier local
   testing, which used absolute paths / didn't hit these specific edge
   cases): a `dch` fatal error from the `~<codename>` versioning scheme
   (needed `dch -b`), a doubled path in `publish-repo.sh` when invoked with
   a relative `repo-dir` (CI does; earlier local tests used absolute paths),
   and a leftover `/repo` path segment in the `sources.list` URL inherited
   from the old greenSec project's different layout.

## Open items

- Re-confirm Valkey's actual upstream support policy against the EOL rule
  in "EOL / retirement policy" at rollout time.
- `README.md`/`add-repository.sh` list supported distros separately from
  `.github/supported-releases.txt` by design (user-facing docs shouldn't
  silently change), but keep both in sync when editing.
- No pruning exists for the ever-growing pool/`gh-pages` history (see
  "Retention policy") - fine at current scale, revisit if repo size becomes
  a problem.

## Acknowledgements

Based on the work of the Valkey developers, the Debian Valkey team (Lucas
Kanashiro et al.), and greenSec GmbH's `valkey-debian` project, from which
most of the version-agnostic packaging content here was carried over.

- [Valkey official website](https://valkey.io/)
- [Valkey GitHub repository](https://github.com/valkey-io/valkey)

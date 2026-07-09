Status: UNVERIFIED — copied from the 9.1 baseline as a starting point.

Before the first real build for this line, run `bin/materialize-debian.sh 8.0`
against an actual `valkey` checkout at tag `8.0.9` (or whatever
`tracked-lines.yaml` currently pins) and confirm `quilt push -a` applies all
patches cleanly. `0004-Add-support-for-USE_SYSTEM_JEMALLOC-flag.patch` is the
most likely to need adjustment. Update or drop patches here as needed, then
delete this note.

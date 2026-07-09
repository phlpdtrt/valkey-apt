Status: UNVERIFIED — copied from the 9.1 baseline as a starting point.

Before the first real build for this line, run `bin/materialize-debian.sh 9.0`
against an actual `valkey` checkout at tag `9.0.4` (or whatever
`tracked-lines.yaml` currently pins) and confirm `quilt push -a` applies all
patches cleanly. `0004-Add-support-for-USE_SYSTEM_JEMALLOC-flag.patch` is the
most likely to need adjustment, since it has already needed rework once
between 9.0 and 9.1 upstream. Update or drop patches here as needed, then
delete this note.

Status: verified baseline - build/install/run tested.

This patch set is the one last known to apply cleanly to a valkey 9.1.0
checkout (carried over from the greenSec `valkey-debian` repo's history,
commit "Update patches for valkey 9.1.0 compatibility" + the follow-up
jemalloc mapping fix).

2026-07-09: built end-to-end in a local LXD `debian/trixie` container via
`bin/build-in-lxc.sh 9.1 trixie amd64` - all three .debs built, installed
cleanly (`dpkg -i` + `apt-get -f install`, no dependency errors), the
generated `valkey-server.service` started successfully under systemd, and
`valkey-cli ping`/`info server` confirmed a working `valkey_version:9.1.0`
server. No further action needed until 9.1 gets a new patch tag upstream.

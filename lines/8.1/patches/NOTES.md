Status: verified against a fresh 8.1.8 checkout (2026-07-10).

Needed rework beyond 9.0/9.1 in two spots: `deps/Makefile`'s dep name is
`hiredis` (pre-libvalkey-rename) and its `distclean` list has no
`fast_float_c_interface` entry; `src/Makefile`'s malloc-selection block is
followed by a `# LIBSSL & LIBCRYPTO` section instead of `USE_LTTNG`, and its
`SERVER_CC` line has no trailing `-I.`. Verified with `patch -p1 -F0 -t` for
every hunk against a fresh `git clone --branch 8.1.8`, matching exactly the
flags `dpkg-source` uses. No further action needed until 8.1 gets a new
patch tag upstream.

Status: verified against a fresh 9.0.4 checkout (2026-07-10).

Diverged from the 9.1 baseline in `deps/Makefile`'s `distclean` target (an
extra `fast_float_c_interface` clean line breaks the naive context match)
and required the same jemalloc-guard rework as 9.1's own patch history.
Verified with `patch -p1 -F0 -t` for every hunk in this series against a
fresh `git clone --branch 9.0.4`, matching exactly the flags `dpkg-source`
uses. No further action needed until 9.0 gets a new patch tag upstream.

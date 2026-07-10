Status: verified against a fresh 8.0.9 checkout (2026-07-10).

Needed the most rework of any tracked line so far - 8.0 predates several
refactors present by 9.1:
- `debian-packaging/0001`: `valkey.conf`'s `dir` directive comment text
  differs ("Note that you must specify a directory here..." instead of the
  "modifying 'dir' during runtime..." comment used from 9.x onward).
- `deps/Makefile`: dep is named `hiredis` (pre-libvalkey-rename), no
  `fast_float_c_interface` clean entry.
- `src/Makefile`: malloc-selection block followed by `# LIBSSL & LIBCRYPTO`
  instead of `USE_LTTNG`; `SERVER_CC` has no trailing `-I.`.
- `src/object.c`: no `KEY_SIZE_TO_INCLUDE_EXPIRE_THRESHOLD` yet - the
  USE_SYSTEM_JEMALLOC block is anchored before the "Creation and parsing of
  objects" comment instead.
- `src/sds.c`: `sdsHdrSize` is declared `static inline` (trailing context
  differs).
- `src/zmalloc.c`: the jemalloc override block additionally defines
  `mallocx`/`dallocx` (kept as-is in the bundled/else branch; not needed in
  the USE_SYSTEM_JEMALLOC branch since the system library already exports
  them unprefixed and the call sites use the plain names directly).

Verified with `patch -p1 -F0 -t` for every hunk against a fresh
`git clone --branch 8.0.9`, matching exactly the flags `dpkg-source` uses.
No further action needed until 8.0 gets a new patch tag upstream.

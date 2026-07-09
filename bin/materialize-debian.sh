#!/bin/sh
# Merge common/ (version-agnostic packaging) with lines/<line>/ (patches,
# changelog, and optional per-line overrides) into an ordinary debian/ tree.
#
# Usage: bin/materialize-debian.sh <line> <target-dir>
#
#   <line>        a key from tracked-lines.yaml, e.g. "9.1"
#   <target-dir>  root of a checked-out valkey source tree (the one that will
#                 be handed to dpkg-buildpackage) - a debian/ subdirectory is
#                 created/overwritten inside it.
#
# The result is a byte-for-byte normal debian/ directory; dh/quilt/debhelper
# need no awareness that an overlay ever existed.

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINE="${1:-}"
TARGET="${2:-}"

if [ -z "$LINE" ] || [ -z "$TARGET" ]; then
    echo "Usage: $0 <line> <target-dir>" >&2
    exit 1
fi

COMMON="$REPO_ROOT/common"
LINE_DIR="$REPO_ROOT/lines/$LINE"

if [ ! -d "$LINE_DIR" ]; then
    echo "Unknown line '$LINE': no directory at $LINE_DIR" >&2
    echo "Known lines:" >&2
    find "$REPO_ROOT/lines" -mindepth 1 -maxdepth 1 -type d -printf '  %f\n' >&2
    exit 1
fi

if [ ! -d "$TARGET" ]; then
    echo "Target directory does not exist: $TARGET" >&2
    exit 1
fi

DEBIAN_DIR="$TARGET/debian"
rm -rf "$DEBIAN_DIR"
mkdir -p "$DEBIAN_DIR"

echo "Materializing debian/ for line $LINE into $DEBIAN_DIR"

# 1. Shared, version-agnostic base.
cp -a "$COMMON"/. "$DEBIAN_DIR"/

# 2. Line-specific changelog (becomes debian/changelog).
if [ ! -f "$LINE_DIR/changelog" ]; then
    echo "Missing $LINE_DIR/changelog" >&2
    exit 1
fi
cp "$LINE_DIR/changelog" "$DEBIAN_DIR/changelog"

# 3. Line-specific patch series (replaces the placeholder from common/, if any).
rm -rf "$DEBIAN_DIR/patches"
if [ ! -d "$LINE_DIR/patches" ]; then
    echo "Missing $LINE_DIR/patches" >&2
    exit 1
fi
cp -a "$LINE_DIR/patches" "$DEBIAN_DIR/patches"
# NOTES.md is documentation for maintainers, not packaging input - drop it so
# it never ends up inside the actual quilt patches directory used by dpkg.
rm -f "$DEBIAN_DIR/patches/NOTES.md"

# 4. Optional escape hatch: a line that needs to diverge on something other
#    than patches/changelog (new binary package, changed Build-Depends, ...)
#    can drop same-named files under lines/<line>/overrides/ to overlay them
#    on top of common/ after step 1.
if [ -d "$LINE_DIR/overrides" ]; then
    echo "Applying overrides from $LINE_DIR/overrides"
    cp -a "$LINE_DIR/overrides"/. "$DEBIAN_DIR"/
fi

echo "Done: $DEBIAN_DIR"

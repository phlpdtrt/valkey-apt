#!/bin/sh
# Build one (line, codename, arch) combination locally inside an LXD
# container, as a fast local alternative to waiting on a GitHub Actions run.
# This mirrors what build.yml does inside Docker via jtdor/build-deb-action,
# but in a real Debian/Ubuntu system container (systemd included), which is
# more representative when debugging the generated systemd units or the
# postinst/postrm maintainer scripts.
#
# NOT wired into CI. Intended for local development/debugging only. This
# script is not executed as part of scaffolding the project - see README.md
# "Local build/test environment (LXC/LXD)".
#
# Usage: bin/build-in-lxc.sh <line> <codename> <arch> [--keep]
#
#   <line>      key from tracked-lines.yaml, e.g. "9.1"
#   <codename>  a codename from .github/supported-releases.txt, e.g. "bookworm"
#   <arch>      "amd64" or "arm64"
#   --keep      don't delete the container after the build (default: delete)
#
# Requires: lxd/lxc set up and initialized on the host (`lxd init`), the
# `images:` remote available, and `yq` (https://github.com/mikefarah/yq) or
# `python3` with PyYAML for reading tracked-lines.yaml.
#
# Output: the built .deb files are copied to ./out/<line>/<codename>/<arch>/

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINE="${1:-}"
CODENAME="${2:-}"
ARCH="${3:-}"
KEEP="${4:-}"

if [ -z "$LINE" ] || [ -z "$CODENAME" ] || [ -z "$ARCH" ]; then
    echo "Usage: $0 <line> <codename> <arch> [--keep]" >&2
    exit 1
fi

command -v lxc >/dev/null 2>&1 || { echo "lxc (LXD client) not found in PATH" >&2; exit 1; }

read_tag() {
    if command -v yq >/dev/null 2>&1; then
        yq -r ".lines.\"$LINE\".tag" "$REPO_ROOT/tracked-lines.yaml"
    else
        python3 - "$REPO_ROOT/tracked-lines.yaml" "$LINE" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1]))
print(data["lines"][sys.argv[2]]["tag"])
PY
    fi
}

TAG="$(read_tag)"
if [ -z "$TAG" ] || [ "$TAG" = "null" ]; then
    echo "Could not resolve tag for line '$LINE' from tracked-lines.yaml" >&2
    exit 1
fi

# Map our (distro:codename) naming to an LXD/simplestreams image alias.
case "$CODENAME" in
    bullseye|bookworm|trixie) IMAGE="images:debian/$CODENAME" ;;
    jammy|noble)               IMAGE="images:ubuntu/$CODENAME" ;;
    *) echo "Unknown codename: $CODENAME (check .github/supported-releases.txt)" >&2; exit 1 ;;
esac

CONTAINER="build-${LINE}-${CODENAME}-${ARCH}"
OUT_DIR="$REPO_ROOT/out/$LINE/$CODENAME/$ARCH"
mkdir -p "$OUT_DIR"

echo "==> Launching $CONTAINER from $IMAGE (arch: $ARCH)"
lxc launch "$IMAGE" "$CONTAINER" ${ARCH:+-c "image.architecture=$ARCH"}

cleanup() {
    if [ "$KEEP" != "--keep" ]; then
        echo "==> Deleting $CONTAINER"
        lxc delete --force "$CONTAINER" >/dev/null 2>&1 || true
    else
        echo "==> Keeping $CONTAINER (--keep passed)"
    fi
}
trap cleanup EXIT

echo "==> Waiting for network in $CONTAINER"
for _ in $(seq 1 30); do
    lxc exec "$CONTAINER" -- true >/dev/null 2>&1 && break
    sleep 1
done

echo "==> Installing build dependencies"
lxc exec "$CONTAINER" -- sh -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get -q update
    apt-get -y --no-install-recommends install \
        build-essential devscripts equivs quilt git ca-certificates \
        libhiredis-dev libjemalloc-dev liblua5.1-dev liblzf-dev libssl-dev \
        libsystemd-dev lua-bitop-dev lua-cjson-dev openssl pkgconf procps \
        tcl tcl-tls dpkg-dev
'

echo "==> Fetching valkey $TAG into the container"
lxc exec "$CONTAINER" -- sh -c "
    git clone --depth 1 --branch '$TAG' --recurse-submodules \
        https://github.com/valkey-io/valkey.git /root/valkey
"

echo "==> Materializing debian/ for line $LINE on the host, then pushing it in"
WORK="$(mktemp -d)"
mkdir -p "$WORK/debian-src"
"$REPO_ROOT/bin/materialize-debian.sh" "$LINE" "$WORK/debian-src"
lxc file push -r "$WORK/debian-src/debian" "$CONTAINER/root/valkey/"
rm -rf "$WORK"

echo "==> Running dpkg-buildpackage in $CONTAINER"
lxc exec "$CONTAINER" -- sh -c '
    cd /root/valkey
    DEB_BUILD_OPTIONS=noautodbgsym dpkg-buildpackage --build=binary --no-sign -d
'

echo "==> Collecting .deb artifacts into $OUT_DIR"
lxc file pull "$CONTAINER/root/"*.deb "$OUT_DIR/" 2>/dev/null || \
    echo "No .deb files found directly under /root - check dpkg-buildpackage output above"

echo "==> Done. Artifacts (if any): $OUT_DIR"

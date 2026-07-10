#!/bin/bash
# Add freshly built .deb files to the flat APT pool and regenerate the
# per-codename indices, retaining exactly one .deb per (package, line,
# codename, arch) - i.e. multiple Valkey lines coexist in the same Packages
# file, superseded only within their own line. This is the hand-rolled
# retention mechanism from the design doc (deliberately not reprepro/aptly,
# both of which default to "one version per slot" semantics that fight this
# requirement).
#
# This is new, not-yet-battle-tested code (flagged as the top residual risk
# in the project plan) - verify with a real `apt update` against the output
# before relying on it in production. Not invoked by any workflow yet.
#
# Usage: bin/publish-repo.sh <repo-dir> <incoming-dir> [--gpg-key <keyid>]
#
#   <repo-dir>      root of the published APT tree (e.g. a checked-out
#                   gh-pages worktree). Created if it doesn't exist yet.
#   <incoming-dir>  directory containing newly built *.deb files to ingest,
#                   e.g. the merged GitHub Actions artifact download.
#   --gpg-key       key id to sign Release with (skipped if omitted, e.g. for
#                   local dry runs - resulting repo will be unsigned).
#
# Layout produced under <repo-dir>:
#   pool/main/v/valkey/<pkg>_<version>_<arch>.deb   (shared across codenames)
#   dists/<codename>/Release[.gpg] / InRelease
#   dists/<codename>/main/binary-<arch>/Packages[.gz]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="${1:?repo-dir required}"
INCOMING_DIR="${2:?incoming-dir required}"
GPG_KEY=""
if [ "${3:-}" = "--gpg-key" ]; then
    GPG_KEY="${4:?--gpg-key needs a key id}"
fi

for tool in dpkg-deb dpkg-scanpackages apt-ftparchive python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Missing required tool: $tool" >&2; exit 1; }
done

# Normalize to an absolute path: several steps below `cd` into $REPO_DIR
# inside a subshell, and any path derived from a *relative* $REPO_DIR (like
# $bin_dir) would then resolve against the wrong (already-inside) cwd,
# doubling the prefix (e.g. "repo/repo/dists/..."). Absolute paths are
# immune to that regardless of which directory a subshell cd's into.
mkdir -p "$REPO_DIR"
REPO_DIR="$(cd "$REPO_DIR" && pwd)"

mkdir -p "$REPO_DIR/pool/main/v/valkey"

CODENAMES=$(grep -E '^[a-z]+:[a-z0-9]+$' "$REPO_ROOT/.github/supported-releases.txt" | cut -d: -f2)
ARCHES="amd64 arm64"

# --- helpers ---------------------------------------------------------------

# Extract the "<major>.<minor>" line id from a Debian upstream version, e.g.
# "9.1.0-1~bookworm1" -> "9.1". Assumes upstream_version is always X.Y.Z.
line_of_version() {
    echo "$1" | sed -E 's/^([0-9]+\.[0-9]+)\..*/\1/'
}

# Extract the codename embedded as a "~<codename><N>" suffix, e.g.
# "9.1.0-1~bookworm1" -> "bookworm".
codename_of_version() {
    local version="$1" cn
    for cn in $CODENAMES; do
        case "$version" in
            *"~${cn}"[0-9]*) echo "$cn"; return 0 ;;
        esac
    done
    return 1
}

# --- 1. ingest incoming .debs ----------------------------------------------

shopt -s nullglob
incoming=("$INCOMING_DIR"/*.deb)
if [ ${#incoming[@]} -eq 0 ]; then
    echo "No .deb files found in $INCOMING_DIR - nothing to ingest" >&2
else
    for deb in "${incoming[@]}"; do
        pkg=$(dpkg-deb -f "$deb" Package)
        version=$(dpkg-deb -f "$deb" Version)
        arch=$(dpkg-deb -f "$deb" Architecture)
        line=$(line_of_version "$version")
        codename=$(codename_of_version "$version") || {
            echo "Could not determine codename from version '$version' ($deb) - skipping" >&2
            continue
        }

        if ! grep -q "^  \"$line\":" "$REPO_ROOT/tracked-lines.yaml"; then
            echo "Warning: '$deb' belongs to untracked line '$line' - ingesting anyway" >&2
        fi

        dest="$REPO_DIR/pool/main/v/valkey/${pkg}_${version}_${arch}.deb"
        echo "==> Adding $dest"
        cp "$deb" "$dest"

        # Retention: remove any other .deb for the same (package, line,
        # codename, arch) that is NOT this version - it has just been
        # superseded by a new patch within the same line.
        find "$REPO_DIR/pool/main/v/valkey" -maxdepth 1 -type f \
            -name "${pkg}_*_${arch}.deb" ! -name "$(basename "$dest")" |
        while read -r old; do
            old_version=$(dpkg-deb -f "$old" Version 2>/dev/null || true)
            [ -z "$old_version" ] && continue
            old_line=$(line_of_version "$old_version")
            old_codename=$(codename_of_version "$old_version" || true)
            if [ "$old_line" = "$line" ] && [ "$old_codename" = "$codename" ]; then
                echo "==> Removing superseded $old (line $old_line, $old_codename)"
                rm -f "$old"
            fi
        done
    done
fi

# --- 2. regenerate indices per (codename, arch) -----------------------------

for codename in $CODENAMES; do
    dist_dir="$REPO_DIR/dists/$codename"
    mkdir -p "$dist_dir/main"

    for arch in $ARCHES; do
        bin_dir="$dist_dir/main/binary-$arch"
        mkdir -p "$bin_dir"

        # Only list pool debs whose embedded codename+arch match this slot.
        pkg_list="$(mktemp)"
        find "$REPO_DIR/pool/main/v/valkey" -maxdepth 1 -type f -name "*_${arch}.deb" |
        while read -r deb; do
            version=$(dpkg-deb -f "$deb" Version)
            cn=$(codename_of_version "$version" || true)
            if [ "$cn" = "$codename" ]; then
                echo "$deb"
            fi
        done > "$pkg_list"

        if [ -s "$pkg_list" ]; then
            ( cd "$REPO_DIR" && dpkg-scanpackages --arch "$arch" \
                --multiversion pool/main/v/valkey /dev/null \
                > "$bin_dir/Packages.tmp" 2>/dev/null )
            # dpkg-scanpackages already scans the whole pool; filter down to
            # just the debs relevant to this codename+arch using $pkg_list.
            python3 "$REPO_ROOT/bin/_filter-packages.py" \
                "$bin_dir/Packages.tmp" "$pkg_list" "$REPO_DIR" > "$bin_dir/Packages"
            rm -f "$bin_dir/Packages.tmp"
        else
            : > "$bin_dir/Packages"
        fi
        gzip -kf "$bin_dir/Packages"
        rm -f "$pkg_list"
    done

    echo "==> Writing Release for $codename"
    ( cd "$REPO_DIR" && apt-ftparchive \
        -o "APT::FTPArchive::Release::Codename=$codename" \
        -o "APT::FTPArchive::Release::Suite=$codename" \
        -o "APT::FTPArchive::Release::Components=main" \
        -o "APT::FTPArchive::Release::Architectures=$(echo $ARCHES)" \
        -o "APT::FTPArchive::Release::Label=valkey-apt" \
        -o "APT::FTPArchive::Release::Origin=valkey-apt" \
        release "dists/$codename" > "dists/$codename/Release" )

    if [ -n "$GPG_KEY" ]; then
        gpg --default-key "$GPG_KEY" -abs -o "$dist_dir/Release.gpg" "$dist_dir/Release"
        gpg --default-key "$GPG_KEY" -abs --clearsign -o "$dist_dir/InRelease" "$dist_dir/Release"
    else
        echo "No --gpg-key given - $codename left unsigned (fine for a local dry run only)" >&2
    fi
done

echo "==> Publish complete: $REPO_DIR"

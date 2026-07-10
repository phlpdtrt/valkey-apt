#!/bin/sh
# To add this repository please do:
#
#   wget -O- https://phlpdtrt.github.io/valkey-apt/add-repository.sh | bash
#
# Optionally pin to a specific tracked line right away:
#
#   wget -O- https://phlpdtrt.github.io/valkey-apt/add-repository.sh | bash -s -- --pin 9.0

set -eu

PIN_LINE=""
if [ "${1:-}" = "--pin" ]; then
    PIN_LINE="${2:-}"
    if [ -z "$PIN_LINE" ]; then
        echo "--pin requires a line argument, e.g. --pin 9.0"
        exit 1
    fi
fi

if [ "$(id -u)" -ne 0 ]; then
    SUDO=sudo
else
    SUDO=
fi

if [ -r /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    DISTRO_ID="${ID:-}"
    CODENAME="${VERSION_CODENAME:-}"
else
    DISTRO_ID=
    CODENAME=
fi

if [ -z "${DISTRO_ID}" ] || [ -z "${CODENAME}" ]; then
    echo "Unable to detect distro codename from /etc/os-release."
    echo "This repository supports Debian (bookworm, trixie) and Ubuntu (jammy, noble, resolute)."
    exit 1
fi

case "${DISTRO_ID}:${CODENAME}" in
    debian:bookworm|debian:trixie|ubuntu:jammy|ubuntu:noble|ubuntu:resolute)
        ;;
    *)
        echo "Unsupported distribution: ${DISTRO_ID}:${CODENAME}"
        echo "Supported releases: debian:{bookworm,trixie} ubuntu:{jammy,noble,resolute}"
        exit 1
        ;;
esac

${SUDO} apt-get update
${SUDO} apt-get -y install ca-certificates wget
${SUDO} wget -O /usr/share/keyrings/valkey-apt.key https://phlpdtrt.github.io/valkey-apt/public.key
echo "deb [signed-by=/usr/share/keyrings/valkey-apt.key] https://phlpdtrt.github.io/valkey-apt ${CODENAME} main" | ${SUDO} tee /etc/apt/sources.list.d/valkey-apt.list

if [ -n "$PIN_LINE" ]; then
    echo "Pinning valkey-server/valkey-tools/valkey-sentinel to line ${PIN_LINE}.*"
    ${SUDO} tee /etc/apt/preferences.d/valkey-apt.pref > /dev/null <<EOF
Package: valkey-server valkey-tools valkey-sentinel
Pin: origin "phlpdtrt.github.io"
Pin: version ${PIN_LINE}.*
Pin-Priority: 1001
EOF
fi

${SUDO} apt-get update

if [ -n "$PIN_LINE" ]; then
    echo "Done. Run 'apt-cache policy valkey-server' to confirm the pin, then 'apt-get install valkey-server'."
else
    echo "Done. Run 'apt list -a valkey-server' to see all available lines, then 'apt-get install valkey-server'."
    echo "See README.md for how to pin to a specific major.minor line instead of the default."
fi

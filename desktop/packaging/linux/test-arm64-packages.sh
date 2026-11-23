#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Validate native Linux ARM64 packages without the public install.sh entrypoint.
# The install.sh architecture allowlist and release integration come later (#356).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
VERSION="$(awk -F'"' '/^version[[:space:]]*=[[:space:]]*"/ { print $2; exit }' "$ROOT/Cargo.toml")"
DIST="$ROOT/dist"

[ "$(uname -m)" = aarch64 ]
[ "$(dpkg --print-architecture)" = arm64 ]

deb="$DIST/nectarlink_${VERSION}_arm64.deb"
rpm="$DIST/nectarlink-$VERSION-1.aarch64.rpm"
appimage="$DIST/Nectarlink-$VERSION-aarch64.AppImage"
tarball="$DIST/Nectarlink-$VERSION-linux-aarch64.tar.gz"

for package in "$deb" "$rpm" "$appimage" "$tarball"; do
    [ -s "$package" ] || { echo "Missing package: $package" >&2; exit 1; }
done

[ "$(dpkg-deb -f "$deb" Architecture)" = arm64 ]
[ "$(rpm -qp --qf '%{ARCH}' "$rpm")" = aarch64 ]

work="$(mktemp -d -t nectarlink-arm64-package-XXXXXX)"
trap 'rm -rf "$work"' EXIT

dpkg-deb -x "$deb" "$work/deb"
readelf -h "$work/deb/usr/lib/nectarlink/nectarlink-desktop" | grep -q 'Machine: *AArch64'
tar -xzf "$tarball" -C "$work"
bundle="$work/Nectarlink-$VERSION-linux-aarch64"
readelf -h "$bundle/nectarlink-desktop" | grep -q 'Machine: *AArch64'
readelf -h "$appimage" | grep -q 'Machine: *AArch64'
test -s "$work/deb/usr/share/nectarlink/nectarlink_pt_BR.qm"
test -s "$bundle/nectarlink_pt_BR.qm"

# Both package managers run on real ARM64 containers, not under emulation.
docker run --rm --platform linux/arm64 -v "$DIST:/dist:ro" ubuntu:24.04 sh -euc '
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends /dist/*.deb >/dev/null
    nectarlink-desktop --version
    DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq nectarlink >/dev/null
    hash -r
    ! command -v nectarlink-desktop
'
docker run --rm --platform linux/arm64 -v "$DIST:/dist:ro" fedora:40 sh -euc '
    dnf install -y -q --nogpgcheck /dist/*.rpm >/dev/null
    nectarlink-desktop --version
    dnf remove -y -q nectarlink >/dev/null
    hash -r
    ! command -v nectarlink-desktop
'

# AppImages run without FUSE inside CI. The tarball has its own standalone
# install/uninstall helper and does not depend on install.sh's allowlist.
APPIMAGE_EXTRACT_AND_RUN=1 "$appimage" --version
mkdir -p "$work/home"
HOME="$work/home" XDG_DATA_HOME="$work/data" bash "$bundle/install.sh"
HOME="$work/home" XDG_DATA_HOME="$work/data" "$work/home/.local/bin/nectarlink-desktop" --version
HOME="$work/home" XDG_DATA_HOME="$work/data" bash "$bundle/uninstall.sh"
test ! -e "$work/home/.local/bin/nectarlink-desktop"

echo "ARM64 package checks passed."

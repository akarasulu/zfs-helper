#!/usr/bin/env bash
set -euo pipefail
# Build a minimal .deb for Debian 12 (bookworm)
# Usage: make-deb.sh <version> [arch] [--dry-run]

DRY_RUN=0
POSITIONAL=()
for arg in "$@"; do
  case "${arg}" in
    --dry-run) DRY_RUN=1; shift;;
    *) POSITIONAL+=("${arg}"); shift;;
  esac
done
set -- "${POSITIONAL[@]}"

PKG_NAME="zfs-helper"
PKG_VERSION="${1:-1.0.0}"
PKG_ARCH="${2:-amd64}"
DST="$(pwd)/dist"
TMP="${DST}/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}"
DEBIAN_DIR="${TMP}/DEBIAN"

if [[ "${DRY_RUN}" -eq 0 ]]; then
  command -v dpkg-deb >/dev/null 2>&1 || { printf 'ERROR: dpkg-deb not found (install dpkg-dev).\n' >&2; exit 1; }
fi

printf 'Building package: %s %s %s (dry-run=%s)\n' "${PKG_NAME}" "${PKG_VERSION}" "${PKG_ARCH}" "${DRY_RUN}"

rm -rf "${DST}" "${TMP}"
mkdir -p "${DEBIAN_DIR}"

cat > "${DEBIAN_DIR}/control" <<EOF
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Section: admin
Priority: optional
Architecture: ${PKG_ARCH}
Maintainer: $(git config user.name || echo "zfs-helper")
Description: zfs-helper - privileged helper for controlled ZFS operations
Depends: systemd (>= 245)
EOF

mkdir -p "${TMP}/sbin" "${TMP}/lib/systemd/system" "${TMP}/usr/bin"

# copy known files if present, warn if missing
for f in sbin/zfs-helper.py sbin/apply-delegation.py bin/zfs-helperctl systemd/zfs-helper.socket systemd/zfs-helper.service; do
  if [[ -e "${f}" ]]; then
    dest_dir="${TMP}/$(dirname "${f}")"
    mkdir -p "${dest_dir}"
    cp -a "${f}" "${dest_dir}/"
  else
    printf 'WARNING: %s not found; it will be omitted from package\n' "${f}" >&2
  fi
done

chmod -R 755 "${TMP}/sbin" "${TMP}/usr/bin" 2>/dev/null || true

if [[ "${DRY_RUN}" -eq 1 ]]; then
  printf 'DRY RUN: package tree assembled at %s\n' "${TMP}"
  printf 'DRY RUN: would run: dpkg-deb --build "%s" "%s/%s_%s_%s.deb"\n' "${TMP}" "${DST}" "${PKG_NAME}" "${PKG_VERSION}" "${PKG_ARCH}"
  exit 0
fi

dpkg-deb --build --root-owner-group "${TMP}" "${DST}/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb"
printf 'Built %s\n' "${DST}/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb"
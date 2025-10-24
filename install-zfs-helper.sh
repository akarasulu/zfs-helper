#!/usr/bin/env bash
set -Eeuo pipefail

# -------- args --------
USER_NAME=""
UNIT_GLOBS=""
MOUNT_GLOBS=""
UNMOUNT_GLOBS=""
SNAPSHOT_GLOBS=""
ROLLBACK_GLOBS=""
CREATE_GLOBS=""
DESTROY_GLOBS=""
RENAME_FROM_GLOBS=""
RENAME_TO_GLOBS=""
SETPROP_GLOBS=""
SETPROP_VALUES=""
SHARE_GLOBS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USER_NAME="$2"; shift 2;;
    --unit-globs) UNIT_GLOBS="$2"; shift 2;;
    --mount-globs) MOUNT_GLOBS="$2"; shift 2;;
    --unmount-globs) UNMOUNT_GLOBS="$2"; shift 2;;
    --snapshot-globs) SNAPSHOT_GLOBS="$2"; shift 2;;
    --rollback-globs) ROLLBACK_GLOBS="$2"; shift 2;;
    --create-globs) CREATE_GLOBS="$2"; shift 2;;
    --destroy-globs) DESTROY_GLOBS="$2"; shift 2;;
    --rename-from-globs) RENAME_FROM_GLOBS="$2"; shift 2;;
    --rename-to-globs) RENAME_TO_GLOBS="$2"; shift 2;;
    --setprop-globs) SETPROP_GLOBS="$2"; shift 2;;
    --setprop-values) SETPROP_VALUES="$2"; shift 2;;
    --share-globs) SHARE_GLOBS="$2"; shift 2;;
    -h|--help)
      echo "Usage: sudo bash $0 --user <name> [--unit-globs 'a,b'] ..."
      exit 0;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

if [[ -z "${USER_NAME}" ]]; then
  echo "ERROR: --user is required" >&2
  exit 2
fi

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 3; }; }
need python3
need jq
need systemctl
if ! command -v /usr/sbin/zfs >/dev/null 2>&1; then
  echo "WARNING: /usr/sbin/zfs not found. Install OpenZFS to use the helper." >&2
fi

DAEMON_SRC="$(dirname "$0")/sbin/zfs-helper.py"
CLI_SRC="$(dirname "$0")/pkgs/zfs-helper-client/usr/bin/zfs-helperctl"
SOCKET_UNIT_SRC="$(dirname "$0")/systemd/zfs-helper.socket"
SERVICE_UNIT_SRC="$(dirname "$0")/systemd/zfs-helper.service"

DAEMON=/usr/local/sbin/zfs-helper.py
CLI=/usr/local/bin/zfs-helperctl
UNIT_DIR=/etc/systemd/system
SOCKET_UNIT=${UNIT_DIR}/zfs-helper.socket
SERVICE_UNIT=${UNIT_DIR}/zfs-helper.service
POLICY_ROOT=/etc/zfs-helper/policy.d
USER_DIR=${POLICY_ROOT}/"${USER_NAME}"

/usr/sbin/groupadd -f zfshelper
install -d -m 0755 -o root -g root /etc/zfs-helper
install -d -m 0755 -o root -g root "${POLICY_ROOT}"
install -d -m 0755 -o root -g root "${USER_DIR}"

install -m 0755 -o root -g root "${DAEMON_SRC}" "${DAEMON}"
install -m 0755 -o root -g root "${CLI_SRC}" "${CLI}"
install -m 0644 -o root -g root "${SOCKET_UNIT_SRC}" "${SOCKET_UNIT}"
install -m 0644 -o root -g root "${SERVICE_UNIT_SRC}" "${SERVICE_UNIT}"

to_listfile () {
  local csv="$1" file="$2"
  [[ -z "${csv}" ]] && return 0
  : > "${file}"
  IFS=',' read -ra arr <<< "${csv}"
  for item in "${arr[@]}"; do
    # shellcheck disable=SC2312
    printf '%s\n' "$(echo "${item}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')" >> "${file}"
  done
}

to_listfile "${UNIT_GLOBS}"        "${USER_DIR}/units.list"
to_listfile "${MOUNT_GLOBS}"       "${USER_DIR}/mount.list"
if [[ -n "${UNMOUNT_GLOBS}" ]]; then
  to_listfile "${UNMOUNT_GLOBS}"   "${USER_DIR}/unmount.list"
fi
to_listfile "${SNAPSHOT_GLOBS}"    "${USER_DIR}/snapshot.list"
to_listfile "${ROLLBACK_GLOBS}"    "${USER_DIR}/rollback.list"
to_listfile "${CREATE_GLOBS}"      "${USER_DIR}/create.list"
to_listfile "${DESTROY_GLOBS}"     "${USER_DIR}/destroy.list"
to_listfile "${RENAME_FROM_GLOBS}" "${USER_DIR}/rename.from.list"
to_listfile "${RENAME_TO_GLOBS}"   "${USER_DIR}/rename.to.list"
to_listfile "${SETPROP_GLOBS}"     "${USER_DIR}/setprop.list"
to_listfile "${SHARE_GLOBS}"       "${USER_DIR}/share.list"

if [[ -n "${SETPROP_VALUES}" ]]; then
  to_listfile "${SETPROP_VALUES}" "${USER_DIR}/setprop.values.list"
fi

if id "${USER_NAME}" >/dev/null 2>&1; then
  usermod -aG zfshelper "${USER_NAME}"
else
  echo "WARNING: user '${USER_NAME}' not found; skipping group membership" >&2
fi

MIN_SYSTEMD_VER=240

version_ge() {
  # returns 0 if $1 >= $2 (numeric major version compare)
  [[ "$1" -ge "$2" ]] 2>/dev/null
}

get_systemd_version() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo ""
    return 1
  fi
  # systemctl --version prints like: "systemd 253 (253.3-1)"
  ver=$(systemctl --version 2>/dev/null | head -n1 | awk '{print $2}' | sed -E 's/[^0-9].*//')
  echo "${ver:-}"
}

echo "Checking for systemd (minimum required: $MIN_SYSTEMD_VER)..."
sd_ver=$(get_systemd_version) || sd_ver=""
if [[ -z "${sd_ver}" ]]; then
  echo "ERROR: systemctl not found. This installer requires systemd." >&2
  exit 1
fi

if ! version_ge "${sd_ver}" "${MIN_SYSTEMD_VER}"; then
  echo "ERROR: systemd version ${sd_ver} detected, but >= ${MIN_SYSTEMD_VER} is required." >&2
  echo "Please upgrade systemd or use a host with a newer systemd (Debian 12 is recommended)." >&2
  exit 1
fi

systemctl daemon-reload
systemctl enable --now zfs-helper.socket
systemctl start zfs-helper.service

echo "zfs-helper installed."
echo "Policy directory: ${USER_DIR}"
echo "Socket: /run/zfs-helper.sock (group zfshelper)"
echo "Remember to re-login '${USER_NAME}' to pick up group membership."

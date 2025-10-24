#!/usr/bin/env bash
set -euo pipefail

# Install developer dependencies required by scripts/ in this project.
# Debian/Ubuntu and Manjaro/Arch supported.
# Run from project root:
#   sudo ./scripts/install-dev-deps.sh

if [[ $(id -u) -ne 0 ]]; then
  SUDO="sudo"
else
  SUDO=""
fi

install_for_apt() {
  REQUIRED_APT_PKGS=(git gnupg dpkg-dev rsync python3 python3-venv python3-pip curl ca-certificates shellcheck)
  echo "Detected apt-get. Installing packages: ${REQUIRED_APT_PKGS[*]}"
  ${SUDO} apt-get update -y
  ${SUDO} apt-get install -y "${REQUIRED_APT_PKGS[@]}"

  # try to install GitHub CLI if available in apt
  if apt-cache show gh >/dev/null 2>&1; then
    ${SUDO} apt-get install -y gh
  else
    echo "Note: 'gh' (GitHub CLI) not available via apt. Install manually if desired."
  fi
}

install_for_pacman() {
  # On Manjaro/Arch; 'dpkg' provides dpkg tools (dpkg-deb etc.)
  REQUIRED_PAC_PKGS=(git gnupg dpkg rsync python python-pip curl ca-certificates shellcheck github-cli)
  echo "Detected pacman. Installing packages: ${REQUIRED_PAC_PKGS[*]}"
  # Synchronize package databases and upgrade first
  ${SUDO} pacman -Syu --noconfirm
  ${SUDO} pacman -S --needed --noconfirm "${REQUIRED_PAC_PKGS[@]}" || {
    echo "pacman install failed; ensure you have network and correct mirrors." >&2
    exit 1
  }
}

# Detect package manager
if command -v apt-get >/dev/null 2>&1; then
  install_for_apt
elif command -v pacman >/dev/null 2>&1; then
  install_for_pacman
else
  cat >&2 <<'ERR'
ERROR: Unsupported distribution for automatic install.
Please install these tools manually:
  git, gnupg, dpkg-dev (or dpkg on Arch), rsync, python3, python3-venv,
  python3-pip (python-pip on Arch), curl, ca-certificates, shellcheck
Optionally install: gh (GitHub CLI)
ERR
  exit 1
fi

# Create Python venv and install mkdocs + material theme
PY_VENV_DIR=".venv"
echo "Creating/updating Python venv at ${PY_VENV_DIR} and installing mkdocs + theme"
python3 -m venv "${PY_VENV_DIR}"
# shellcheck disable=SC1091
source "${PY_VENV_DIR}/bin/activate"
python -m pip install --upgrade pip setuptools wheel
python -m pip install --upgrade "mkdocs" "mkdocs-material"
deactivate || true

echo
echo "Done. Quick checklist:"
echo "- Ensure your GPG/YubiKey is available for signing: gpg --list-secret-keys"
echo "- If you plan to create GitHub Releases from scripts, run: gh auth login"
echo "- To use mkdocs, activate venv: source ${PY_VENV_DIR}/bin/activate  then mkdocs build"
echo "- Make scripts executable: chmod +x scripts/*.sh"
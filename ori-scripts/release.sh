#!/usr/bin/env bash
set -euo pipefail
# Create a signed release tarball, build .deb, build docs with mkdocs, prepare apt tree,
# optionally create GitHub release and publish docs/ (including docs/apt) on the default branch.
# Usage: release.sh [--dry-run] [--no-gh] [--no-push] [--no-tag] [--force] <version> [notes-file]

DRY_RUN=0
NO_GH=0
NO_PUSH=0
NO_TAG=0
FORCE_PUSH=0
POSITIONAL=()

print_usage() {
  cat <<EOF
Usage: $0 [--dry-run] [--no-gh] [--no-push] [--no-tag] [--force] <version> [notes-file]
  --dry-run   : do everything locally but skip remote pushes/gh operations
  --no-gh     : do not create a GitHub Release (even if gh is available)
  --no-push   : do not push docs/ changes to origin
  --no-tag    : do not create a git tag (use HEAD or pre-tagged commit)
  --force     : allow force-push of default branch (unsafe)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift;;
    --no-gh) NO_GH=1; shift;;
    --no-push) NO_PUSH=1; shift;;
    --no-tag) NO_TAG=1; shift;;
    --force) FORCE_PUSH=1; shift;;
    -h|--help) print_usage; exit 0;;
    *) POSITIONAL+=("$1"); shift;;
  esac
done
set -- "${POSITIONAL[@]}"

if [[ $# -lt 1 || $# -gt 2 ]]; then
  print_usage
  exit 2
fi

VER="$1"
NOTES_FILE="${2:-}"
PKG="zfs-helper"
TARBALL="${PKG}-${VER}.tar.gz"
DIST_DIR="dist"
mkdir -p "${DIST_DIR}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# check required local commands
for cmd in git gpg dpkg-scanpackages rsync; do
  command -v "${cmd}" >/dev/null 2>&1 || { printf 'ERROR: required command %s not found\n' "${cmd}" >&2; exit 1; }
done

# ensure clean working tree
if ! git -C "${REPO_ROOT}" diff --quiet --ignore-submodules --; then
  printf 'ERROR: working tree is dirty. Commit or stash changes before releasing.\n' >&2
  exit 1
fi

# tag creation (optional)
if [[ "${NO_TAG}" -eq 0 ]]; then
  if git -C "${REPO_ROOT}" rev-parse "v${VER}" >/dev/null 2>&1; then
    printf 'ERROR: tag v%s already exists\n' "${VER}" >&2
    exit 1
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf 'DRY RUN: would create signed tag v%s\n' "${VER}"
  else
    printf 'Creating signed tag v%s\n' "${VER}"
    git -C "${REPO_ROOT}" tag -s "v${VER}" -m "Release ${VER}"

    # Immediately push the tag to origin so remote operations (gh release, CI) can find it.
    # If origin is missing, warn and continue; user can push manually.
    ORIGIN_URL="$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null || true)"
    if [[ -n "${ORIGIN_URL}" ]]; then
      printf 'Pushing tag v%s to origin...\n' "${VER}"
      if ! git -C "${REPO_ROOT}" push origin "v${VER}"; then
        printf 'ERROR: failed to push tag v%s to origin. Push it manually or run with --no-gh / --no-push\n' "${VER}" >&2
        exit 1
      fi
    else
      printf 'WARNING: no origin remote configured; tag created locally but not pushed. Push manually if you want remote release.\n' >&2
    fi
  fi
  SRC_REF="v${VER}"
else
  printf 'Skipping tag creation (--no-tag); using HEAD as source\n'
  SRC_REF="HEAD"
fi

# create tarball from source ref
printf 'Creating tarball %s from %s\n' "${TARBALL}" "${SRC_REF}"
if [[ "${DRY_RUN}" -eq 1 ]]; then
  printf 'DRY RUN: would run git archive --format=tar --prefix=%s/ %s | gzip > %s\n' "${PKG}-${VER}" "${SRC_REF}" "${DIST_DIR}/${TARBALL}"
else
  if ! git -C "${REPO_ROOT}" rev-parse --verify "${SRC_REF}^{commit}" >/dev/null 2>&1; then
    printf 'ERROR: source ref %s does not resolve to a commit. Aborting.\n' "${SRC_REF}" >&2
    git -C "${REPO_ROOT}" show-ref || true
    exit 1
  fi

  if ! git -C "${REPO_ROOT}" archive --format=tar --prefix="${PKG}-${VER}/" "${SRC_REF}" | gzip -9 > "${DIST_DIR}/${TARBALL}"; then
    printf 'ERROR: git archive failed while creating %s\n' "${DIST_DIR}/${TARBALL}" >&2
    ls -la "${DIST_DIR}" >&2
    exit 1
  fi
fi

# verify tarball exists
sigfile="${DIST_DIR}/${TARBALL}.asc"
if [[ "${DRY_RUN}" -eq 0 ]]; then
  if [[ ! -f "${DIST_DIR}/${TARBALL}" ]]; then
    printf 'ERROR: expected tarball %s missing in %s. Aborting.\n' "${TARBALL}" "${DIST_DIR}" >&2
    ls -la "${DIST_DIR}" >&2
    exit 1
  fi
fi

# sign tarball with local gpg key
GPG_KEY=$(git -C "${REPO_ROOT}" config --get user.signingkey || true)
if [[ "${DRY_RUN}" -eq 1 ]]; then
  printf 'DRY RUN: would sign %s with key %s\n' "${DIST_DIR}/${TARBALL}" "${GPG_KEY:-<default>}"
else
  if [[ -n "${GPG_KEY}" ]]; then
    gpg --batch --yes --armor --local-user "${GPG_KEY}" --detach-sign -o "${sigfile}" "${DIST_DIR}/${TARBALL}"
  else
    gpg --batch --yes --armor --detach-sign -o "${sigfile}" "${DIST_DIR}/${TARBALL}"
  fi
  printf 'Tarball and signature created: %s %s\n' "${DIST_DIR}/${TARBALL}" "${sigfile}"
fi

# build .deb
if [[ "${DRY_RUN}" -eq 1 ]]; then
  bash "${REPO_ROOT}/scripts/make-deb.sh" "${VER}" "amd64" --dry-run
else
  bash "${REPO_ROOT}/scripts/make-deb.sh" "${VER}" "amd64"
fi

# prepare APT repo tree
APT_DIR="${DIST_DIR}/apt"
rm -rf "${APT_DIR}"
mkdir -p "${APT_DIR}/pool/${PKG}" "${APT_DIR}/dists/bookworm/main/binary-amd64"

cp "${DIST_DIR}/${PKG}_${VER}_amd64.deb" "${APT_DIR}/pool/${PKG}/" 2>/dev/null || true

pushd "${APT_DIR}/pool" >/dev/null
dpkg-scanpackages . /dev/null | gzip -9c > ../dists/bookworm/main/binary-amd64/Packages.gz
popd >/dev/null

# generate Packages.gz (already done) then build a proper Release with checksums & Date
if command -v apt-ftparchive >/dev/null 2>&1; then
  printf 'Generating Release file with apt-ftparchive (includes hashes & Date)\n'
  apt-ftparchive \
    -o APT::FTPArchive::Release::Origin="${PKG}" \
    -o APT::FTPArchive::Release::Label="${PKG}" \
    -o APT::FTPArchive::Release::Suite="bookworm" \
    -o APT::FTPArchive::Release::Codename="bookworm" \
    -o APT::FTPArchive::Release::Architectures="amd64" \
    -o APT::FTPArchive::Release::Components="main" \
    release "${APT_DIR}/dists/bookworm" > "${APT_DIR}/dists/bookworm/Release"
else
  printf 'apt-ftparchive not found; generating Release with checksums & Date (fallback)\n'
  RELEASE_DIR="${APT_DIR}/dists/bookworm"
  mkdir -p "${RELEASE_DIR}"
  TMP="$(mktemp)"
  {
    printf 'Origin: %s\n' "${PKG}"
    printf 'Label: %s\n' "${PKG}"
    printf 'Suite: bookworm\n'
    printf 'Codename: bookworm\n'
    printf 'Date: %s\n' "$(date -u +"%a, %d %b %Y %H:%M:%S %Z")"
    printf 'Architectures: amd64\n'
    printf 'Components: main\n'
    printf 'Description: %s APT repo for Debian 12 (bookworm)\n' "${PKG}"
    printf '\n'
  } > "${TMP}"

  # gather files (relative paths) and compute checksums
  pushd "${RELEASE_DIR}" >/dev/null
  # list files excluding Release / InRelease / Release.gpg
  mapfile -t FL < <(find . -type f ! -name 'Release' ! -name 'InRelease' ! -name 'Release.gpg' -printf '%P\n' | sort)

  # MD5Sum
  printf 'MD5Sum:\n' >> "${TMP}"
  for f in "${FL[@]}"; do
    # ensure file exists
    if [[ -f "${f}" ]]; then
      md5=$(md5sum -- "${f}" | awk '{print $1}')
      size=$(stat -c%s -- "${f}")
      printf ' %s %d %s\n' "${md5}" "${size}" "${f}" >> "${TMP}"
    fi
  done

  # SHA1
  printf '\nSHA1:\n' >> "${TMP}"
  for f in "${FL[@]}"; do
    if [[ -f "${f}" ]]; then
      sha1=$(sha1sum -- "${f}" | awk '{print $1}')
      size=$(stat -c%s -- "${f}")
      printf ' %s %d %s\n' "${sha1}" "${size}" "${f}" >> "${TMP}"
    fi
  done

  # SHA256
  printf '\nSHA256:\n' >> "${TMP}"
  for f in "${FL[@]}"; do
    if [[ -f "${f}" ]]; then
      sha256=$(sha256sum -- "${f}" | awk '{print $1}')
      size=$(stat -c%s -- "${f}")
      printf ' %s %d %s\n' "${sha256}" "${size}" "${f}" >> "${TMP}"
    fi
  done

  popd >/dev/null

  mv "${TMP}" "${RELEASE_DIR}/Release"
fi

# sign Release (unchanged)
if [[ "${DRY_RUN}" -eq 1 ]]; then
  printf 'DRY RUN: would sign Release file with key %s\n' "${GPG_KEY:-<default>}"
else
  if [[ -n "${GPG_KEY}" ]]; then
    gpg --default-key "${GPG_KEY}" --clearsign -o "${APT_DIR}/dists/bookworm/InRelease" "${APT_DIR}/dists/bookworm/Release"
    gpg --default-key "${GPG_KEY}" --detach-sign -o "${APT_DIR}/dists/bookworm/Release.gpg" "${APT_DIR}/dists/bookworm/Release"
  else
    gpg --clearsign -o "${APT_DIR}/dists/bookworm/InRelease" "${APT_DIR}/dists/bookworm/Release"
    gpg --detach-sign -o "${APT_DIR}/dists/bookworm/Release.gpg" "${APT_DIR}/dists/bookworm/Release"
  fi
fi

printf 'Local release artifacts prepared in: %s\n' "${DIST_DIR}"

# ensure APT_DIR exists (we'll place the public key into it so it survives mkdocs clean)
mkdir -p "${APT_DIR}"

# If a committed public key exists under keys/, copy it into the APT tree.
KEY_SRC="${REPO_ROOT}/keys/zfs-helper-apt-key.asc"
if [[ -f "${KEY_SRC}" ]]; then
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf 'DRY RUN: would copy committed key %s -> %s\n' "${KEY_SRC}" "${APT_DIR}/zfs-helper-apt-key.asc"
  else
    printf 'Copying committed APT public key %s -> %s\n' "${KEY_SRC}" "${APT_DIR}/zfs-helper-apt-key.asc"
    cp -f "${KEY_SRC}" "${APT_DIR}/zfs-helper-apt-key.asc"
  fi
else
  # fallback: export public key from local GPG key if available
  GPG_KEY_ID="${GPG_KEY:-}"
  if [[ -z "${GPG_KEY_ID}" ]]; then
    GPG_KEY_ID="$(gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^sec:/ {print $5; exit}')"
  fi

  if [[ -n "${GPG_KEY_ID}" ]]; then
    PUBKEY_PATH="${APT_DIR}/zfs-helper-apt-key.asc"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      printf 'DRY RUN: would export public key %s -> %s\n' "${GPG_KEY_ID}" "${PUBKEY_PATH}"
    else
      printf 'Exporting public key %s -> %s\n' "${GPG_KEY_ID}" "${PUBKEY_PATH}"
      gpg --armor --export "${GPG_KEY_ID}" > "${PUBKEY_PATH}"
    fi
  else
    printf 'WARNING: no committed key at %s and no local signing key found; apt clients will need the public key installed manually\n' "${KEY_SRC}" >&2
  fi
fi

# Build docs with mkdocs so docs/index.html always exists
MKDOCS_CMD=""
if [[ -x "${REPO_ROOT}/.venv/bin/mkdocs" ]]; then
  MKDOCS_CMD="${REPO_ROOT}/.venv/bin/mkdocs"
elif command -v mkdocs >/dev/null 2>&1; then
  MKDOCS_CMD="mkdocs"
fi

if [[ -n "${MKDOCS_CMD}" ]]; then
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf 'DRY RUN: would run: %s build --site-dir %s/docs\n' "${MKDOCS_CMD}" "${REPO_ROOT}"
  else
    printf 'Building docs with %s (output -> %s/docs)\n' "${MKDOCS_CMD}" "${REPO_ROOT}"
    # mkdocs cleans the docs/ site dir; we exported the public key into dist/apt so it won't be lost
    "${MKDOCS_CMD}" build --site-dir "${REPO_ROOT}/docs"
    printf 'Docs built into %s/docs\n' "${REPO_ROOT}"
  fi
else
  printf 'WARNING: mkdocs not found; docs will not be rebuilt. Ensure docs/index.html exists in repo.\n' >&2
fi

# Create GitHub Release (optional)
if [[ "${NO_GH}" -eq 0 && "${DRY_RUN}" -eq 0 ]]; then
  if command -v gh >/dev/null 2>&1; then
    if ! gh auth status >/dev/null 2>&1; then
      printf 'WARNING: gh not authenticated; skipping GitHub Release creation\n' >&2
    else
      ASSETS=()
      [[ -f "${DIST_DIR}/${TARBALL}" ]] && ASSETS+=("${DIST_DIR}/${TARBALL}")
      [[ -f "${sigfile}" ]] && ASSETS+=("${sigfile}")
      [[ -f "${DIST_DIR}/${PKG}_${VER}_amd64.deb" ]] && ASSETS+=("${DIST_DIR}/${PKG}_${VER}_amd64.deb")

      if [[ ${#ASSETS[@]} -eq 0 ]]; then
        printf 'WARNING: no artifact files found to upload to GitHub Release; skipping upload\n' >&2
      else
        if [[ -n "${NOTES_FILE}" ]]; then
          gh release create "v${VER}" "${ASSETS[@]}" --title "v${VER}" --notes-file "${NOTES_FILE}"
        else
          gh release create "v${VER}" "${ASSETS[@]}" --title "v${VER}" --notes "Release ${VER}"
        fi
        printf 'GitHub release v%s created/updated\n' "${VER}"
      fi
    fi
  else
    printf 'gh CLI not found; skipping GitHub Release creation\n' >&2
  fi
else
  printf 'Skipping GitHub Release (no-gh or dry-run enabled)\n'
fi

# Publish apt tree into docs/apt on the repository's default branch (preserve other docs/)
if [[ "${NO_PUSH}" -eq 1 || "${DRY_RUN}" -eq 1 ]]; then
  printf 'Skipping docs/ push (no-push or dry-run enabled)\n'
  exit 0
fi

REMOTE="$(git -C "${REPO_ROOT}" remote get-url origin || true)"
if [[ -z "${REMOTE}" ]]; then
  printf 'ERROR: no origin remote found; cannot publish docs/\n' >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
pushd "${TMP_DIR}" >/dev/null

# determine default branch name (robustly parse git ls-remote --symref output)
DEFAULT_BRANCH="$(git ls-remote --symref "${REMOTE}" HEAD 2>/dev/null | awk '/^ref:/ {print $2; exit}' | sed 's|refs/heads/||')"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

printf 'Publishing APT tree to %s/docs/apt (branch %s)\n' "${REMOTE}" "${DEFAULT_BRANCH}"

# clone default branch shallowly if possible, otherwise init
if git clone --depth 1 --branch "${DEFAULT_BRANCH}" "${REMOTE}" . 2>/dev/null; then
  :
else
  git init -q
  git remote add origin "${REMOTE}"
  git checkout -b "${DEFAULT_BRANCH}"
fi

# sync locally-built docs into the checkout (overwrite files produced by mkdocs)
mkdir -p docs
rsync -a --delete "${REPO_ROOT}/docs/" docs/ || true

# remove only docs/apt content (preserve all other docs/)
git rm -r --ignore-unmatch docs/apt >/dev/null 2>&1 || true
mkdir -p docs/apt

# sync apt tree into docs/apt/ (copy contents into docs/apt)
rsync -a --delete "${REPO_ROOT}/${APT_DIR}/" docs/apt/

git add -A
git commit -m "Publish docs (mkdocs) and APT repo for ${VER} to docs/apt" >/dev/null 2>&1 || true

# attempt non-forced push
if git push origin "${DEFAULT_BRANCH}" 2>/tmp/gitpush.err; then
  printf 'Published docs and apt repo to %s/docs/apt on branch %s (non-forced)\n' "${REMOTE}" "${DEFAULT_BRANCH}"
else
  if [[ "${FORCE_PUSH}" -eq 1 ]]; then
    printf 'Non-fast-forward push failed; performing forced push (as requested)\n'
    git push --force origin "${DEFAULT_BRANCH}"
    printf 'Published docs and apt repo to %s/docs/apt on branch %s (forced)\n' "${REMOTE}" "${DEFAULT_BRANCH}"
  else
    printf 'ERROR: push rejected (non-fast-forward). To overwrite use --force, or reconcile remote branch.\n' >&2
    sed -n '1,200p' /tmp/gitpush.err >&2 || true
    exit 1
  fi
fi

popd >/dev/null
printf 'Release complete. Artifacts: %s\n' "${DIST_DIR}"

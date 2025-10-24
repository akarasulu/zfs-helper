#!/usr/bin/env bash
set -euo pipefail
# Build mkdocs site and publish to gh-pages.
# Usage: deploy-site.sh [--dry-run] [--no-push] [--force]

DRY_RUN=0
NO_PUSH=0
FORCE_PUSH=0
POSITIONAL=()

print_usage() {
  cat <<EOF
Usage: $0 [--dry-run] [--no-push] [--force]
  --dry-run : build site but do not push to remote
  --no-push : do not push changes to origin
  --force   : allow force-push of gh-pages
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift;;
    --no-push) NO_PUSH=1; shift;;
    --force) FORCE_PUSH=1; shift;;
    -h|--help) print_usage; exit 0;;
    *) POSITIONAL+=("$1"); shift;;
  esac
done
set -- "${POSITIONAL[@]}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE_DIR="${REPO_ROOT}/site"
REMOTE="$(git -C "${REPO_ROOT}" remote get-url origin || true)"

if [[ -z "${REMOTE}" ]]; then
  printf 'ERROR: No origin remote; set "origin" before deploying.\n' >&2
  exit 1
fi

command -v mkdocs >/dev/null 2>&1 || { printf 'ERROR: mkdocs not found. Install mkdocs (pip) before deploying.\n' >&2; exit 1; }

mkdocs build --site-dir "${SITE_DIR}"

if [[ "${DRY_RUN}" -eq 1 || "${NO_PUSH}" -eq 1 ]]; then
  printf 'Built site at %s (not pushing due to --dry-run or --no-push)\n' "${SITE_DIR}"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
pushd "${TMP}" >/dev/null

git init -q
git remote add origin "${REMOTE}"

if git ls-remote --exit-code origin gh-pages >/dev/null 2>&1; then
  git fetch origin gh-pages:gh-pages
  git checkout gh-pages
else
  git checkout --orphan gh-pages
fi

git rm -rf . >/dev/null 2>&1 || true
rsync -a --delete "${SITE_DIR}/" .

git add -A
git commit -m "Publish docs (mkdocs) $(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true

if git push origin gh-pages 2>/tmp/ghpush.err; then
  printf 'Docs published to gh-pages (non-forced)\n'
else
  if [[ "${FORCE_PUSH}" -eq 1 ]]; then
    printf 'Non-fast-forward push failed; performing forced push (as requested)\n'
    git push --force origin gh-pages
    printf 'Docs published to gh-pages (forced)\n'
  else
    printf 'ERROR: push rejected (non-fast-forward). To overwrite use --force, or reconcile remote branch manually.\n' >&2
    sed -n '1,200p' /tmp/ghpush.err >&2 || true
    exit 1
  fi
fi

popd >/dev/null
printf 'Docs deploy finished\n'
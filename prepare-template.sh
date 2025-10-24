#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: prepare-template.sh <repository-url> [target-directory]

Clone your fork of gh-repos, reset MkDocs content to placeholders,
regenerate the static site, and export a selected GPG public key.

Arguments:
  <repository-url>   SSH or HTTPS URL of your fork (required).
  [target-directory] Optional destination directory for the clone. Defaults to
                     the repository name derived from the URL.
EOF
}

PROMPT_FD=0
PROMPT_FD_SET="no"

parse_repo_url() {
    local url="$1"
    if [[ "$url" =~ ^git@github\.com:([^/]+)/(.+?)(\.git)?$ ]]; then
        REPO_OWNER="${BASH_REMATCH[1]}"
        REPO_NAME="${BASH_REMATCH[2]}"
    elif [[ "$url" =~ ^https://github\.com/([^/]+)/(.+?)(\.git)?$ ]]; then
        REPO_OWNER="${BASH_REMATCH[1]}"
        REPO_NAME="${BASH_REMATCH[2]}"
    else
        echo "Unable to parse repository owner/name from URL: $url" >&2
        exit 1
    fi
    REPO_NAME="${REPO_NAME%.git}"
}

update_mkdocs_config() {
    local owner="$1"
    local repo="$2"
    local repo_url="https://github.com/${owner}/${repo}"
    local docs_url="https://${owner}.github.io/${repo}"

    SITE_NAME=$(python3 - <<PY
from pathlib import Path
import re

path = Path("mkdocs.yml")
if not path.exists():
    raise SystemExit("mkdocs.yml not found; cannot update configuration.")

owner = ${owner@Q}
repo = ${repo@Q}
repo_url = ${repo_url@Q}
docs_url = ${docs_url@Q} + "/"

def humanize(name: str) -> str:
    if not name:
        return "Project Documentation"
    parts = re.split(r"[-_]+", name)
    words = [word.capitalize() for word in parts if word]
    return " ".join(words) if words else name

text = path.read_text()

def set_line(content: str, key: str, value: str) -> str:
    pattern = rf"^{key}:\s?.*$"
    replacement = f"{key}: {value}"
    if re.search(pattern, content, flags=re.MULTILINE):
        return re.sub(pattern, replacement, content, flags=re.MULTILINE)
    return content + "\n" + replacement + "\n"

site_name = humanize(repo)
text = set_line(text, "site_name", f'"{site_name}"')
text = set_line(text, "repo_url", repo_url)
text = set_line(text, "repo_name", repo)

text = re.sub(
    r"(link:\s*)https://github\.com/[^\s]+",
    rf"\\1{repo_url}",
    text,
    count=1,
)
text = re.sub(
    r"(link:\s*)https://[A-Za-z0-9_.-]+\.github\.io/[^\s/]+/?",
    rf"\\1{docs_url}",
    text,
    count=1,
)

path.write_text(text)
print(site_name)
PY
)
    SITE_NAME=${SITE_NAME:-"Project Documentation"}
}

reset_readme() {
    local candidates=("README.md" "Readme.md" "readme.md")
    local target=""
    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            target="$candidate"
            break
        fi
    done
    if [[ -z "$target" ]]; then
        target="README.md"
    fi

    cat > "$target" <<EOF
# ${SITE_NAME}

> Replace this README with information about ${SITE_NAME}.

## Quick Start

- Describe how to install or use the project.
- Outline any prerequisites or environment setup steps.
- Link to detailed documentation once it is ready.

## Next Steps

- Customize the documentation in \`mkdocs/\`.
- Update package definitions under \`pkgs/\`.
- Remove this placeholder content when you add real details.
EOF
}

prompt() {
    local message="$1"
    local input
    if [[ "$PROMPT_FD_SET" == "no" ]]; then
        if ! read -rp "$message" input; then
            echo "Input aborted." >&2
            exit 1
        fi
    else
        printf "%s" "$message" >&"$PROMPT_FD"
        if ! IFS= read -r -u "$PROMPT_FD" input; then
            echo "Input aborted." >&2
            exit 1
        fi
        printf "\n" >&"$PROMPT_FD"
    fi
    REPLY="$input"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if ! command -v git >/dev/null 2>&1; then
    echo "git is required but was not found in PATH." >&2
    exit 1
fi

if ! command -v gpg >/dev/null 2>&1; then
    echo "gpg is required but was not found in PATH." >&2
    exit 1
fi

if [[ ! -t 0 ]]; then
    if [[ -r /dev/tty ]]; then
        exec {PROMPT_FD}<>/dev/tty
        PROMPT_FD_SET="yes"
    else
        echo "Cannot prompt for input: no interactive terminal available." >&2
        exit 1
    fi
fi

if [[ $# -lt 1 ]]; then
    prompt "Repository URL for your fork (e.g. git@github.com:user/gh-repos.git): "
    repo_url="$REPLY"
    if [[ -z "${repo_url}" ]]; then
        echo "Repository URL is required." >&2
        usage >&2
        exit 1
    fi
else
    repo_url="$1"
fi

parse_repo_url "$repo_url"

derive_dir_name() {
    local url="$1"
    local trimmed="${url%%.git}"
    trimmed="${trimmed%/}"
    echo "${trimmed##*/}"
}

target_dir="${2:-$(derive_dir_name "$repo_url")}"

if [[ -z "$target_dir" ]]; then
    echo "Unable to determine target directory name. Please specify it explicitly." >&2
    exit 1
fi

if [[ -e "$target_dir" ]]; then
    echo "Target directory '$target_dir' already exists. Choose another name or remove it." >&2
    exit 1
fi

echo "📦 Cloning $repo_url into $target_dir ..."
git clone --origin origin "$repo_url" "$target_dir"

cd "$target_dir"

if [[ ! -d "templates/mkdocs" ]]; then
    echo "templates/mkdocs directory not found in the cloned repository." >&2
    exit 1
fi

echo "🧹 Resetting MkDocs source content..."
rm -rf mkdocs/*
cp -R templates/mkdocs/. mkdocs/

echo "🛠️  Updating MkDocs configuration with repository details..."
update_mkdocs_config "$REPO_OWNER" "$REPO_NAME"

echo "🗃️  Persisting repository metadata for tooling..."
git config gh-repos.owner "$REPO_OWNER"
git config gh-repos.name "$REPO_NAME"

echo "🧾 Resetting README.md placeholder..."
reset_readme

echo "🧽 Clearing generated docs and previous APT repository..."
rm -rf docs

if [[ ! -x "./scripts/mkdocs.sh" ]]; then
    echo "scripts/mkdocs.sh is missing or not executable." >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to rebuild documentation." >&2
    exit 1
fi

echo "🏗️ Rebuilding documentation with placeholder content..."
./scripts/mkdocs.sh

echo "🔐 Discovering available GPG private keys..."
mapfile -t gpg_lines < <(gpg --list-secret-keys --with-colons 2>/dev/null || true)

declare -a fingerprints=()
declare -a labels=()
current_fpr=""

for line in "${gpg_lines[@]}"; do
    IFS=':' read -ra parts <<<"$line"
    type="${parts[0]}"
    case "$type" in
        fpr)
            current_fpr="${parts[9]}"
            ;;
        uid)
            if [[ -n "$current_fpr" ]]; then
                fingerprints+=("$current_fpr")
                labels+=("${parts[9]}")
                current_fpr=""
            fi
            ;;
    esac
done

if [[ ${#fingerprints[@]} -eq 0 ]]; then
    echo "No GPG private keys were found. Create one with 'gpg --full-generate-key' and rerun this script." >&2
    exit 1
fi

echo "Available keys:"
for i in "${!fingerprints[@]}"; do
    printf "  [%d] %s\n      %s\n" "$((i + 1))" "${labels[$i]}" "${fingerprints[$i]}"
done

selection=""
attempts=0
max_attempts=5
while [[ -z "$selection" ]]; do
    prompt "Select a key to export [1-${#fingerprints[@]}]: "
    choice="$REPLY"
    if [[ -z "$choice" ]]; then
        attempts=$((attempts + 1))
        if (( attempts >= max_attempts )); then
            echo "No selection detected after $max_attempts attempts. Exiting." >&2
            exit 1
        fi
        echo "No selection detected. Please choose a number between 1 and ${#fingerprints[@]}."
        continue
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#fingerprints[@]} )); then
        selection=$((choice - 1))
    else
        echo "Invalid selection. Please choose a number between 1 and ${#fingerprints[@]}."
        attempts=$((attempts + 1))
        if (( attempts >= max_attempts )); then
            echo "Too many invalid attempts. Exiting." >&2
            exit 1
        fi
    fi
done

mkdir -p keys docs/apt
fingerprint="${fingerprints[$selection]}"

echo "📝 Exporting public key for ${labels[$selection]}..."
gpg --armor --export "$fingerprint" > keys/apt-repo-pubkey.asc
cp keys/apt-repo-pubkey.asc docs/apt/apt-repo-pubkey.asc

cat <<EOF
✅ Template preparation complete.

Next steps:
  1. cd $target_dir
  2. Review placeholder docs in mkdocs/.
  3. Update packages or scripts as needed.
  4. Run ./scripts/mkdocs.sh and ./scripts/mkrepo.sh after customizing.
  5. git status && git commit -am "Customize template"
EOF

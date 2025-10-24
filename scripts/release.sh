#!/usr/bin/env bash
set -euo pipefail

# release.sh - Create GitHub release with artifacts using gh CLI
# This script runs on the HOST where GitHub CLI is configured

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"
DOCS_DIR="$WORKSPACE_ROOT/docs"
DEB_OUTPUT_DIR="$WORKSPACE_ROOT/debs"

echo "🚀 Creating GitHub release..."
echo "════════════════════════════════"

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ Error: GitHub CLI (gh) is not installed"
    echo "💡 Install with: curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg"
    echo "   echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null"
    echo "   sudo apt update && sudo apt install gh"
    exit 1
fi

# Check if we're in a git repository
if [[ ! -d "$WORKSPACE_ROOT/.git" ]]; then
    echo "❌ Error: Not in a git repository"
    exit 1
fi

# Check GitHub CLI authentication
if ! gh auth status &> /dev/null; then
    echo "❌ Error: GitHub CLI is not authenticated"
    echo "💡 Authenticate with: gh auth login"
    exit 1
fi

origin_url=$(git -C "$WORKSPACE_ROOT" config --get remote.origin.url 2>/dev/null || echo "")
if [[ -z "$origin_url" ]]; then
    echo "❌ Error: Unable to determine git remote origin URL"
    exit 1
fi

if [[ "$origin_url" =~ ^git@github\.com:([^/]+)/(.+?)(\.git)?$ ]]; then
    repo_owner="${BASH_REMATCH[1]}"
    repo_name="${BASH_REMATCH[2]}"
elif [[ "$origin_url" =~ ^https://github\.com/([^/]+)/(.+?)(\.git)?$ ]]; then
    repo_owner="${BASH_REMATCH[1]}"
    repo_name="${BASH_REMATCH[2]}"
else
    echo "❌ Error: Unsupported remote origin format: $origin_url"
    exit 1
fi

config_owner=$(git -C "$WORKSPACE_ROOT" config --get gh-repos.owner 2>/dev/null || true)
config_name=$(git -C "$WORKSPACE_ROOT" config --get gh-repos.name 2>/dev/null || true)
if [[ -z "$repo_owner" && -n "$config_owner" ]]; then
    repo_owner="$config_owner"
fi
if [[ -z "$repo_name" && -n "$config_name" ]]; then
    repo_name="$config_name"
fi

repo_name="${repo_name%.git}"

if [[ ( -z "$repo_owner" || -z "$repo_name" ) && -n "${GITHUB_REPOSITORY:-}" && "$GITHUB_REPOSITORY" =~ ^([^/]+)/([^/]+)$ ]]; then
    repo_owner="${BASH_REMATCH[1]}"
    repo_name="${BASH_REMATCH[2]}"
    repo_name="${repo_name%.git}"
fi

if [[ -z "$repo_name" ]]; then
    repo_name="$(basename "$WORKSPACE_ROOT")"
fi

if [[ -z "$repo_owner" ]]; then
    repo_owner="$(git -C "$WORKSPACE_ROOT" config --get user.name 2>/dev/null || true)"
    repo_owner="${repo_owner%% *}"
fi

if [[ -z "$repo_owner" ]]; then
    repo_owner="$(whoami 2>/dev/null || echo 'user')"
fi

repo_slug="${repo_owner}/${repo_name}"
docs_url="https://${repo_owner}.github.io/${repo_name}"
apt_list_name="${repo_name}.list"
gpg_key_name="${repo_name}.asc"

# Get latest tag
latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [[ -z "$latest_tag" ]]; then
    echo "❌ Error: No git tags found"
    echo "💡 Run publish.sh first to create a tagged release"
    exit 1
fi

# Check if tag was provided as argument
if [[ -n "${1:-}" ]]; then
    release_tag="$1"
    
    # Verify tag exists
    if ! git tag -l | grep -q "^$release_tag$"; then
        echo "❌ Error: Tag $release_tag does not exist"
        echo "📋 Available tags:"
        git tag -l | head -10
        exit 1
    fi
else
    release_tag="$latest_tag"
fi

echo "🏷️  Creating release for tag: $release_tag"

# Check if release already exists
if gh release view "$release_tag" --repo "$repo_slug" &> /dev/null; then
    echo "⚠️  Release $release_tag already exists"
    read -p "🤔 Delete and recreate? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️  Deleting existing release..."
        gh release delete "$release_tag" --yes --repo "$repo_slug"
    else
        echo "❌ Release cancelled by user"
        exit 1
    fi
fi

# Get commit info for the tag
tag_commit=$(git rev-list -n 1 "$release_tag")
tag_date=$(git log -1 --format="%ci" "$tag_commit")
tag_author=$(git log -1 --format="%an" "$tag_commit")

echo "📋 Release details:"
echo "   Tag: $release_tag"
echo "   Commit: $(git rev-parse --short "$tag_commit")"
echo "   Date: $tag_date"
echo "   Author: $tag_author"

# Prepare release artifacts
echo ""
echo "📦 Preparing release artifacts..."

artifacts_dir="$WORKSPACE_ROOT/release-artifacts"
rm -rf "$artifacts_dir"
mkdir -p "$artifacts_dir"

# Copy .deb packages
deb_count=0
if [[ -d "$DEB_OUTPUT_DIR" ]]; then
    for deb_file in "$DEB_OUTPUT_DIR"/*.deb; do
        if [[ -f "$deb_file" ]]; then
            cp "$deb_file" "$artifacts_dir/"
            echo "   📦 $(basename "$deb_file")"
            deb_count=$((deb_count + 1))
        fi
    done
fi

# Copy additional .deb files from docs/apt/pool if they exist
if [[ -d "$DOCS_DIR/apt/pool" ]]; then
    for deb_file in "$DOCS_DIR/apt/pool"/*.deb; do
        if [[ -f "$deb_file" ]]; then
            deb_name=$(basename "$deb_file")
            if [[ ! -f "$artifacts_dir/$deb_name" ]]; then
                cp "$deb_file" "$artifacts_dir/"
                echo "   📦 $deb_name (from repository)"
                deb_count=$((deb_count + 1))
            fi
        fi
    done
fi

# Create checksums file
if [[ $deb_count -gt 0 ]]; then
    echo "🔍 Generating checksums..."
    cd "$artifacts_dir"
    
    {
        echo "# SHA256 Checksums for $release_tag"
        echo "# Generated on $(date -Ru)"
        echo ""
        sha256sum *.deb
    } > SHA256SUMS
    
    # Sign checksums if GPG is available
    if command -v gpg &> /dev/null && [[ -n "${GPG_KEY_ID:-}" ]]; then
        echo "🔐 Signing checksums..."
        gpg --detach-sign --armor --local-user "${GPG_KEY_ID}" SHA256SUMS
        echo "   ✅ Created SHA256SUMS.asc"
    fi
    
    cd "$WORKSPACE_ROOT"
    echo "   ✅ Created SHA256SUMS"
fi

# Create repository archive
echo "📁 Creating repository archive..."
repo_archive_name="${repo_name}-apt-repository-$release_tag.tar.gz"
repo_archive="$artifacts_dir/$repo_archive_name"

if [[ -d "$DOCS_DIR/apt" ]]; then
    tar -czf "$repo_archive" -C "$DOCS_DIR" apt/
    echo "   ✅ Created repository archive: $repo_archive_name"
else
    echo "   ⚠️  No APT repository found to archive"
fi

# Create installation script
cat > "$artifacts_dir/install-repository.sh" << EOF
#!/bin/bash
# Installation script for ${repo_name} APT repository

set -euo pipefail

# Repository configuration
REPO_OWNER="${repo_owner}"
REPO_NAME="${repo_name}"
REPO_URL="https://\${REPO_OWNER}.github.io/\${REPO_NAME}"
KEY_DEST="/etc/apt/trusted.gpg.d/${gpg_key_name}"
LIST_DEST="/etc/apt/sources.list.d/${apt_list_name}"

echo "Installing \${REPO_NAME} APT repository..."
echo "Repository: \${REPO_URL}"

# Download and add GPG key
echo "Adding GPG key..."
curl -fsSL "\${REPO_URL}/apt/apt-repo-pubkey.asc" | sudo tee "\${KEY_DEST}" > /dev/null

# Add repository
echo "Adding repository to sources..."
echo "deb \${REPO_URL}/apt stable main" | sudo tee "\${LIST_DEST}"

# Update package lists
echo "Updating package lists..."
sudo apt update

echo "Repository installed successfully!"
echo "Install packages with: sudo apt install <package-name>"
EOF

chmod +x "$artifacts_dir/install-repository.sh"
echo "   ✅ Created install-repository.sh"

# Generate release notes
echo ""
echo "📝 Generating release notes..."

release_notes_file="$artifacts_dir/RELEASE_NOTES.md"

cat > "$release_notes_file" << EOF
# Release $release_tag

Released on $(date "+%B %d, %Y")

## 📦 Packages Included

EOF

# List packages with details
if [[ $deb_count -gt 0 ]]; then
    echo "This release includes $deb_count Debian package(s):" >> "$release_notes_file"
    echo "" >> "$release_notes_file"
    
    for deb_file in "$artifacts_dir"/*.deb; do
        if [[ -f "$deb_file" ]]; then
            # Extract package info
            pkg_name=$(dpkg-deb -f "$deb_file" Package 2>/dev/null || echo "Unknown")
            pkg_version=$(dpkg-deb -f "$deb_file" Version 2>/dev/null || echo "Unknown")
            pkg_arch=$(dpkg-deb -f "$deb_file" Architecture 2>/dev/null || echo "Unknown")
            pkg_desc=$(dpkg-deb -f "$deb_file" Description 2>/dev/null || echo "No description available")
            
            echo "### $pkg_name ($pkg_version)" >> "$release_notes_file"
            echo "- **Architecture**: $pkg_arch" >> "$release_notes_file"
            echo "- **Description**: $pkg_desc" >> "$release_notes_file"
            echo "- **File**: \`$(basename "$deb_file")\`" >> "$release_notes_file"
            echo "" >> "$release_notes_file"
        fi
    done
else
    echo "No packages included in this release." >> "$release_notes_file"
    echo "" >> "$release_notes_file"
fi

cat >> "$release_notes_file" << EOF

## 🚀 Installation

### Quick Setup
\`\`\`bash
# Download and run installation script
curl -fsSL https://github.com/$repo_slug/releases/download/$release_tag/install-repository.sh | bash
\`\`\`

### Manual Setup
\`\`\`bash
# Add GPG key
curl -fsSL $docs_url/apt/apt-repo-pubkey.asc | sudo tee /etc/apt/trusted.gpg.d/$gpg_key_name > /dev/null

# Add repository
echo "deb $docs_url/apt stable main" | sudo tee /etc/apt/sources.list.d/$apt_list_name

# Update and install
sudo apt update
sudo apt install <package-name>
\`\`\`

## 📁 Additional Files

- **SHA256SUMS**: Checksums for all packages
- **install-repository.sh**: Automated setup script
- **${repo_name}-apt-repository-$release_tag.tar.gz**: Complete APT repository archive

## 🔐 Security

All packages and repository metadata are cryptographically signed with GPG.
Verify checksums before installation:

\`\`\`bash
sha256sum -c SHA256SUMS
\`\`\`

## 📋 Changes

EOF

# Add git log since last tag
previous_tag=$(git describe --tags --abbrev=0 "$release_tag^" 2>/dev/null || echo "")

if [[ -n "$previous_tag" ]]; then
    echo "Changes since $previous_tag:" >> "$release_notes_file"
    echo "" >> "$release_notes_file"
    git log --pretty=format:"- %s (%h)" "$previous_tag..$release_tag" >> "$release_notes_file"
else
    echo "Initial release." >> "$release_notes_file"
fi

echo "" >> "$release_notes_file"

# Create the GitHub release
echo ""
echo "🎉 Creating GitHub release..."

release_args=(
    "release" "create" "$release_tag"
    "--repo" "$repo_slug"
    "--title" "Release $release_tag"
    "--notes-file" "$release_notes_file"
)

# Add artifacts
if [[ $deb_count -gt 0 ]]; then
    for artifact in "$artifacts_dir"/*; do
        if [[ -f "$artifact" && "$artifact" != "$release_notes_file" ]]; then
            release_args+=("$artifact")
        fi
    done
fi

if ! release_output=$(gh "${release_args[@]}" 2>&1); then
    echo "$release_output"
    if [[ "$release_output" == *'"workflow" scope may be required'* ]]; then
        echo "💡 Tip: run 'gh auth refresh -h github.com -s repo -s workflow' to grant the required scopes, then retry."
    fi
    echo "❌ Failed to create GitHub release"
    exit 1
fi

printf '%s\n' "$release_output"
echo "✅ GitHub release created successfully!"

# Display release information
echo ""
echo "🎉 Release $release_tag created successfully!"
echo "═══════════════════════════════════════════════"
echo "🌐 Release URL: https://github.com/$repo_slug/releases/tag/$release_tag"
echo "📦 Packages: $deb_count"
echo "📁 Artifacts: $(find "$artifacts_dir" -type f | wc -l)"

if [[ $deb_count -gt 0 ]]; then
    echo ""
    echo "📋 Included packages:"
    for deb_file in "$artifacts_dir"/*.deb; do
        if [[ -f "$deb_file" ]]; then
            echo "   - $(basename "$deb_file")"
        fi
    done
fi

# Clean up artifacts directory
echo ""
read -p "🧹 Clean up release artifacts directory? [Y/n]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    rm -rf "$artifacts_dir"
    echo "✅ Artifacts directory cleaned up"
else
    echo "📁 Artifacts preserved in: $artifacts_dir"
fi

echo ""
echo "🎉 Release process completed!"
echo "💡 Users can now install packages from your repository"

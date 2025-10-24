#!/usr/bin/env bash
set -euo pipefail

# publish.sh - Commit and tag version on main branch for GitHub Pages
# This script runs on the HOST where git and GitHub CLI are configured

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"
DOCS_DIR="$WORKSPACE_ROOT/docs"

echo "📤 Publishing repository to GitHub Pages..."
echo "═══════════════════════════════════════════"

# Check if we're in a git repository
if [[ ! -d "$WORKSPACE_ROOT/.git" ]]; then
    echo "❌ Error: Not in a git repository"
    echo "💡 Initialize git repository with: git init"
    exit 1
fi

# Check if docs directory exists
if [[ ! -d "$DOCS_DIR" ]]; then
    echo "❌ Error: docs directory not found"
    echo "💡 Run build.sh first to generate the documentation and repository"
    exit 1
fi

# Check if docs has content
if [[ -z "$(ls -A "$DOCS_DIR" 2>/dev/null || true)" ]]; then
    echo "❌ Error: docs directory is empty"
    echo "💡 Run build.sh to generate content"
    exit 1
fi

# Get current branch
current_branch=$(git rev-parse --abbrev-ref HEAD)
echo "📍 Current branch: $current_branch"

# Check if working directory is clean (allow docs/ changes)
if [[ -n "$(git status --porcelain | grep -v '^?? docs/' | grep -v '^M  docs/' | grep -v '^A  docs/')" ]]; then
    echo "⚠️  Warning: Working directory has uncommitted changes (excluding docs/)"
    git status --short
    echo ""
    read -p "🤔 Continue with uncommitted changes? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Publish cancelled by user"
        exit 1
    fi
fi

# Get version from git tags or prompt user
echo ""
echo "🏷️  Determining version..."

# Try to get version from environment variable
if [[ -n "${RELEASE_VERSION:-}" ]]; then
    version="$RELEASE_VERSION"
    echo "📋 Using environment version: $version"
elif [[ -n "${1:-}" ]]; then
    version="$1"
    echo "📋 Using provided version: $version"
else
    # Get latest tag
    latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    
    if [[ -n "$latest_tag" ]]; then
        echo "📋 Latest tag: $latest_tag"
        # Suggest next version
        if [[ "$latest_tag" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
            major="${BASH_REMATCH[1]}"
            minor="${BASH_REMATCH[2]}"
            patch="${BASH_REMATCH[3]}"
            next_patch="v$major.$minor.$((patch + 1))"
            echo "💡 Suggested next version: $next_patch"
        fi
    else
        echo "📋 No previous tags found"
        echo "💡 Suggested first version: v1.0.0"
    fi
    
    read -p "🔢 Enter version (e.g., v1.0.0): " version
    
    if [[ -z "$version" ]]; then
        echo "❌ Error: Version cannot be empty"
        exit 1
    fi
fi

# Validate version format
if [[ ! "$version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ Error: Invalid version format. Use format: v1.0.0 or 1.0.0"
    exit 1
fi

# Ensure version starts with 'v'
if [[ ! "$version" =~ ^v ]]; then
    version="v$version"
fi

# Check if tag already exists
if git tag -l | grep -q "^$version$"; then
    echo "❌ Error: Tag $version already exists"
    echo "💡 Choose a different version or delete the existing tag"
    exit 1
fi

echo "🎯 Publishing version: $version"

# Stage docs, mkdocs source, and configuration
echo ""
echo "📁 Staging docs directory..."
git add "$DOCS_DIR"
git add mkdocs mkdocs.yml 2>/dev/null || true
for readme_candidate in README.md Readme.md readme.md; do
    if [[ -f "$readme_candidate" ]]; then
        git add "$readme_candidate"
        break
    fi
done

# Check what we're about to commit
echo "📋 Changes to be committed:"
git diff --cached --stat

# Create commit message
commit_message="Release $version

- Updated website and APT repository
- Generated from commit $(git rev-parse --short HEAD)
- Includes $(find "$DOCS_DIR" -name "*.deb" | wc -l) packages"

if [[ -f "$DOCS_DIR/apt/SIGNED" ]]; then
    commit_message+="\n- Repository cryptographically signed"
fi

echo ""
echo "📝 Commit message:"
echo "$commit_message"

# Confirm commit
echo ""
read -p "🤔 Proceed with commit and tag? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Publish cancelled by user"
    git reset HEAD "$DOCS_DIR" 2>/dev/null || true
    exit 1
fi

# Create commit
echo "💾 Creating commit..."
if git commit -m "$commit_message"; then
    echo "✅ Commit created successfully"
    commit_hash=$(git rev-parse --short HEAD)
else
    echo "❌ Failed to create commit"
    exit 1
fi

# Create tag
echo "🏷️  Creating tag $version..."
tag_message="Release $version

This release includes:
- Updated documentation website
- APT repository with packages
- Generated on $(date -Ru)
- Commit: $commit_hash"

if git tag -a "$version" -m "$tag_message"; then
    echo "✅ Tag $version created successfully"
else
    echo "❌ Failed to create tag"
    exit 1
fi

# Check if we have a remote configured
remote_url=$(git remote get-url origin 2>/dev/null || echo "")

if [[ -z "$remote_url" ]]; then
    echo "⚠️  Warning: No git remote configured"
    echo "💡 Add remote with: git remote add origin <url>"
    echo "📋 Local changes completed successfully:"
    echo "   - Commit: $commit_hash"
    echo "   - Tag: $version"
    exit 0
fi

echo "🌐 Remote repository: $remote_url"

# Push changes
echo ""
echo "📤 Pushing changes to remote..."

# Push main branch
if git push origin "$current_branch"; then
    echo "✅ Pushed $current_branch branch"
else
    echo "❌ Failed to push $current_branch branch"
    exit 1
fi

# Push tags
if git push origin "$version"; then
    echo "✅ Pushed tag $version"
else
    echo "❌ Failed to push tag $version"
    exit 1
fi

# Check GitHub Pages configuration
echo ""
echo "🌐 Checking GitHub Pages configuration..."

# Extract repository info from remote URL
if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
    repo_owner="${BASH_REMATCH[1]}"
    repo_name="${BASH_REMATCH[2]}"
    pages_url="https://$repo_owner.github.io/$repo_name"
    
    echo "📍 Repository: $repo_owner/$repo_name"
    echo "🌐 GitHub Pages URL: $pages_url"
    echo "📦 APT Repository URL: $pages_url/apt/"
    
    # Create user instructions
    cat > "$WORKSPACE_ROOT/DEPLOYMENT.md" << EOF
# Deployment Information

## GitHub Pages
- **Website URL**: $pages_url
- **APT Repository URL**: $pages_url/apt/

## Repository Setup for Users
\`\`\`bash
# Add repository
curl -fsSL $pages_url/apt/apt-repo-pubkey.asc | sudo apt-key add -
echo "deb $pages_url/apt stable main" | sudo tee /etc/apt/sources.list.d/gh-repos.list
sudo apt update

# Install packages
sudo apt install <package-name>
\`\`\`

## Release Information
- **Version**: $version
- **Commit**: $commit_hash
- **Released**: $(date -Ru)
- **Packages**: $(find "$DOCS_DIR" -name "*.deb" | wc -l 2>/dev/null || echo "0")

## GitHub Pages Configuration
Ensure GitHub Pages is configured to serve from:
- **Source**: Deploy from a branch
- **Branch**: main
- **Folder**: /docs
EOF

    echo "📄 Created DEPLOYMENT.md with setup instructions"
    
else
    echo "⚠️  Could not parse GitHub repository information from remote URL"
fi

echo ""
echo "🎉 Publish completed successfully!"
echo "═══════════════════════════════════════"
echo "✅ Commit: $commit_hash"
echo "✅ Tag: $version"
echo "✅ Pushed to remote"
echo ""
echo "📋 Next steps:"
echo "   1. Configure GitHub Pages (if not already done):"
echo "      - Go to repository Settings → Pages"
echo "      - Set source to 'main' branch, '/docs' folder"
echo "   2. Wait for GitHub Pages deployment (usually 2-5 minutes)"
echo "   3. Optionally run release.sh to create GitHub release"
echo ""
if [[ -n "${pages_url:-}" ]]; then
    echo "🌐 Your site will be available at: $pages_url"
    echo "📦 APT repository at: $pages_url/apt/"
fi

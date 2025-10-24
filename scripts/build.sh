#!/usr/bin/env bash
set -euo pipefail

# build.sh - Main build orchestrator script
# This script runs on the HOST and executes container scripts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🚀 Starting GH-Repos build process..."
echo "════════════════════════════════════"

# Fix common permission issues when running in container
if [[ "${REMOTE_CONTAINERS:-}" == "true" ]] || [[ "${CODESPACES:-}" == "true" ]] || [[ -f "/.dockerenv" ]]; then
    echo "🔧 Ensuring proper permissions..."
    # Fix ownership of workspace files
    sudo chown -R $(id -u):$(id -g) "$WORKSPACE_ROOT" 2>/dev/null || true
    # Ensure we can write to key directories
    sudo chmod -R u+w "$WORKSPACE_ROOT" 2>/dev/null || true
fi

# Check if we're in a dev container or need to use docker
if [[ "${REMOTE_CONTAINERS:-}" == "true" ]] || [[ "${CODESPACES:-}" == "true" ]] || [[ -f "/.dockerenv" ]]; then
    echo "📦 Running inside container - executing scripts directly"
    CONTAINER_CMD=""
else
    echo "🐳 Running on host - will execute scripts in container"
    
    # Check if docker is available
    if ! command -v docker &> /dev/null; then
        echo "❌ Error: Docker is not installed or not in PATH"
        echo "💡 Please install Docker or run this script inside a dev container"
        exit 1
    fi
    
    # Check if dev container image exists or build it
    IMAGE_NAME="gh-repos-build"
    if ! docker image inspect "$IMAGE_NAME" &> /dev/null; then
        echo "🔨 Building dev container image..."
        if [[ -f "$WORKSPACE_ROOT/.devcontainer/Dockerfile" ]]; then
            docker build -t "$IMAGE_NAME" "$WORKSPACE_ROOT/.devcontainer/"
        else
            echo "❌ Error: .devcontainer/Dockerfile not found"
            echo "💡 Please set up the dev container or run inside VS Code dev container"
            exit 1
        fi
    fi
    
    # Set up container command
    CONTAINER_CMD="docker run --rm -v \"$WORKSPACE_ROOT:/workspace\" -w /workspace \"$IMAGE_NAME\""
fi

# Function to run script in container
run_in_container() {
    local script_name="$1"
    local script_path="/workspace/scripts/$script_name"
    
    echo ""
    echo "▶️  Executing $script_name..."
    echo "────────────────────────────────"
    
    if [[ -n "$CONTAINER_CMD" ]]; then
        eval "$CONTAINER_CMD bash $script_path"
    else
        bash "$WORKSPACE_ROOT/scripts/$script_name"
    fi
    
    if [[ $? -eq 0 ]]; then
        echo "✅ $script_name completed successfully"
    else
        echo "❌ $script_name failed"
        exit 1
    fi
}

# Execute build steps in order
echo "📋 Build plan:"
echo "   1. Generate website with MkDocs"
echo "   2. Build Debian packages"
echo "   3. Create APT repository structure"
echo ""

# Step 1: Generate MkDocs website
run_in_container "mkdocs.sh"

# Step 2: Build Debian packages
run_in_container "mkdebs.sh"

# Step 3: Create APT repository
run_in_container "mkrepo.sh"

echo ""
echo "🎉 Build process completed successfully!"
echo "════════════════════════════════════════"
echo "✅ Website generated in: docs/"
echo "✅ APT repository created in: docs/apt/"
echo ""
echo "📋 Next steps:"
echo "   1. Review generated files in docs/"
echo "   2. Run signrepo.sh to sign the repository (on host)"
echo "   3. Run publish.sh to commit and deploy"
echo "   4. Run release.sh to create GitHub release"
echo ""
echo "⚠️  Note: Repository is currently UNSIGNED"
echo "🔐 Run signrepo.sh on the host to sign with your GPG key"


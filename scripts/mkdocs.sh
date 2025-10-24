#!/usr/bin/env bash
set -euo pipefail

# mkdocs.sh - Generate GitHub Pages website using MkDocs
# This script runs inside the Debian 12 container

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"
DOCS_DIR="$WORKSPACE_ROOT/docs"
MKDOCS_DIR="$WORKSPACE_ROOT/mkdocs"

echo "🏗️  Generating GitHub Pages website with MkDocs..."

# Ensure we're in the workspace root
cd "$WORKSPACE_ROOT"

# Check if mkdocs.yml exists
if [[ ! -f "mkdocs.yml" ]]; then
    echo "❌ Error: mkdocs.yml not found in workspace root"
    exit 1
fi

# Check if mkdocs source directory exists
if [[ ! -d "$MKDOCS_DIR" ]]; then
    echo "❌ Error: mkdocs source directory not found at $MKDOCS_DIR"
    exit 1
fi

# Install mkdocs and dependencies if not already installed
echo "📦 Checking MkDocs installation..."

# Check if mkdocs is available in PATH or in our virtual environment
VENV_DIR="$HOME/.local/mkdocs-venv"
MKDOCS_CMD="mkdocs"

if [[ -f "$VENV_DIR/bin/mkdocs" ]]; then
    # Use virtual environment mkdocs
    MKDOCS_CMD="$VENV_DIR/bin/mkdocs"
    echo "✅ Found MkDocs in virtual environment"
elif command -v mkdocs &> /dev/null; then
    # Use system mkdocs
    echo "✅ Found MkDocs in system PATH"
else
    echo "Installing MkDocs and dependencies in virtual environment..."
    
    # Create virtual environment if it doesn't exist
    if [[ ! -d "$VENV_DIR" ]]; then
        python3 -m venv "$VENV_DIR"
        echo "📁 Created virtual environment at $VENV_DIR"
    fi
    
    # Install packages in virtual environment
    "$VENV_DIR/bin/pip" install --upgrade pip
    "$VENV_DIR/bin/pip" install mkdocs mkdocs-material pymdown-extensions
    
    # Set mkdocs command to use virtual environment
    MKDOCS_CMD="$VENV_DIR/bin/mkdocs"
    
    echo "✅ MkDocs installed successfully in virtual environment"
fi

# Clean existing docs directory (but preserve apt/ subdirectory if it exists)
echo "🧹 Cleaning docs directory (preserving apt/ if exists)..."
if [[ -d "$DOCS_DIR" ]]; then
    # Preserve apt directory if it exists
    if [[ -d "$DOCS_DIR/apt" ]]; then
        echo "💾 Preserving existing apt/ directory..."
        mv "$DOCS_DIR/apt" "$DOCS_DIR.apt.backup" 2>/dev/null || true
    fi
    
    # Try to change permissions first to handle permission issues
    echo "🔧 Adjusting permissions for cleanup..."
    sudo chown -R $(id -u):$(id -g) "$DOCS_DIR" 2>/dev/null || true
    sudo chmod -R u+w "$DOCS_DIR" 2>/dev/null || true
    find "$DOCS_DIR" -type f -not -path "*/apt/*" -exec chmod +w {} \; 2>/dev/null || true
    find "$DOCS_DIR" -type d -not -path "*/apt/*" -exec chmod +wx {} \; 2>/dev/null || true
    
    # Remove everything else (excluding apt directory if we backed it up)
    if [[ -d "$DOCS_DIR.apt.backup" ]]; then
        # Remove everything except the backup
        find "$DOCS_DIR" -mindepth 1 -maxdepth 1 -not -name "$(basename "$DOCS_DIR.apt.backup")" -exec rm -rf {} \; 2>/dev/null || {
            echo "⚠️  Some files could not be removed due to permissions. Continuing with build..."
        }
    else
        # Remove everything
        rm -rf "$DOCS_DIR"/* 2>/dev/null || {
            echo "⚠️  Some files could not be removed due to permissions. Continuing with build..."
        }
    fi
else
    mkdir -p "$DOCS_DIR"
fi

# Build the site
echo "🔨 Building MkDocs site..."

# Create a temporary build directory to avoid permission issues
TEMP_DOCS_DIR=$(mktemp -d)
echo "📁 Using temporary build directory: $TEMP_DOCS_DIR"

# Build to temporary directory first
$MKDOCS_CMD build --site-dir "$TEMP_DOCS_DIR" --clean --strict

# Move the built site to the target directory
echo "📦 Moving built site to $DOCS_DIR..."

# Ensure target directory exists
mkdir -p "$DOCS_DIR"

# Copy the built site (this will overwrite existing files)
# Ensure we have write permissions before copying
sudo chown -R $(id -u):$(id -g) "$DOCS_DIR" 2>/dev/null || true
sudo chmod -R u+w "$DOCS_DIR" 2>/dev/null || true
cp -r "$TEMP_DOCS_DIR"/* "$DOCS_DIR/" 2>/dev/null || {
    echo "⚠️  Permission issues detected, using sudo to copy..."
    sudo cp -r "$TEMP_DOCS_DIR"/* "$DOCS_DIR/"
    sudo chown -R $(id -u):$(id -g) "$DOCS_DIR"
}

# Restore apt directory if we backed it up
if [[ -d "$DOCS_DIR.apt.backup" ]]; then
    echo "🔄 Restoring APT repository..."
    mv "$DOCS_DIR.apt.backup" "$DOCS_DIR/apt"
fi

# Clean up temporary directory
rm -rf "$TEMP_DOCS_DIR"

# Verify the build
if [[ ! -f "$DOCS_DIR/index.html" ]]; then
    echo "❌ Error: MkDocs build failed - no index.html generated"
    exit 1
fi

# Create .nojekyll file to prevent GitHub Pages from processing with Jekyll
touch "$DOCS_DIR/.nojekyll"

# Display build summary
echo "✅ MkDocs build completed successfully!"
echo "📁 Generated files in: $DOCS_DIR"
echo "📊 Build summary:"
echo "   - HTML files: $(find "$DOCS_DIR" -name "*.html" | wc -l)"
echo "   - CSS files: $(find "$DOCS_DIR" -name "*.css" | wc -l)"
echo "   - JS files: $(find "$DOCS_DIR" -name "*.js" | wc -l)"

if [[ -d "$DOCS_DIR/apt" ]]; then
    echo "   - APT repo preserved: Yes"
else
    echo "   - APT repo preserved: No (will be created by mkrepo.sh)"
fi

echo "🎉 Website ready for GitHub Pages deployment!"
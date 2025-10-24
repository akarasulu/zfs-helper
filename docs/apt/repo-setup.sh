#!/bin/bash
# Repository setup script for users

REPO_URL="https://akarasulu.github.io/gh-repos/apt"
KEY_DEST="/etc/apt/trusted.gpg.d/gh-repos.asc"
LIST_DEST="/etc/apt/sources.list.d/gh-repos.list"

echo "🔧 Adding GH-Repos APT repository..."

# Check if we're on a system that supports the modern method
if [[ -d "/etc/apt/trusted.gpg.d" ]]; then
    echo "📥 Downloading and installing GPG key..."
    # Download GPG key to trusted.gpg.d (modern method)
    curl -fsSL "$REPO_URL/apt-repo-pubkey.asc" | sudo tee "$KEY_DEST" > /dev/null
    echo "✅ GPG key installed to $KEY_DEST"
else
    echo "📥 Downloading and installing GPG key (legacy method)..."
    # Fallback to apt-key for older systems
    curl -fsSL "$REPO_URL/apt-repo-pubkey.asc" | sudo apt-key add -
    echo "✅ GPG key added via apt-key"
fi

echo "📝 Adding repository to sources..."
# Add repository to sources
echo "deb $REPO_URL stable main" | sudo tee "$LIST_DEST"

echo "🔄 Updating package list..."
# Update package list
sudo apt update

echo "🎉 Repository added successfully!"
echo "📦 Install packages with: sudo apt install <package-name>"
echo "📋 Available packages: dev-tools,hello-world,mock-monitor,sys-info"

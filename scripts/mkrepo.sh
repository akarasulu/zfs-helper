#!/usr/bin/env bash
set -euo pipefail

# mkrepo.sh - Create APT repository structure under /docs/apt
# This script runs inside the Debian 12 container

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"
DOCS_DIR="$WORKSPACE_ROOT/docs"
APT_REPO_DIR="$DOCS_DIR/apt"
DEB_OUTPUT_DIR="$WORKSPACE_ROOT/debs"
KEYS_DIR="$WORKSPACE_ROOT/keys"

repo_owner=""
repo_name=""

    if [[ -n "${GITHUB_REPOSITORY:-}" && "$GITHUB_REPOSITORY" =~ ^([^/]+)/([^/]+)$ ]]; then
        repo_owner="${BASH_REMATCH[1]}"
        repo_name="${BASH_REMATCH[2]}"
    else
        origin_url=$(git -C "$WORKSPACE_ROOT" config --get remote.origin.url 2>/dev/null || echo "")
        if [[ "$origin_url" =~ ^git@github\.com:([^/]+)/(.+?)(\.git)?$ ]]; then
            repo_owner="${BASH_REMATCH[1]}"
            repo_name="${BASH_REMATCH[2]}"
        elif [[ "$origin_url" =~ ^https://github\.com/([^/]+)/(.+?)(\.git)?$ ]]; then
            repo_owner="${BASH_REMATCH[1]}"
            repo_name="${BASH_REMATCH[2]}"
        fi
    fi

config_owner=$(git -C "$WORKSPACE_ROOT" config --get gh-repos.owner 2>/dev/null || true)
config_name=$(git -C "$WORKSPACE_ROOT" config --get gh-repos.name 2>/dev/null || true)
if [[ -z "$repo_owner" && -n "$config_owner" ]]; then
    repo_owner="$config_owner"
fi
if [[ -z "$repo_name" && -n "$config_name" ]]; then
    repo_name="$config_name"
fi

mkdocs_repo_name=""
mkdocs_repo_owner=""
mkdocs_repo_title=""
if command -v python3 >/dev/null 2>&1; then
    eval "$(
        cd "$WORKSPACE_ROOT" && python3 - <<'PY'
from pathlib import Path
import re

repo_name = ""
repo_owner = ""
site_name = ""

path = Path("mkdocs.yml")
if path.exists():
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("repo_name:"):
            repo_name = line.split(":", 1)[1].strip().strip("'\"")
        elif line.startswith("site_name:"):
            site_name = line.split(":", 1)[1].strip().strip("'\"")
        elif line.startswith("repo_url:"):
            repo_url = line.split(":", 1)[1].strip().strip("'\"")
            match = re.match(r"https://github\.com/([^/]+)/([^/\s]+)", repo_url)
            if match:
                repo_owner = match.group(1)
                if not repo_name:
                    repo_name = match.group(2)

def humanize(name: str) -> str:
    parts = re.split(r"[-_]+", name)
    words = [part.capitalize() for part in parts if part]
    return " ".join(words) if words else name

preferred_title = site_name or humanize(repo_name)

print(f"mkdocs_repo_name={repo_name!r}")
print(f"mkdocs_repo_owner={repo_owner!r}")
print(f"mkdocs_repo_title={preferred_title!r}")
PY
    )"
fi

if [[ -z "$repo_owner" && -n "${mkdocs_repo_owner:-}" ]]; then
    repo_owner="$mkdocs_repo_owner"
fi
if [[ -z "$repo_name" && -n "${mkdocs_repo_name:-}" ]]; then
    repo_name="$mkdocs_repo_name"
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

if [[ -z "$repo_name" ]]; then
    repo_name="apt-repo"
fi

docs_url="https://${repo_owner}.github.io/${repo_name}"
site_label="${mkdocs_repo_title:-$repo_name}"
repo_label="${site_label} APT Repository"
apt_list_name="${repo_name}.list"
gpg_key_name="${repo_name}.asc"

echo "🏗️  Creating APT repository structure..."

# Create APT repository directories
mkdir -p "$APT_REPO_DIR"/{pool,dists/stable/{main/{binary-amd64,binary-arm64,binary-all,source}}}

# Check if we have packages to include
if [[ ! -d "$DEB_OUTPUT_DIR" ]] || [[ -z "$(ls -A "$DEB_OUTPUT_DIR"/*.deb 2>/dev/null || true)" ]]; then
    echo "❌ Error: No .deb packages found in $DEB_OUTPUT_DIR"
    echo "💡 Run mkdebs.sh first to build packages"
    exit 1
fi

# Copy .deb packages to pool directory
echo "📦 Copying packages to repository pool..."
package_count=0
declare -A package_seen=()
package_list=()
for deb_file in "$DEB_OUTPUT_DIR"/*.deb; do
    if [[ -f "$deb_file" ]]; then
        cp "$deb_file" "$APT_REPO_DIR/pool/"
        echo "   - $(basename "$deb_file")"
        package_count=$((package_count + 1))
        pkg_name=$(dpkg-deb -f "$deb_file" Package 2>/dev/null || basename "$deb_file")
        if [[ -n "$pkg_name" && -z "${package_seen[$pkg_name]:-}" ]]; then
            package_seen["$pkg_name"]=1
            package_list+=("$pkg_name")
        fi
    fi
done

echo "✅ Copied $package_count packages to repository pool"

# Copy GPG public key
echo "🔑 Adding GPG public key to repository..."
if [[ -f "$KEYS_DIR/apt-repo-pubkey.asc" ]]; then
    cp "$KEYS_DIR/apt-repo-pubkey.asc" "$APT_REPO_DIR/"
    echo "✅ GPG public key added"
else
    echo "⚠️  Warning: GPG public key not found at $KEYS_DIR/apt-repo-pubkey.asc"
    echo "💡 Users will need to manually import your key or add it later"
fi

# Create repository metadata
echo "📋 Generating repository metadata..."

# Function to create Packages file for a specific architecture
create_packages_file() {
    local arch="$1"
    local packages_dir="$APT_REPO_DIR/dists/stable/main/binary-$arch"
    local packages_file="$packages_dir/Packages"
    
    mkdir -p "$packages_dir"
    
    echo "   Creating Packages file for $arch..."
    
    # Clear the Packages file
    > "$packages_file"
    
    # Process each .deb file
    for deb_file in "$APT_REPO_DIR/pool"/*.deb; do
        if [[ -f "$deb_file" ]]; then
            # Get package architecture from the .deb file
            pkg_arch=$(dpkg-deb -f "$deb_file" Architecture)
            
            # Include package if architecture matches or is 'all'
            if [[ "$pkg_arch" == "$arch" ]] || [[ "$pkg_arch" == "all" && "$arch" == "amd64" ]]; then
                # Extract package info
                dpkg-deb -f "$deb_file" >> "$packages_file"
                
                # Add additional metadata
                filename="pool/$(basename "$deb_file")"
                size=$(stat -c%s "$deb_file")
                md5sum=$(md5sum "$deb_file" | cut -d' ' -f1)
                sha1sum=$(sha1sum "$deb_file" | cut -d' ' -f1)
                sha256sum=$(sha256sum "$deb_file" | cut -d' ' -f1)
                
                echo "Filename: $filename" >> "$packages_file"
                echo "Size: $size" >> "$packages_file"
                echo "MD5sum: $md5sum" >> "$packages_file"
                echo "SHA1: $sha1sum" >> "$packages_file"
                echo "SHA256: $sha256sum" >> "$packages_file"
                echo "" >> "$packages_file"
            fi
        fi
    done
    
    # Compress the Packages file
    gzip -c "$packages_file" > "$packages_file.gz"
    
    # Create Packages.bz2 if bzip2 is available
    if command -v bzip2 &> /dev/null; then
        bzip2 -c "$packages_file" > "$packages_file.bz2"
    fi
}

# Create Packages files for different architectures
create_packages_file "amd64"
create_packages_file "arm64"
create_packages_file "all"

# Create Release file
echo "📄 Creating Release file..."
release_file="$APT_REPO_DIR/dists/stable/Release"

cat > "$release_file" << EOF
Origin: ${repo_name}
Label: ${repo_label}
Suite: stable
Version: 1.0
Codename: stable
Date: $(date -Ru)
Architectures: amd64 arm64 all
Components: main
Description: APT repository for ${site_label} hosted on GitHub Pages
EOF

# Calculate checksums for Release file
echo "MD5Sum:" >> "$release_file"
(cd "$APT_REPO_DIR/dists/stable" && find . -type f -name "Packages*" | while read file; do
    md5=$(md5sum "$file" | cut -d' ' -f1)
    size=$(stat -c%s "$file")
    path=${file#./}
    printf " %s %7d %s\n" "$md5" "$size" "$path"
done) >> "$release_file"

echo "SHA1:" >> "$release_file"
(cd "$APT_REPO_DIR/dists/stable" && find . -type f -name "Packages*" | while read file; do
    sha1=$(sha1sum "$file" | cut -d' ' -f1)
    size=$(stat -c%s "$file")
    path=${file#./}
    printf " %s %7d %s\n" "$sha1" "$size" "$path"
done) >> "$release_file"

echo "SHA256:" >> "$release_file"
(cd "$APT_REPO_DIR/dists/stable" && find . -type f -name "Packages*" | while read file; do
    sha256=$(sha256sum "$file" | cut -d' ' -f1)
    size=$(stat -c%s "$file")
    path=${file#./}
    printf " %s %7d %s\n" "$sha256" "$size" "$path"
done) >> "$release_file"

# Create repository configuration file for users
package_summary="<package-name>"
if [[ ${#package_list[@]} -gt 0 ]]; then
    package_summary=$(IFS=', '; echo "${package_list[*]}")
fi

echo "📝 Creating repository configuration..."
cat > "$APT_REPO_DIR/repo-setup.sh" << EOF
#!/bin/bash
# Repository setup script for users

REPO_URL="${docs_url}/apt"
KEY_DEST="/etc/apt/trusted.gpg.d/${gpg_key_name}"
LIST_DEST="/etc/apt/sources.list.d/${apt_list_name}"

echo "🔧 Adding ${site_label} APT repository..."

# Check if we're on a system that supports the modern method
if [[ -d "/etc/apt/trusted.gpg.d" ]]; then
    echo "📥 Downloading and installing GPG key..."
    # Download GPG key to trusted.gpg.d (modern method)
    curl -fsSL "\$REPO_URL/apt-repo-pubkey.asc" | sudo tee "\$KEY_DEST" > /dev/null
    echo "✅ GPG key installed to \$KEY_DEST"
else
    echo "📥 Downloading and installing GPG key (legacy method)..."
    # Fallback to apt-key for older systems
    curl -fsSL "\$REPO_URL/apt-repo-pubkey.asc" | sudo apt-key add -
    echo "✅ GPG key added via apt-key"
fi

echo "📝 Adding repository to sources..."
# Add repository to sources
echo "deb \$REPO_URL stable main" | sudo tee "\$LIST_DEST"

echo "🔄 Updating package list..."
# Update package list
sudo apt update

echo "🎉 Repository added successfully!"
echo "📦 Install packages with: sudo apt install <package-name>"
echo "📋 Available packages: ${package_summary}"
EOF

chmod +x "$APT_REPO_DIR/repo-setup.sh"

# Create a simple index.html for the APT repository
cat > "$APT_REPO_DIR/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>${repo_label}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        pre { background: #f4f4f4; padding: 10px; border-radius: 5px; }
        .package { margin: 10px 0; padding: 10px; border: 1px solid #ddd; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>${repo_label}</h1>
        <p>This is an APT repository hosted on GitHub Pages for <strong>${site_label}</strong>.</p>
        
        <h2>Quick Setup</h2>
        <pre><code># Download and run setup script
curl -fsSL ${docs_url}/apt/repo-setup.sh | bash

# Or manual setup:
curl -fsSL ${docs_url}/apt/apt-repo-pubkey.asc | sudo tee /etc/apt/trusted.gpg.d/${gpg_key_name} > /dev/null
echo "deb ${docs_url}/apt stable main" | sudo tee /etc/apt/sources.list.d/${apt_list_name}
sudo apt update</code></pre>

        <h2>Available Packages</h2>
        <div id="packages">
EOF

# List available packages in the HTML
for deb_file in "$APT_REPO_DIR/pool"/*.deb; do
    if [[ -f "$deb_file" ]]; then
        pkg_name=$(dpkg-deb -f "$deb_file" Package)
        pkg_version=$(dpkg-deb -f "$deb_file" Version)
        pkg_description=$(dpkg-deb -f "$deb_file" Description || echo "No description available")
        
        cat >> "$APT_REPO_DIR/index.html" << EOF
            <div class="package">
                <h3>$pkg_name ($pkg_version)</h3>
                <p>$pkg_description</p>
                <code>sudo apt install $pkg_name</code>
            </div>
EOF
    fi
done

cat >> "$APT_REPO_DIR/index.html" << EOF
        </div>
    </div>
</body>
</html>
EOF

# Display repository summary
echo ""
echo "📊 APT Repository Summary"
echo "═════════════════════════"
echo "📍 Repository location: $APT_REPO_DIR"
echo "📦 Packages: $package_count"
echo ""
echo "📂 Repository structure:"
find "$APT_REPO_DIR" -type f | sort | sed 's|^'"$APT_REPO_DIR"'|   apt|'

echo ""
echo "✅ APT repository created successfully!"
echo "🔐 Note: Repository metadata is unsigned - run signrepo.sh on host to sign"
echo "🌐 Repository will be available at: ${docs_url}/apt/"

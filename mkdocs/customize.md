# Customization Guide

Learn how to customize GH-Repos for your specific needs, from basic configuration to advanced setups.

## Basic Customization

### Repository Information

Update the core repository details in `mkdocs.yml`:

```yaml
site_name: Your Repository Name
site_description: Your custom description
repo_url: https://github.com/your-username/your-repo
repo_name: your-repo
```

### Branding and Appearance

#### Theme Customization

Modify the Material theme settings:

```yaml
theme:
  name: material
  palette:
    primary: blue        # Your brand color
    accent: light-blue   # Accent color
  logo: assets/logo.png  # Your logo
  favicon: assets/favicon.ico
```

#### Custom CSS

Add custom styling by creating `docs/assets/stylesheets/extra.css`:

```css
:root {
  --md-primary-fg-color: #your-color;
  --md-accent-fg-color: #your-accent;
}

.md-header {
  background: linear-gradient(45deg, #your-gradient);
}
```

Then reference it in `mkdocs.yml`:

```yaml
extra_css:
  - assets/stylesheets/extra.css
```

## Package Configuration

### Package Metadata

Customize package information in each `DEBIAN/control` file:

```
Package: your-package-name
Version: 1.0.0
Section: utils
Priority: optional
Architecture: amd64
Depends: libc6 (>= 2.17), other-package
Maintainer: Your Name <your.email@example.com>
Homepage: https://your-project.com
Description: Short description
 Long description goes here.
 Multiple lines are supported.
 .
 Use dots for paragraph breaks.
```

#### Package Categories

Organize packages by section:

- `admin` - System administration utilities
- `devel` - Development tools
- `utils` - General utilities
- `net` - Network applications
- `libs` - Libraries
- `games` - Games and entertainment

### Multiple Architectures

Support different architectures by organizing packages:

```
pkgs/
├── my-tool/
│   ├── amd64/
│   │   └── DEBIAN/control  # Architecture: amd64
│   ├── arm64/
│   │   └── DEBIAN/control  # Architecture: arm64
│   └── all/
│       └── DEBIAN/control  # Architecture: all
```

## GPG Key Management

### Generate New Keys

Create a dedicated signing key:

```bash
# Generate a new GPG key
gpg --full-generate-key

# Export public key
gpg --armor --export your-key-id > keys/apt-repo-pubkey.asc

# Export private key (keep secure!)
gpg --armor --export-secret-keys your-key-id > private-key.asc
```

### Hardware Token Integration

For production environments, use a hardware token:

```bash
# List available tokens
gpg --card-status

# Import key to token
gpg --edit-key your-key-id
> keytocard
```

### Key Distribution

Make your public key easily accessible:

```bash
# Host on key servers
gpg --send-keys your-key-id

# Include in repository
cp public-key.asc keys/apt-repo-pubkey.asc
```

## Advanced Scripting

### Custom Build Scripts

Enhance `scripts/build.sh` for complex builds:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Configuration
PACKAGES_DIR="pkgs"
OUTPUT_DIR="docs/pool"
ARCHITECTURES=("amd64" "arm64" "all")

# Build each package
for pkg_dir in "$PACKAGES_DIR"/*; do
    if [[ -d "$pkg_dir" ]]; then
        echo "Building $(basename "$pkg_dir")..."
        
        # Custom build logic here
        if [[ -f "$pkg_dir/build.sh" ]]; then
            cd "$pkg_dir"
            ./build.sh
            cd - > /dev/null
        fi
        
        # Create package
        dpkg-deb --build "$pkg_dir" "$OUTPUT_DIR/"
    fi
done

# Generate repository metadata
./scripts/generate-repo.sh
```

### Automated Versioning

Implement semantic versioning:

```bash
#!/usr/bin/env bash

# Get version from git tag
VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.1.0")

# Update package versions
find pkgs -name "control" -exec sed -i "s/Version:.*/Version: $VERSION/" {} \;

echo "Updated packages to version $VERSION"
```

### Custom Signing Process

Enhance `scripts/sign.sh` with robust error handling:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="docs"
GPG_KEY_ID="${GPG_KEY_ID:-your-default-key-id}"

# Sign packages
find "$REPO_DIR/pool" -name "*.deb" | while read -r package; do
    echo "Signing $package..."
    
    # Create detached signature
    gpg --detach-sign --armor \
        --local-user "$GPG_KEY_ID" \
        --output "$package.asc" \
        "$package"
done

# Sign repository metadata
cd "$REPO_DIR"
gpg --detach-sign --armor \
    --local-user "$GPG_KEY_ID" \
    --output Release.gpg \
    Release

echo "Repository signed successfully"
```

## GitHub Actions Integration

### Automated Builds

Create `.github/workflows/build.yml`:

```yaml
name: Build and Deploy Packages

on:
  push:
    tags: ['v*']
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup environment
      run: |
        export UID=$(id -u)
        export GID=$(id -g)
    
    - name: Build packages
      run: ./scripts/build.sh
    
    - name: Sign packages
      env:
        GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
        GPG_PASSPHRASE: ${{ secrets.GPG_PASSPHRASE }}
      run: |
        echo "$GPG_PRIVATE_KEY" | gpg --import
        ./scripts/sign.sh
    
    - name: Deploy to GitHub Pages
      uses: peaceiris/actions-gh-pages@v3
      with:
        github_token: ${{ secrets.GITHUB_TOKEN }}
        publish_dir: ./docs
```

### Security Considerations

Store sensitive data in GitHub Secrets:

- `GPG_PRIVATE_KEY` - Your private GPG key
- `GPG_PASSPHRASE` - Key passphrase (if any)
- `SIGNING_TOKEN` - Hardware token PIN

## Multi-Repository Setup

### Organization Repositories

For multiple related repositories:

```
organization/
├── main-repo/          # Primary packages
├── testing-repo/       # Beta/testing packages
├── archive-repo/       # Deprecated packages
└── shared-configs/     # Common configurations
```

### Repository Inheritance

Share common configurations:

```yaml
# shared-configs/base.yml
theme:
  name: material
  palette:
    primary: blue

# main-repo/mkdocs.yml
INHERIT: ../shared-configs/base.yml
site_name: Main Repository
```

## Documentation Customization

### Custom Pages

Add specialized documentation:

```
mkdocs/
├── index.md
├── usage.md
├── design.md
├── customize.md
├── releases.md
├── api/
│   ├── index.md
│   └── reference.md
└── examples/
    ├── basic.md
    └── advanced.md
```

Update navigation in `mkdocs.yml`:

```yaml
nav:
  - Home: index.md
  - Getting Started: usage.md
  - Design: design.md
  - Customization: customize.md
  - API Reference:
    - Overview: api/index.md
    - Reference: api/reference.md
  - Examples:
    - Basic Usage: examples/basic.md
    - Advanced: examples/advanced.md
  - Releases: releases.md
```

### Extensions and Plugins

Add powerful extensions:

```yaml
markdown_extensions:
  - toc:
      permalink: true
  - admonition
  - codehilite
  - pymdownx.superfences:
      custom_fences:
        - name: mermaid
          class: mermaid
          format: !!python/name:pymdownx.superfences.fence_code_format

plugins:
  - search
  - git-revision-date-localized
  - minify:
      minify_html: true
```

## Monitoring and Analytics

### Repository Statistics

Track repository usage:

```bash
# Add to scripts/stats.sh
#!/usr/bin/env bash

echo "Repository Statistics"
echo "===================="
echo "Packages: $(find docs/pool -name '*.deb' | wc -l)"
echo "Size: $(du -sh docs/pool | cut -f1)"
echo "Last Update: $(date)"
```

### User Analytics

Add Google Analytics to track usage:

```yaml
# mkdocs.yml
extra:
  analytics:
    provider: google
    property: G-XXXXXXXXXX
```

---

With these customization options, you can adapt GH-Repos to meet your specific requirements while maintaining the core functionality and security features.

Next: Check out the [releases](releases.md) to see what's new.
# GH-Repos: GitHub Pages as APT Repositories

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub Pages](https://img.shields.io/badge/GitHub%20Pages-Enabled-brightgreen)](https://pages.github.com/)
[![Debian](https://img.shields.io/badge/Debian-12-red)](https://www.debian.org/)

Turn a GitHub repository into a GH Pages hosted mkdocs website with APT repository.

## 🎯 Overview

**GH-Repos** enables you to create and manage APT repositories using GitHub Pages with automated package building, signing, and deployment. Perfect for distributing your custom Debian packages with secure GPG signatures.

### Key Features

- 🏗️ **Automated Package Building** - Build Debian packages in containerized environments
- 🔐 **GPG Signing** - Cryptographically sign packages and repository metadata
- 📦 **GitHub Pages Hosting** - Host APT repositories on GitHub's reliable infrastructure
- 🚀 **CI/CD Integration** - Streamlined build and deployment workflows
- 🛡️ **Security First** - Hardware token support and secure key management
- 📚 **Documentation** - Guides and documentation

## 🚀 Quick Start

### Prerequisites

- **Linux environment** (required for proper user mapping)
- **Docker** with VS Code Dev Containers extension
- **GitHub account** with repository access
- **GPG key** for package signing

### 1. Setup Environment

```bash
# Export user ID for container alignment
export UID=$(id -u)
export GID=$(id -g)

# Set these to match the owner/name of your fork
FORK_OWNER=<your-account>
FORK_REPO=<your-repo-name>

# Prepare your fork with placeholder docs and a fresh public key
curl -sSL "https://raw.githubusercontent.com/${FORK_OWNER}/${FORK_REPO}/main/prepare-template.sh" | \
  bash -s -- "git@github.com:${FORK_OWNER}/${FORK_REPO}.git"

cd ${FORK_REPO}

# Open in VS Code Dev Container
code .
```

> If you omit the optional directory argument, the script uses the repository name from the URL.

### 2. Add Your Packages

```bash
# Create a new package
mkdir -p pkgs/my-awesome-tool/{DEBIAN,usr/bin}

# Create package metadata
cat > pkgs/my-awesome-tool/DEBIAN/control << EOF
Package: my-awesome-tool
Version: 1.0.0
Section: utils
Priority: optional
Architecture: all
Maintainer: Your Name <your.email@example.com>
Description: An awesome command-line tool
 Detailed description of what your tool does.
EOF

# Add your executable
echo '#!/bin/bash
echo "Hello from my awesome tool!"' > pkgs/my-awesome-tool/usr/bin/my-awesome-tool
chmod +x pkgs/my-awesome-tool/usr/bin/my-awesome-tool
```

### 3. Build and Deploy

```bash
# Build packages (runs in container)
./scripts/build.sh

# Sign repository (runs on host)
./scripts/signrepo.sh

# Publish to GitHub Pages
./scripts/publish.sh v1.0.0

# Create GitHub release
./scripts/release.sh v1.0.0
```

### 4. Configure GitHub Pages

1. Go to your repository **Settings** → **Pages**
2. Set source to **Deploy from a branch**
3. Select **main** branch and **/ docs** folder
4. Wait for deployment (2-5 minutes)

### 5. Manually Install Your Packages

```bash
# Add your repository
curl -fsSL https://YOUR_USERNAME.github.io/gh-repos/apt/apt-repo-pubkey.asc | sudo apt-key add -
echo "deb https://YOUR_USERNAME.github.io/gh-repos/apt stable main" | sudo tee /etc/apt/sources.list.d/gh-repos.list

# Update and install
sudo apt update
sudo apt install my-awesome-tool
```

Or just fire up the test vagrant guest with `vagrant up` to automatically test installing your packages.

## 📁 Project Structure

```
gh-repos/
├── 📄 README.md                    # This file
├── 📄 mkdocs.yml                   # Documentation configuration
├── 🗂️ mkdocs/                      # Documentation source
│   ├── 📄 index.md                 # Homepage
│   ├── 📄 quickstart.md            # Script-driven reset instructions
│   ├── 📄 usage.md                 # Getting started guide
│   ├── 📄 design.md                # Architecture documentation
│   ├── 📄 build.md                 # Build process details
│   ├── 📄 customize.md             # Customization guide
│   └── 📄 releases.md              # Release notes
├── 🗂️ scripts/                     # Build automation scripts
│   ├── 🔧 build.sh                 # Main build orchestrator
│   ├── 🔧 mkdocs.sh                # Generate documentation
│   ├── 🔧 mkdebs.sh                # Build Debian packages
│   ├── 🔧 mkrepo.sh                # Create APT repository
│   ├── 🔧 signrepo.sh              # GPG sign repository
│   ├── 🔧 publish.sh               # Git commit and publish
│   └── 🔧 release.sh               # Create GitHub releases
├── 🗂️ pkgs/                        # Package source directories
│   ├── 📦 hello-world/             # Example: Basic utility
│   ├── 📦 mock-monitor/            # Example: Systemd service
│   ├── 📦 dev-tools/               # Example: Multiple tools
│   ├── 📦 sys-info/                # Example: Compiled binary
│   └── 📄 README.md                # Package documentation
├── 🗂️ docs/                        # Generated GitHub Pages content
│   ├── 🌐 index.html               # Website homepage
│   ├── 🗂️ apt/                     # APT repository
│   │   ├── 🔑 apt-repo-pubkey.asc  # GPG public key
│   │   ├── 🗂️ dists/               # Repository metadata
│   │   └── 🗂️ pool/                # Package files (.deb)
│   └── 🗂️ assets/                  # Website assets
├── 🗂️ templates/                  # Placeholder templates used by prepare-template.sh
│   └── 🗂️ mkdocs/                  # MkDocs placeholder content
├── 🗂️ keys/                        # GPG public keys
└── 🗂️ .devcontainer/               # Development container config
    ├── 📄 devcontainer.json        # Container configuration
    └── 📄 Dockerfile               # Container image definition
```

## 🛠️ Build System Architecture

### Container Operations (Secure & Isolated)
1. **`mkdocs.sh`** - Generate documentation website
2. **`mkdebs.sh`** - Build Debian packages from sources
3. **`mkrepo.sh`** - Create APT repository structure

### Host Operations (Access to Secrets)
4. **`signrepo.sh`** - GPG sign packages and repository
5. **`publish.sh`** - Git commit, tag, and push changes
6. **`release.sh`** - Create GitHub releases with artifacts

### Security Philosophy
> **"Just do what you need inside and GTFO"**
> 
> No GPG keys, hardware tokens, or secrets enter the container. All security-sensitive operations happen on the trusted host environment.

## 📦 Example Packages

The repository includes 4 example packages demonstrating different Debian packaging features:

| Package | Description | Features Demonstrated |
|---------|-------------|----------------------|
| **hello-world** | Simple greeting utility | Basic package structure, minimal dependencies |
| **mock-monitor** | System monitoring service | Systemd integration, maintainer scripts, service lifecycle |
| **dev-tools** | Development utilities | Configuration files, multiple binaries, user setup |
| **sys-info** | System information tool | Compiled C binary, build process, manual pages |

### Package Features Showcased

- ✅ **Basic packaging** - File installation and metadata
- ✅ **Service management** - Systemd service integration
- ✅ **Configuration handling** - Conffiles and user setup
- ✅ **Build processes** - Source code compilation
- ✅ **Dependencies** - Package relationships and suggestions
- ✅ **Architecture support** - `all` vs architecture-specific packages
- ✅ **Maintainer scripts** - Installation and removal logic
- ✅ **Documentation** - Manual pages and help systems

## 🔧 Advanced Configuration

### Custom GPG Key

```bash
# Generate dedicated signing key
gpg --full-generate-key

# Export public key for repository
gpg --armor --export YOUR_KEY_ID > keys/apt-repo-pubkey.asc

# Set environment variable for scripts
export GPG_KEY_ID=YOUR_KEY_ID
```

### Hardware Token Support

```bash
# Works with YubiKeys and other PKCS#11 tokens
# No special container configuration needed
./scripts/signrepo.sh  # Will use hardware token if configured
```

### GitHub Actions Integration

```yaml
# .github/workflows/build.yml
name: Build and Deploy
on:
  push:
    tags: ['v*']

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - name: Build and deploy
      env:
        GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
      run: |
        export UID=$(id -u) GID=$(id -g)
        ./scripts/build.sh
        ./scripts/signrepo.sh
        ./scripts/publish.sh
```

## 🌐 Use Cases

### Personal Package Distribution
Host your custom tools and utilities with professional infrastructure.

### Organization Package Management
Distribute internal tools to your team with proper version control.

### Open Source Projects
Provide easy installation for users through familiar APT commands.

### Software Vendors
Deliver commercial software with trusted package management.

## 📚 Documentation

- **[Getting Started](https://username.github.io/gh-repos/usage/)** - Complete setup guide
- **[Build Process](https://username.github.io/gh-repos/build/)** - Technical details
- **[Customization](https://username.github.io/gh-repos/customize/)** - Advanced configuration
- **[Design & Architecture](https://username.github.io/gh-repos/design/)** - System overview

## 🤝 Contributing

We welcome contributions! Here's how to get started:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/gh-repos.git
cd gh-repos

# Set up development environment
export UID=$(id -u) GID=$(id -g)
code .  # Open in VS Code with Dev Containers
```

### Testing Your Changes

```bash
# Test package building
./scripts/mkdebs.sh

# Test documentation generation
./scripts/mkdocs.sh

# Test full build process
./scripts/build.sh
```

## 📋 Requirements

### System Requirements
- **Operating System**: Linux (Ubuntu 20.04+, Debian 11+)
- **Memory**: 2GB RAM minimum for container operations
- **Storage**: 10GB free space for builds and artifacts
- **Architecture**: x86_64 or ARM64

### Software Dependencies
- **Docker** 20.10+ (for containerized builds)
- **VS Code** with Dev Containers extension (recommended)
- **Git** 2.20+ (for version control)
- **GPG** 2.2+ (for package signing)
- **GitHub CLI** (optional, for release automation)

### Supported Platforms

| Platform | Build Support | Host Support | Notes |
|----------|---------------|--------------|-------|
| **Linux** | ✅ Full | ✅ Full | Recommended platform |
| **macOS** | ⚠️ Limited | ⚠️ Limited | User mapping limitations |
| **Windows** | ❌ None | ❌ None | Not supported |

## 🔍 Troubleshooting

### Common Issues

**Permission Issues**
```bash
# Ensure UID/GID are exported
export UID=$(id -u) GID=$(id -g)
```

**GPG Signing Failures**
```bash
# Verify key exists
gpg --list-secret-keys
# Set key ID
export GPG_KEY_ID=YOUR_KEY_ID
```

**Build Failures**
```bash
# Check package structure
find pkgs/ -name "control" -exec head -5 {} \;
# Validate control files
./scripts/mkdebs.sh
```

**GitHub Pages Not Updating**
- Ensure `/docs` folder is committed
- Check GitHub Pages source configuration
- Verify GitHub Pages is enabled in repository settings

### Getting Help

- 📖 **Documentation**: Comprehensive guides at [your-repo-url]
- 🐛 **Issues**: Report bugs on [GitHub Issues](https://github.com/akarasulu/gh-repos/issues)
- 💬 **Discussions**: Ask questions in [GitHub Discussions](https://github.com/akarasulu/gh-repos/discussions)

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Debian Project** - For the excellent package management system
- **GitHub** - For providing free hosting via GitHub Pages
- **Material for MkDocs** - For the beautiful documentation theme
- **Dev Containers** - For consistent development environments

## 🔗 Related Projects

- **[Debian Packaging Guide](https://www.debian.org/doc/manuals/debmake-doc/)** - Official Debian packaging documentation
- **[GitHub Pages](https://pages.github.com/)** - Free hosting for open source projects
- **[APT Repository Format](https://wiki.debian.org/RepositoryFormat)** - Technical specification

---

<div align="center">

**Built with ❤️ for the open source community**

[⭐ Star this repository](https://github.com/akarasulu/gh-repos) if you find it useful!

</div>

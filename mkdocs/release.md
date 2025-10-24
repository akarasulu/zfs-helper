# Release Process

ZFS Helper uses the gh-repos approach for building and releasing Debian packages through a devcontainer-based build system.

## Overview

Releases are built using GitHub Actions and a Debian 12 devcontainer that includes all necessary packaging tools. The process creates signed Debian packages and publishes them to an APT repository hosted on GitHub Pages.

## Prerequisites

- **Git**: Configured for signed tags (GPG key available)
- **GPG**: For signing releases and repository metadata
- **GitHub CLI** (optional): For release automation
- **Access**: Push access to the repository

## Build Process

The build system uses several scripts in the `scripts/` directory:

### Local Development Build

```bash
# Build packages in devcontainer
./scripts/build.sh

# Build Debian packages
./scripts/mkdebs.sh

# Build documentation
./scripts/mkdocs.sh

# Create APT repository
./scripts/mkrepo.sh

# Sign repository metadata
./scripts/signrepo.sh

# Publish to GitHub Pages
./scripts/publish.sh
```

### Release Workflow

```bash
# Create and publish a full release
./scripts/release.sh 1.0.0 release-notes.md
```

This script:
1. Creates a GPG-signed annotated git tag
2. Builds Debian packages in the devcontainer
3. Generates documentation with MkDocs
4. Creates the APT repository structure
5. Signs repository metadata with GPG
6. Creates a GitHub release with artifacts
7. Publishes to GitHub Pages (gh-pages branch)

## Package Versions

Packages are versioned using semantic versioning (MAJOR.MINOR.PATCH):
- **MAJOR**: Breaking changes to API or configuration
- **MINOR**: New features, backward-compatible changes
- **PATCH**: Bug fixes and maintenance updates

## APT Repository Structure

The published APT repository is available at:
```
https://akarasulu.github.io/zfs-helper/apt/
```

Repository structure:
```
docs/apt/
├── apt-repo-pubkey.asc     # GPG public key for verification
├── repo-setup.sh           # Installation script for users
├── dists/stable/           # Repository metadata
│   ├── InRelease           # Signed repository info
│   ├── Release             # Repository metadata
│   ├── Release.gpg         # GPG signature
│   └── main/               # Package indices
└── pool/                   # Package files (.deb)
```

## Security

### Package Signing
- All packages are built in a clean devcontainer environment
- Repository metadata is signed with GPG
- Users verify packages using the published GPG key

### GPG Key Management
- Public key is distributed via the repository
- Private key is used only for signing releases
- Key fingerprint should be published separately for verification

## User Installation

End users install packages using:

```bash
# Add repository and install
curl -fsSL https://akarasulu.github.io/zfs-helper/apt/repo-setup.sh | sudo bash
sudo apt update
sudo apt install zfs-helper zfs-helper-client
```

## Troubleshooting Releases

### Build Failures
- Check devcontainer configuration
- Verify all dependencies are available in Debian 12
- Review build logs in GitHub Actions

### Signing Issues
- Ensure GPG key is available and not expired
- Check GPG agent configuration
- Verify key has appropriate permissions

### Repository Publishing
- Confirm GitHub Pages is enabled
- Check gh-pages branch exists and is up to date
- Verify repository structure matches expected format

## Development Workflow

1. **Feature Development**: Work on feature branches
2. **Testing**: Validate changes in devcontainer
3. **Documentation**: Update relevant documentation
4. **Package Testing**: Build and test packages locally
5. **Release**: Tag and publish when ready

The gh-repos approach ensures consistent, reproducible builds and simplifies the release process compared to the previous manual script-based approach.
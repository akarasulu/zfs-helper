# Build Process

The GH-Repos build system uses a series of scripts to handle different aspects of package creation, repository generation, and deployment. The process is split between container-based operations (for consistent builds) and host operations (for secure signing and publishing).

## Container Scripts (Run inside Debian 12 container)

Different scripts handle steps in the build process within the Debian 12 container:

### 1. **mkdocs.sh** - Website Generation
Uses MkDocs to generate the GitHub Pages website in `/docs`:
- Builds documentation from `mkdocs/` directory
- Preserves existing APT repository if present
- Creates `.nojekyll` file for GitHub Pages
- Validates build output and provides summary

### 2. **mkdebs.sh** - Package Creation  
Creates Debian packages from sources under `/pkgs/<pkg_name>`:
- Scans for package directories with `DEBIAN/control` files
- Validates package metadata (Package, Version, Architecture fields)
- Runs custom build scripts if present (`build.sh`)
- Creates `.deb` packages with proper permissions
- Verifies package integrity after creation
- Outputs packages to `debs/` directory

### 3. **mkrepo.sh** - Repository Structure
Creates the APT repository structure under `/docs/apt`:
- Copies GPG public key (`keys/apt-repo-pubkey.asc`) into repository
- Copies all build artifacts (`.deb` packages) to repository pool
- Generates repository metadata (Packages, Release files)
- Creates compressed package indices (`.gz`, `.bz2`)
- Supports multiple architectures (amd64, arm64, all)
- Generates user-friendly setup scripts and documentation

## Host Scripts (Run outside container)

These scripts execute outside of the container on the host where security credentials are properly configured:

### 4. **signrepo.sh** - GPG Signing
Cryptographically signs repository files and artifacts:
- Signs individual `.deb` packages with detached signatures
- Signs repository Release file (creates `Release.gpg` and `InRelease`)
- Auto-detects or uses specified GPG key
- Verifies all signatures after creation
- Creates verification scripts for users
- Supports hardware tokens and secure key management

### 5. **publish.sh** - Git Publishing
Commits and tags version on main branch for GitHub Pages deployment:
- Stages `docs/` directory changes
- Creates descriptive commit with build information
- Creates annotated git tag for version
- Pushes changes to remote repository
- Generates deployment documentation
- Provides GitHub Pages configuration instructions

### 6. **release.sh** - GitHub Releases
Creates GitHub releases with downloadable artifacts using GitHub CLI:
- Packages all `.deb` files as release assets
- Generates SHA256 checksums for verification
- Creates installation scripts for users
- Builds comprehensive release notes with package details
- Archives complete APT repository structure
- Supports GPG signing of checksums

## Build Orchestration

### **build.sh** - Main Orchestrator
The primary build script that coordinates the entire process:
- Detects container vs host environment
- Executes container scripts in proper sequence
- Handles Docker container management if needed
- Provides comprehensive build reporting
- Validates each step before proceeding

## Security Architecture

No git commits, tags, or GPG signing occurs within the container environment. The Debian package infrastructure builds artifacts using tools designed for Debian within a clean Debian environment. Container script invocations occur when `build.sh` runs on the host and fires up the container.

The commit, tag, and APT repository files' GPG signing, releasing, and publishing to GitHub occurs outside of the container where the user may be using a hardware token and/or has everything securely setup and configured within a trusted environment (i.e., logged into GitHub CLI).

### Why This Separation?

> **Security Philosophy**: Don't mess with passing around hardware tokens, or passing sockets, and building the GPG stack inside a container. Don't install and move keys around into the container. Just do what you need inside and GTFO.

This approach:
- ✅ **Keeps secrets secure** - No keys in containers
- ✅ **Supports hardware tokens** - Works with YubiKeys, etc.
- ✅ **Simplifies container** - Clean, minimal build environment  
- ✅ **Enables host tools** - Use configured git, GPG, GitHub CLI
- ✅ **Maintains isolation** - Build environment stays clean

## Typical Workflow

```bash
# 1. Build everything (container operations)
./scripts/build.sh

# 2. Sign repository (host operation)  
./scripts/signrepo.sh

# 3. Publish to GitHub Pages (host operation)
./scripts/publish.sh v1.0.0

# 4. Create GitHub release (host operation)
./scripts/release.sh v1.0.0
```

## Script Dependencies

### Container Requirements
- Debian 12 environment
- `mkdocs` and Python packages
- `dpkg-deb` and Debian build tools
- Standard Unix utilities (`find`, `tar`, `gzip`, etc.)

### Host Requirements  
- Git (for version control operations)
- GPG (for signing operations)
- GitHub CLI (`gh`) for release creation
- Docker (if not running in dev container)

## Error Handling

All scripts include comprehensive error handling:
- **Exit on error** (`set -euo pipefail`)
- **Input validation** with helpful error messages
- **Dependency checking** before operations
- **Cleanup on failure** where appropriate
- **Detailed logging** for troubleshooting

## Customization

Scripts support customization through environment variables:
- `GPG_KEY_ID` - Specify signing key
- `RELEASE_VERSION` - Override version detection
- `GPG_SIGN_CONFIRM` - Skip signing confirmation
- `GITHUB_REPOSITORY` - Repository identification

This modular approach ensures each script has a single responsibility while maintaining the overall security and reliability of the build process.

# Example Debian Packages

This directory contains example Debian packages that demonstrate different packaging features and best practices. These packages are designed to showcase the capabilities of the GH-Repos APT repository system.

## Package Overview

### 1. `hello-world` - Basic Vanilla Package
**Architecture:** `all`  
**Section:** `utils`  
**Version:** `1.0.0`

A minimal example demonstrating the simplest possible Debian package structure.

**Features demonstrated:**
- Basic package structure with `DEBIAN/control`
- Simple shell script installation
- Architecture-independent package (`all`)
- Minimal dependencies

**What it installs:**
- `/usr/bin/hello-world` - Simple greeting script

**Usage:**
```bash
sudo apt install hello-world
hello-world
```

### 2. `mock-monitor` - Systemd Service Package
**Architecture:** `all`  
**Section:** `admin`  
**Version:** `2.1.3`

Demonstrates a complete systemd service installation with proper lifecycle management.

**Features demonstrated:**
- Systemd service file installation
- Maintainer scripts (`postinst`, `prerm`, `postrm`)
- Service lifecycle management
- Log directory creation
- Dependency handling (`systemd`)

**What it installs:**
- `/usr/bin/mock-monitor` - Monitoring daemon
- `/etc/systemd/system/mock-monitor.service` - Service definition
- `/var/log/mock-monitor/` - Log directory

**Usage:**
```bash
sudo apt install mock-monitor
sudo systemctl start mock-monitor
sudo systemctl status mock-monitor
sudo journalctl -u mock-monitor -f
```

### 3. `dev-tools` - Configuration Files Package
**Architecture:** `all`  
**Section:** `devel`  
**Version:** `1.5.2`

Shows complex package with configuration files, multiple utilities, and user setup.

**Features demonstrated:**
- Configuration files management (`conffiles`)
- Multiple executable scripts
- User directory initialization
- Dependencies and suggestions
- Shared data files installation

**What it installs:**
- `/usr/bin/dev-init` - Project initialization tool
- `/usr/bin/git-helper` - Git utility scripts
- `/etc/dev-tools/config.conf` - System configuration
- `/etc/dev-tools/templates.conf` - Project templates
- `/usr/share/dev-tools/` - Shared data files

**Usage:**
```bash
sudo apt install dev-tools
dev-init my-project
dev-init -t python my-python-app
git-helper cleanup
git-helper stats
```

### 4. `sys-info` - Compiled Binary Package
**Architecture:** `amd64`  
**Section:** `admin`  
**Version:** `3.2.1`

Demonstrates building and packaging compiled binaries with build process.

**Features demonstrated:**
- Architecture-specific binary (`amd64`)
- Build script with compilation
- C source code compilation
- Manual page installation
- Runtime dependencies (`libc6`)

**What it installs:**
- `/usr/bin/sys-info` - System information utility
- `/usr/share/man/man1/sys-info.1` - Manual page

**Build process:**
```bash
# Source code in src/sys-info.c
# Compiled during package build
gcc -o sys-info src/sys-info.c -std=c99 -Wall -Wextra
```

**Usage:**
```bash
sudo apt install sys-info
sys-info
sys-info -q
man sys-info
```

## Package Structure

Each package follows the standard Debian package structure:

```
pkgs/<package-name>/
├── DEBIAN/
│   ├── control          # Package metadata (required)
│   ├── conffiles        # Configuration files list
│   ├── postinst         # Post-installation script
│   ├── prerm            # Pre-removal script
│   └── postrm           # Post-removal script
├── usr/
│   ├── bin/             # Executable files
│   └── share/           # Shared data files
├── etc/                 # Configuration files
├── var/                 # Variable data files
├── src/                 # Source code (if applicable)
└── build.sh             # Build script (if needed)
```

## Building the Packages

To build all packages:

```bash
# Build packages in container
./scripts/build.sh

# Or build individual packages
./scripts/mkdebs.sh
```

## Testing the Packages

After building, you can test individual packages:

```bash
# Install a specific package
sudo dpkg -i debs/hello-world_1.0.0_all.deb

# Remove a package
sudo dpkg -r hello-world

# Check package information
dpkg -l | grep hello-world
dpkg -L hello-world
```

## Repository Features Demonstrated

These packages collectively demonstrate:

1. **Basic packaging** - Simple file installation
2. **Service management** - Systemd integration
3. **Configuration handling** - Conffiles and user setup
4. **Build processes** - Source compilation
5. **Dependencies** - Package relationships
6. **Architecture handling** - `all` vs `amd64` packages
7. **Maintainer scripts** - Installation/removal logic
8. **Documentation** - Manual pages
9. **Security** - Proper permissions and service hardening

## Customization

You can modify these packages or create new ones by:

1. Copying an existing package structure
2. Updating the `DEBIAN/control` file with your metadata
3. Adding your files to the appropriate directories
4. Creating maintainer scripts if needed
5. Adding build scripts for compilation if required

## Repository Integration

When these packages are built and added to the APT repository, users can:

```bash
# Add the repository
curl -fsSL https://username.github.io/repo/apt/apt-repo-pubkey.asc | sudo apt-key add -
echo "deb https://username.github.io/repo/apt stable main" | sudo tee /etc/apt/sources.list.d/gh-repos.list

# Update and install
sudo apt update
sudo apt install hello-world mock-monitor dev-tools sys-info
```

This demonstrates a complete end-to-end package distribution system using GitHub Pages and APT repository infrastructure.
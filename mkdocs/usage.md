# Getting Started

This guide will walk you through setting up your own APT repository using GitHub Pages.

## Prerequisites

Before you begin, ensure you have:

- **Linux environment** (required for proper user mapping)
- **Docker** installed and running
- **VS Code** with Dev Containers extension
- **GPG key** for package signing
- **GitHub account** with repository access

!!! warning "Important: User Environment Setup"
    The devcontainer used to build packages will NOT align with your user unless you export UID/GID before launching VS Code:
    ```bash
    export UID=$(id -u)
    export GID=$(id -g)
    ```

## Step-by-Step Setup

### 1. Fork and Clone Repository

```bash
# Fork the repository on GitHub first, then clone your fork
git clone https://github.com/YOUR_USERNAME/gh-repos.git
cd gh-repos
```

### 2. Configure Environment

Export your user ID and group ID to ensure proper container permissions:

```bash
export UID=$(id -u)
export GID=$(id -g)
```

Open the project in VS Code:

```bash
code .
```

When prompted, reopen in the Dev Container.

### 3. Add Your Packages

Create package sources under the `pkgs/` directory:

```bash
mkdir -p pkgs/my-package
cd pkgs/my-package
```

Each package should include:
- **Source code** or binary files
- **DEBIAN/control** file with package metadata
- **Build scripts** (if applicable)

#### Example Package Structure

```
pkgs/
└── my-awesome-tool/
    ├── DEBIAN/
    │   ├── control
    │   ├── postinst
    │   └── prerm
    ├── usr/
    │   └── bin/
    │       └── my-awesome-tool
    └── build.sh
```

#### Example DEBIAN/control File

```
Package: my-awesome-tool
Version: 1.0.0
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Your Name <your.email@example.com>
Description: An awesome command-line tool
 This package provides an amazing command-line tool
 that does incredible things for your system.
```

### 4. Configure Repository Information

Update the MkDocs configuration and documentation:

1. **Edit `mkdocs.yml`** - Update site name, description, and repository URL
2. **Update documentation** - Customize the content in `mkdocs/` directory
3. **Configure GPG keys** - Place your public key in `keys/` directory

### 5. Build and Test

Build your packages locally:

```bash
./scripts/build.sh
```

Test the APT repository:

```bash
./scripts/publish.sh
```

### 6. Deploy to GitHub Pages

1. **Commit your changes**:
   ```bash
   git add .
   git commit -m "Add my packages and customize repository"
   git push origin main
   ```

2. **Configure GitHub Pages**:
   - Go to your repository settings
   - Navigate to "Pages" section
   - Set source to "Deploy from a branch"
   - Select "main" branch and "/docs" folder

3. **Create a release**:
   ```bash
   git tag -a v1.0.0 -m "Release version 1.0.0"
   git push origin v1.0.0
   ```

### 7. Verify Your Repository

Once GitHub Pages is deployed, your APT repository will be available at:
```
https://YOUR_USERNAME.github.io/gh-repos/
```

Users can add your repository with:

```bash
# Add your repository
curl -fsSL https://YOUR_USERNAME.github.io/gh-repos/keys/apt-repo-pubkey.asc | sudo apt-key add -
echo "deb https://YOUR_USERNAME.github.io/gh-repos/ ./" | sudo tee /etc/apt/sources.list.d/your-repo.list

# Update and install
sudo apt update
sudo apt install your-package-name
```

## Next Steps

- **[Customize](customize.md)** your repository further
- **[Review the design](design.md)** to understand the architecture
- **[Check releases](releases.md)** for updates and changelog

## Troubleshooting

### Permission Issues
Ensure UID/GID are exported before starting VS Code.

### GPG Signing Failures
Verify your GPG key is properly configured and accessible within the container.

### Build Failures
Check package structure and DEBIAN/control file syntax.

### GitHub Pages Not Updating
Ensure the `/docs` folder is committed and GitHub Pages source is correctly configured.

---

Need help? Check our [Design documentation](design.md) or open an issue on GitHub.

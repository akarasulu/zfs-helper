#!/usr/bin/env bash
set -euo pipefail

# mkdebs.sh - Create Debian packages from sources under /pkgs/<pkg_name>
# This script runs inside the Debian 12 container

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"
PKGS_DIR="$WORKSPACE_ROOT/pkgs"
BUILD_DIR="$WORKSPACE_ROOT/build"
DEB_OUTPUT_DIR="$WORKSPACE_ROOT/debs"

echo "📦 Building Debian packages..."

# Create necessary directories
mkdir -p "$BUILD_DIR" "$DEB_OUTPUT_DIR" 2>/dev/null || {
    echo "🔧 Permission issue detected, using sudo to create directories..."
    sudo mkdir -p "$BUILD_DIR" "$DEB_OUTPUT_DIR"
    sudo chown -R $(id -u):$(id -g) "$BUILD_DIR" "$DEB_OUTPUT_DIR"
}

# Check if pkgs directory exists
if [[ ! -d "$PKGS_DIR" ]]; then
    echo "❌ Error: pkgs directory not found at $PKGS_DIR"
    echo "💡 Create package sources under pkgs/<package_name>/"
    exit 1
fi

# Check for packages to build
package_dirs=($(find "$PKGS_DIR" -mindepth 1 -maxdepth 1 -type d))

if [[ ${#package_dirs[@]} -eq 0 ]]; then
    echo "❌ No packages found in $PKGS_DIR"
    echo "💡 Create package directories under pkgs/ with DEBIAN/control files"
    exit 1
fi

echo "📋 Found ${#package_dirs[@]} package(s) to build:"
for pkg_dir in "${package_dirs[@]}"; do
    echo "   - $(basename "$pkg_dir")"
done

# Build each package
built_packages=0
failed_packages=0

for pkg_dir in "${package_dirs[@]}"; do
    pkg_name=$(basename "$pkg_dir")
    echo ""
    echo "🔨 Building package: $pkg_name"
    echo "────────────────────────────────────"
    
    # Check for DEBIAN/control file
    if [[ ! -f "$pkg_dir/DEBIAN/control" ]]; then
        echo "❌ Error: Missing DEBIAN/control file in $pkg_name"
        echo "💡 Create $pkg_dir/DEBIAN/control with package metadata"
        failed_packages=$((failed_packages + 1))
        continue
    fi
    
    # Validate control file
    echo "📋 Validating package metadata..."
    if ! grep -q "^Package:" "$pkg_dir/DEBIAN/control"; then
        echo "❌ Error: Missing 'Package:' field in control file"
        failed_packages=$((failed_packages + 1))
        continue
    fi
    
    if ! grep -q "^Version:" "$pkg_dir/DEBIAN/control"; then
        echo "❌ Error: Missing 'Version:' field in control file"
        failed_packages=$((failed_packages + 1))
        continue
    fi
    
    if ! grep -q "^Architecture:" "$pkg_dir/DEBIAN/control"; then
        echo "❌ Error: Missing 'Architecture:' field in control file"
        failed_packages=$((failed_packages + 1))
        continue
    fi
    
    # Extract package info from control file
    package_name=$(grep "^Package:" "$pkg_dir/DEBIAN/control" | cut -d: -f2 | xargs)
    version=$(grep "^Version:" "$pkg_dir/DEBIAN/control" | cut -d: -f2 | xargs)
    architecture=$(grep "^Architecture:" "$pkg_dir/DEBIAN/control" | cut -d: -f2 | xargs)
    
    echo "   Package: $package_name"
    echo "   Version: $version"
    echo "   Architecture: $architecture"
    
    # Create build workspace
    build_workspace="$BUILD_DIR/$pkg_name"
    rm -rf "$build_workspace" 2>/dev/null || sudo rm -rf "$build_workspace" 2>/dev/null || true
    mkdir -p "$build_workspace" 2>/dev/null || {
        sudo mkdir -p "$build_workspace"
        sudo chown -R $(id -u):$(id -g) "$build_workspace"
    }
    
    # Copy package contents to build workspace
    echo "📂 Copying package contents..."
    cp -r "$pkg_dir"/* "$build_workspace/"
    
    # Set proper permissions for DEBIAN scripts
    if [[ -d "$build_workspace/DEBIAN" ]]; then
        find "$build_workspace/DEBIAN" -type f -name "postinst" -o -name "prerm" -o -name "postrm" -o -name "preinst" | \
            xargs -r chmod 755
    fi
    
    # Run custom build script if it exists
    if [[ -f "$build_workspace/build.sh" ]]; then
        echo "🔧 Running custom build script..."
        cd "$build_workspace"
        chmod +x build.sh
        if ./build.sh; then
            echo "✅ Custom build script completed successfully"
        else
            echo "❌ Custom build script failed"
            failed_packages=$((failed_packages + 1))
            continue
        fi
        cd "$WORKSPACE_ROOT"
        
        # Remove build script from package
        rm -f "$build_workspace/build.sh"
    fi
    
    # Create the .deb package
    deb_filename="${package_name}_${version}_${architecture}.deb"
    echo "📦 Creating package: $deb_filename"
    
    if dpkg-deb --build "$build_workspace" "$DEB_OUTPUT_DIR/$deb_filename"; then
        echo "✅ Package built successfully: $deb_filename"
        
        # Verify the package
        echo "🔍 Verifying package..."
        if dpkg-deb --info "$DEB_OUTPUT_DIR/$deb_filename" > /dev/null; then
            echo "✅ Package verification passed"
            built_packages=$((built_packages + 1))
        else
            echo "❌ Package verification failed"
            rm -f "$DEB_OUTPUT_DIR/$deb_filename"
            failed_packages=$((failed_packages + 1))
        fi
    else
        echo "❌ Failed to build package: $pkg_name"
        failed_packages=$((failed_packages + 1))
    fi
done

# Clean up build directory
rm -rf "$BUILD_DIR" 2>/dev/null || {
    echo "🔧 Permission issue removing build directory, using sudo..."
    sudo rm -rf "$BUILD_DIR" 2>/dev/null || true
}

echo ""
echo "📊 Build Summary"
echo "════════════════"
echo "✅ Successfully built: $built_packages packages"
echo "❌ Failed builds: $failed_packages packages"

if [[ $built_packages -gt 0 ]]; then
    echo ""
    echo "📦 Built packages:"
    ls -la "$DEB_OUTPUT_DIR"/*.deb 2>/dev/null || echo "   (none)"
    
    echo ""
    echo "🎉 Packages ready for repository creation!"
    echo "💡 Next step: Run mkrepo.sh to create APT repository"
else
    echo ""
    echo "❌ No packages were built successfully"
    exit 1
fi

if [[ $failed_packages -gt 0 ]]; then
    exit 1
fi

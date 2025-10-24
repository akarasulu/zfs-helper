#!/usr/bin/env bash
set -euo pipefail

# mkdebs.sh - Create Debian packages from sources under /pkgs/<pkg_name>
# This script runs inside the Debian 12 container

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "${SCRIPT_DIR}")"
PKGS_DIR="${WORKSPACE_ROOT}/pkgs"
BUILD_DIR="${WORKSPACE_ROOT}/build"
DEB_OUTPUT_DIR="${WORKSPACE_ROOT}/debs"

echo "📦 Building Debian packages..."

# Create necessary directories
mkdir -p "${BUILD_DIR}" "${DEB_OUTPUT_DIR}" 2>/dev/null || {
    echo "🔧 Permission issue detected, using sudo to create directories..."
    sudo mkdir -p "${BUILD_DIR}" "${DEB_OUTPUT_DIR}"
    sudo chown -R $(id -u):$(id -g) "${BUILD_DIR}" "${DEB_OUTPUT_DIR}"
}

# Clean up orphaned .deb files and signatures
echo "🧹 Cleaning up orphaned package files..."
if [[ -d "${DEB_OUTPUT_DIR}" ]]; then
    # Get list of valid package names from pkgs directory
    valid_pkg_names=()
    if [[ -d "${PKGS_DIR}" ]]; then
        while IFS= read -r -d '' pkg_dir; do
            pkg_name=$(basename "${pkg_dir}")
            if [[ -f "${pkg_dir}/DEBIAN/control" ]]; then
                valid_pkg_names+=("${pkg_name}")
            fi
        done < <(find "${PKGS_DIR}" -mindepth 1 -maxdepth 1 -type d -print0)
    fi
    
    # Remove .deb files that don't have corresponding source directories
    removed_count=0
    for deb_file in "${DEB_OUTPUT_DIR}"/*.deb; do
        [[ -f "${deb_file}" ]] || continue
        
        deb_basename=$(basename "${deb_file}")
        # Extract package name from filename (remove version and architecture)
        pkg_name=$(echo "${deb_basename}" | sed 's/_[^_]*_[^_]*\.deb$//')
        
        # Check if this package is in our valid list
        is_valid=false
        for valid_pkg in "${valid_pkg_names[@]}"; do
            if [[ "${pkg_name}" == "${valid_pkg}" ]]; then
                is_valid=true
                break
            fi
        done
        
        if [[ "${is_valid}" == false ]]; then
            echo "   🗑️  Removing orphaned: ${deb_basename}"
            rm -f "${deb_file}" 2>/dev/null || sudo rm -f "${deb_file}"
            removed_count=$((${removed_count} + 1))
        fi
    done
    
    # Also clean up from docs/apt/pool if it exists
    if [[ -d "${WORKSPACE_ROOT}/docs/apt/pool" ]]; then
        for deb_file in "${WORKSPACE_ROOT}/docs/apt/pool"/*.deb; do
            [[ -f "${deb_file}" ]] || continue
            
            deb_basename=$(basename "${deb_file}")
            pkg_name=$(echo "${deb_basename}" | sed 's/_[^_]*_[^_]*\.deb$//')
            
            is_valid=false
            for valid_pkg in "${valid_pkg_names[@]}"; do
                if [[ "${pkg_name}" == "${valid_pkg}" ]]; then
                    is_valid=true
                    break
                fi
            done
            
            if [[ "${is_valid}" == false ]]; then
                echo "   🗑️  Removing from repository: ${deb_basename}"
                rm -f "${deb_file}" "${deb_file}.asc" 2>/dev/null || sudo rm -f "${deb_file}" "${deb_file}.asc"
                removed_count=$((${removed_count} + 1))
            fi
        done
    fi
    
    if [[ ${removed_count} -gt 0 ]]; then
        echo "   ✅ Removed ${removed_count} orphaned package file(s)"
    else
        echo "   ✅ No orphaned files found"
    fi
fi

# Check if pkgs directory exists
if [[ ! -d "${PKGS_DIR}" ]]; then
    echo "❌ Error: pkgs directory not found at ${PKGS_DIR}"
    echo "💡 Create package sources under pkgs/<package_name>/"
    exit 1
fi

# Check for packages to build
package_dirs=($(find "${PKGS_DIR}" -mindepth 1 -maxdepth 1 -type d))

if [[ ${#package_dirs[@]} -eq 0 ]]; then
    echo "❌ No packages found in ${PKGS_DIR}"
    echo "💡 Create package directories under pkgs/ with DEBIAN/control files"
    exit 1
fi

# Count valid packages (those with DEBIAN/control files)
valid_packages=0
for pkg_dir in "${package_dirs[@]}"; do
    if [[ -f "${pkg_dir}/DEBIAN/control" ]]; then
        valid_packages=$((${valid_packages} + 1))
    fi
done

if [[ ${valid_packages} -eq 0 ]]; then
    echo "❌ No valid packages found (missing DEBIAN/control files)"
    echo "💡 Create DEBIAN/control files in package directories"
    exit 1
fi

echo "📋 Found ${valid_packages} valid package(s) to build:"
for pkg_dir in "${package_dirs[@]}"; do
    if [[ -f "${pkg_dir}/DEBIAN/control" ]]; then
        echo "   ✓ $(basename "${pkg_dir}")"
    else
        echo "   ⚠ $(basename "${pkg_dir}") (skipped - no DEBIAN/control)"
    fi
done

# Build each package
built_packages=0
failed_packages=0

for pkg_dir in "${package_dirs[@]}"; do
    pkg_name=$(basename "${pkg_dir}")
    echo ""
    echo "🔨 Building package: ${pkg_name}"
    echo "────────────────────────────────────"
    
    # Check for DEBIAN/control file
    if [[ ! -f "${pkg_dir}/DEBIAN/control" ]]; then
        echo "⚠️  Skipping ${pkg_name}: No DEBIAN/control file found"
        continue
    fi
    
    # Validate control file
    echo "📋 Validating package metadata..."
    if ! grep -q "^Package:" "${pkg_dir}/DEBIAN/control"; then
        echo "❌ Error: Missing 'Package:' field in control file"
        failed_packages=$((failed_packages + 1))
        continue
    fi
    
    if ! grep -q "^Version:" "${pkg_dir}/DEBIAN/control"; then
        echo "❌ Error: Missing 'Version:' field in control file"
        failed_packages=$((failed_packages + 1))
        continue
    fi
    
    if ! grep -q "^Architecture:" "${pkg_dir}/DEBIAN/control"; then
        echo "❌ Error: Missing 'Architecture:' field in control file"
        failed_packages=$((failed_packages + 1))
        continue
    fi
    
    # Extract package info from control file
    package_name=$(grep "^Package:" "${pkg_dir}/DEBIAN/control" | cut -d: -f2 | xargs)
    version=$(grep "^Version:" "${pkg_dir}/DEBIAN/control" | cut -d: -f2 | xargs)
    architecture=$(grep "^Architecture:" "${pkg_dir}/DEBIAN/control" | cut -d: -f2 | xargs)
    
    echo "   Package: ${package_name}"
    echo "   Version: ${version}"
    echo "   Architecture: ${architecture}"
    
    # Create build workspace
    build_workspace="${BUILD_DIR}/${pkg_name}"
    rm -rf "${build_workspace}" 2>/dev/null || sudo rm -rf "${build_workspace}" 2>/dev/null || true
    mkdir -p "${build_workspace}" 2>/dev/null || {
        sudo mkdir -p "${build_workspace}"
        sudo chown -R $(id -u):$(id -g) "${build_workspace}"
    }
    
    # Copy package contents to build workspace
    echo "📂 Copying package contents..."
    cp -r "${pkg_dir}"/* "${build_workspace}/"
    
    # Set proper permissions for DEBIAN scripts
    if [[ -d "${build_workspace}/DEBIAN" ]]; then
        find "${build_workspace}/DEBIAN" -type f -name "postinst" -o -name "prerm" -o -name "postrm" -o -name "preinst" | \
            xargs -r chmod 755
    fi
    
    # Run custom build script if it exists
    if [[ -f "${build_workspace}/build.sh" ]]; then
        echo "🔧 Running custom build script..."
        cd "${build_workspace}"
        chmod +x build.sh
        if ./build.sh; then
            echo "✅ Custom build script completed successfully"
        else
            echo "❌ Custom build script failed"
            failed_packages=$((failed_packages + 1))
            continue
        fi
        cd "${WORKSPACE_ROOT}"
        
        # Remove build script from package
        rm -f "${build_workspace}/build.sh"
    fi
    
    # Create the .deb package
    deb_filename="${package_name}_${version}_${architecture}.deb"
    echo "📦 Creating package: ${deb_filename}"
    
    if dpkg-deb --build "${build_workspace}" "${DEB_OUTPUT_DIR}/${deb_filename}"; then
        echo "✅ Package built successfully: ${deb_filename}"
        
        # Verify the package
        echo "🔍 Verifying package..."
        if dpkg-deb --info "${DEB_OUTPUT_DIR}/${deb_filename}" > /dev/null; then
            echo "✅ Package verification passed"
            built_packages=$((built_packages + 1))
        else
            echo "❌ Package verification failed"
            rm -f "${DEB_OUTPUT_DIR}/${deb_filename}"
            failed_packages=$((failed_packages + 1))
        fi
    else
        echo "❌ Failed to build package: ${pkg_name}"
        failed_packages=$((failed_packages + 1))
    fi
done

# Clean up build directory
rm -rf "${BUILD_DIR}" 2>/dev/null || {
    echo "🔧 Permission issue removing build directory, using sudo..."
    sudo rm -rf "${BUILD_DIR}" 2>/dev/null || true
}

echo ""
echo "📊 Build Summary"
echo "════════════════"
echo "✅ Successfully built: ${built_packages} packages"
echo "❌ Failed builds: ${failed_packages} packages"

if [[ ${built_packages} -gt 0 ]]; then
    echo ""
    echo "📦 Built packages:"
    ls -la "${DEB_OUTPUT_DIR}"/*.deb 2>/dev/null || echo "   (none)"
    
    echo ""
    echo "🎉 Packages ready for repository creation!"
    echo "💡 Next step: Run mkrepo.sh to create APT repository"
else
    echo ""
    echo "❌ No packages were built successfully"
    exit 1
fi

if [[ ${failed_packages} -gt 0 ]]; then
    exit 1
fi

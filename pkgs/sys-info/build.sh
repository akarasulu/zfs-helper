#!/bin/bash
# Build script for sys-info package

set -e

echo "🔨 Building sys-info from source..."

# Check if we have the source file
if [[ ! -f "src/sys-info.c" ]]; then
    echo "❌ Source file src/sys-info.c not found"
    exit 1
fi

# Create build directory
mkdir -p build

# Compile the program
echo "Compiling sys-info.c..."
gcc -o build/sys-info src/sys-info.c -std=c99 -Wall -Wextra

# Copy binary to installation directory
echo "Installing binary..."
cp build/sys-info usr/bin/

# Make sure it's executable
chmod 755 usr/bin/sys-info

echo "✅ Build completed successfully!"
echo "Binary location: usr/bin/sys-info"
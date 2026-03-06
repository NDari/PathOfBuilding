#!/bin/bash
# cspell:words LÖVE APPIMAGE appimage
# Build Path of Building for Linux using extracted LÖVE runtime
# Output: Builds/PathOfBuilding/ with launcher script + LÖVE runtime + game data
#
# Uses the UNFUSED layout (matching CI): love/ directory on disk, LÖVE binary
# runs with "love-runtime/love love/" so love.filesystem.getSource() returns
# the love/ directory path (sibling of src/).
#
# Usage: ./build-app-linux.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_DIR/Builds"
DIST_DIR="$BUILD_DIR/PathOfBuilding"
LOVE_VERSION="11.5"
LOVE_APPIMAGE_URL="https://github.com/love2d/love/releases/download/${LOVE_VERSION}/love-${LOVE_VERSION}-x86_64.AppImage"
LOVE_APPIMAGE="$BUILD_DIR/love-${LOVE_VERSION}.AppImage"
LOVE_EXTRACTED="$BUILD_DIR/love-${LOVE_VERSION}-extracted"

echo "=== Building Path of Building (Linux) ==="
echo "Repository: $REPO_DIR"
echo "Output:     $DIST_DIR"
echo ""

# Create build directory
mkdir -p "$BUILD_DIR"

# Download LÖVE AppImage if not already cached
if [ -f "$LOVE_APPIMAGE" ]; then
	echo "Using cached LÖVE AppImage: $LOVE_APPIMAGE"
else
	echo "Downloading LÖVE ${LOVE_VERSION} AppImage..."
	curl -L -o "$LOVE_APPIMAGE" "$LOVE_APPIMAGE_URL"
	chmod +x "$LOVE_APPIMAGE"
	echo "Downloaded."
fi

# Extract AppImage if not already cached
if [ -d "$LOVE_EXTRACTED" ]; then
	echo "Using cached extracted LÖVE runtime: $LOVE_EXTRACTED"
else
	echo "Extracting LÖVE AppImage..."
	cd "$BUILD_DIR"
	"$LOVE_APPIMAGE" --appimage-extract > /dev/null 2>&1
	mv squashfs-root "$LOVE_EXTRACTED"
	cd "$REPO_DIR"
	echo "Extracted."
fi

# Clean previous build
if [ -d "$DIST_DIR" ]; then
	echo "Cleaning previous build..."
	rm -rf "$DIST_DIR"
fi
mkdir -p "$DIST_DIR/love-runtime"
mkdir -p "$DIST_DIR/love"
mkdir -p "$DIST_DIR/src"
mkdir -p "$DIST_DIR/runtime"

# LÖVE runtime (binary + shared libs)
echo "Copying LÖVE runtime..."
cp "$LOVE_EXTRACTED/bin/love" "$DIST_DIR/love-runtime/love"
chmod +x "$DIST_DIR/love-runtime/love"
cp -r "$LOVE_EXTRACTED/lib" "$DIST_DIR/love-runtime/lib"

# Game directory (love/) — on disk, auto-updatable
echo "Copying love/ game directory..."
cp "$SCRIPT_DIR/main.lua" "$SCRIPT_DIR/conf.lua" "$DIST_DIR/love/"
cp -r "$SCRIPT_DIR/shim" "$DIST_DIR/love/shim"
cp -r "$SCRIPT_DIR/lib" "$DIST_DIR/love/lib"
if [ -d "$SCRIPT_DIR/fonts" ]; then
	cp -r "$SCRIPT_DIR/fonts" "$DIST_DIR/love/fonts"
fi

# PoB source and data
echo "Copying game data..."
cp -r "$REPO_DIR/src" "$DIST_DIR/src"
mkdir -p "$DIST_DIR/runtime/lua"
cp -r "$REPO_DIR/runtime/lua" "$DIST_DIR/runtime/lua"

# Manifest (into src/ where UpdateCheck.lua expects it)
if [ -f "$REPO_DIR/manifest.xml" ]; then
	cp "$REPO_DIR/manifest.xml" "$DIST_DIR/src/manifest.xml"
fi

# Default part files
for f in changelog.txt help.txt LICENSE.md; do
	[ -f "$REPO_DIR/$f" ] && cp "$REPO_DIR/$f" "$DIST_DIR/src/$f"
done

# License at top level
if [ -f "$REPO_DIR/LICENSE.md" ]; then
	cp "$REPO_DIR/LICENSE.md" "$DIST_DIR/"
fi

# Create launcher script (unfused: passes love/ directory as argument)
cat > "$DIST_DIR/LOVE-PathOfBuilding" << 'LAUNCHER'
#!/bin/bash
# Path of Building launcher
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$SCRIPT_DIR/love-runtime/lib:$LD_LIBRARY_PATH"
exec "$SCRIPT_DIR/love-runtime/love" "$SCRIPT_DIR/love" "$@"
LAUNCHER
chmod +x "$DIST_DIR/LOVE-PathOfBuilding"

echo ""
echo "=== Build complete ==="
echo "Run with: $DIST_DIR/LOVE-PathOfBuilding"

#!/bin/bash
# cspell:words LÖVE
# Build Path of Building for macOS using the LÖVE runtime
# Output: Builds/PathOfBuilding/ with launcher script + LÖVE runtime + game data
#
# Uses the UNFUSED layout (matching CI): love/ directory on disk, LÖVE binary
# runs with "love.app/Contents/MacOS/love love/" so love.filesystem.getSource()
# returns the love/ directory path (sibling of src/).
#
# Usage: ./love/build-app-macos.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_DIR/Builds"
DIST_DIR="$BUILD_DIR/PathOfBuilding"
LOVE_VERSION="11.5"
LOVE_ZIP_URL="https://github.com/love2d/love/releases/download/${LOVE_VERSION}/love-${LOVE_VERSION}-macos.zip"
LOVE_ZIP="$BUILD_DIR/love-${LOVE_VERSION}-macos.zip"
LOVE_APP="$BUILD_DIR/love-${LOVE_VERSION}.app"

echo "=== Building Path of Building (macOS) ==="
echo "Repository: $REPO_DIR"
echo "Output:     $DIST_DIR"
echo ""

mkdir -p "$BUILD_DIR"

# Download LÖVE zip if not already cached
if [ -f "$LOVE_ZIP" ]; then
	echo "Using cached LÖVE zip: $LOVE_ZIP"
else
	echo "Downloading LÖVE ${LOVE_VERSION} macOS..."
	curl -L -o "$LOVE_ZIP" "$LOVE_ZIP_URL"
	echo "Downloaded."
fi

# Extract love.app if not already cached
if [ -d "$LOVE_APP" ]; then
	echo "Using cached LÖVE app: $LOVE_APP"
else
	echo "Extracting LÖVE app..."
	cd "$BUILD_DIR"
	unzip -q "$LOVE_ZIP"
	mv love.app "$LOVE_APP"
	cd "$REPO_DIR"
	echo "Extracted."
fi

# Clean previous build
if [ -d "$DIST_DIR" ]; then
	echo "Cleaning previous build..."
	rm -rf "$DIST_DIR"
fi
mkdir -p "$DIST_DIR/love"
mkdir -p "$DIST_DIR/src"
mkdir -p "$DIST_DIR/runtime"

# LÖVE runtime (intact app bundle — binary uses @rpath Frameworks inside it)
echo "Copying LÖVE runtime..."
cp -r "$LOVE_APP" "$DIST_DIR/love.app"
chmod +x "$DIST_DIR/love.app/Contents/MacOS/love"

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
cp -r "$REPO_DIR/src/." "$DIST_DIR/src/"
mkdir -p "$DIST_DIR/runtime/lua"
cp -r "$REPO_DIR/runtime/lua/." "$DIST_DIR/runtime/lua/"

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

# Create launcher script
cat > "$DIST_DIR/PathOfBuilding" << 'LAUNCHER'
#!/bin/bash
# Path of Building launcher
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/love.app/Contents/MacOS/love" "$SCRIPT_DIR/love" "$@"
LAUNCHER
chmod +x "$DIST_DIR/PathOfBuilding"

echo ""
echo "=== Build complete ==="
echo "Run with: $DIST_DIR/PathOfBuilding"

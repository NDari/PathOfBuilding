#!/bin/bash
# Build Path of Building for Linux using extracted LÖVE runtime
# Output: Builds/PathOfBuilding/ with launcher script + LÖVE runtime + game data
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
mkdir -p "$DIST_DIR/runtime"

# Create .love file (zip of love/ directory, excluding build/launch scripts)
echo "Creating .love file..."
LOVE_FILE="$BUILD_DIR/PathOfBuilding.love"
(cd "$SCRIPT_DIR" && zip -9 -r "$LOVE_FILE" . \
	-x "run.sh" -x "run.bat" -x "build-app-linux.sh" -x "build-app-windows.bat" -x "scripts/*")

# Copy extracted LÖVE shared libraries
echo "Copying LÖVE runtime..."
mkdir -p "$DIST_DIR/love-runtime"
cp -r "$LOVE_EXTRACTED/lib" "$DIST_DIR/love-runtime/lib"

# Fuse: concatenate the love binary + .love into a single executable at the top level.
# This must live alongside src/, lib/, runtime/ so that love.filesystem.getSource()
# returns a path whose parent directory contains those siblings.
echo "Fusing binary..."
cat "$LOVE_EXTRACTED/bin/love" "$LOVE_FILE" > "$DIST_DIR/pob-love"
chmod +x "$DIST_DIR/pob-love"

# Copy game data
echo "Copying game data..."
cp -r "$REPO_DIR/src" "$DIST_DIR/src"
# Copy manifest and default part files for auto-updates
if [ -f "$REPO_DIR/manifest.xml" ]; then
	cp "$REPO_DIR/manifest.xml" "$DIST_DIR/src/manifest.xml"
fi
for f in changelog.txt help.txt LICENSE.md; do
	[ -f "$REPO_DIR/$f" ] && cp "$REPO_DIR/$f" "$DIST_DIR/src/$f"
done
cp -r "$REPO_DIR/runtime/lua" "$DIST_DIR/runtime/lua"
cp -r "$SCRIPT_DIR/lib" "$DIST_DIR/lib"

# Copy license
if [ -f "$REPO_DIR/LICENSE.md" ]; then
	cp "$REPO_DIR/LICENSE.md" "$DIST_DIR/"
fi

# Create launcher script
cat > "$DIST_DIR/LOVE-PathOfBuilding" << 'LAUNCHER'
#!/bin/bash
# Path of Building launcher
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$SCRIPT_DIR/love-runtime/lib:$LD_LIBRARY_PATH"
exec "$SCRIPT_DIR/pob-love" "$@"
LAUNCHER
chmod +x "$DIST_DIR/LOVE-PathOfBuilding"

# Clean up intermediate .love file
rm -f "$LOVE_FILE"

echo ""
echo "=== Build complete ==="
echo "Run with: $DIST_DIR/LOVE-PathOfBuilding"

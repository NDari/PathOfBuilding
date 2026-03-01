#!/bin/bash
# Convert WebP images in TreeData to PNG for LÖVE compatibility
# Requires: dwebp (from libwebp-tools / webp package)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TREE_DIR="$SCRIPT_DIR/../../src/TreeData"

if ! command -v dwebp &> /dev/null; then
	echo "Error: dwebp not found. Install libwebp-tools."
	echo "  Arch: pacman -S libwebp"
	echo "  Debian/Ubuntu: apt install webp"
	exit 1
fi

count=0
find "$TREE_DIR" -name "*.webp" | while read -r webp; do
	png="${webp%.webp}.png"
	if [ ! -f "$png" ]; then
		echo "Converting: $webp → $png"
		dwebp "$webp" -o "$png"
		count=$((count + 1))
	fi
done

echo "Done. Converted $count files."

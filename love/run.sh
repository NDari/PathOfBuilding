#!/bin/bash
# Launch Path of Building using LÖVE
# Usage: ./run.sh [/path/to/love]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOVE_BIN="${1:-love}"

# Check LÖVE is available
if ! command -v "$LOVE_BIN" &> /dev/null; then
	echo "Error: LÖVE binary not found. Install LÖVE 11.5+ or pass the path as an argument."
	echo "  Arch Linux:  pacman -S love"
	echo "  Ubuntu/Debian: See https://love2d.org/wiki/Getting_Started"
	echo "  Or: $0 /path/to/love"
	exit 1
fi

# Check LÖVE version
LOVE_VER=$("$LOVE_BIN" --version 2>&1 | grep -oP '\d+\.\d+' | head -1)
LOVE_MAJOR=$(echo "$LOVE_VER" | cut -d. -f1)
if [ "$LOVE_MAJOR" -lt 11 ] 2>/dev/null; then
	echo "Warning: LÖVE version $LOVE_VER detected. LÖVE 11.5+ is recommended."
fi

# Check for fonts, download if missing
if [ ! -f "$SCRIPT_DIR/fonts/FontinSmallCaps.ttf" ]; then
	echo "Fonts not found. Please place TTF fonts in $SCRIPT_DIR/fonts/"
	echo "Required:"
	echo "  - FontinSmallCaps.ttf (Fontin SmallCaps)"
	echo "  - BitstreamVeraSansMono.ttf (Bitstream Vera Sans Mono)"
	echo ""
	echo "Bitstream Vera Sans Mono can be installed from your system packages:"
	echo "  Arch: pacman -S ttf-bitstream-vera"
	echo "  Debian/Ubuntu: apt install fonts-dejavu-core"
	echo ""
	echo "Fontin SmallCaps is available from exljbris Font Foundry (free for personal use)."
	echo "Attempting to find system fonts as fallback..."

	# Try to find system fonts
	VERA=$(find /usr/share/fonts -name "VeraMono.ttf" 2>/dev/null | head -1)
	if [ -n "$VERA" ]; then
		ln -sf "$VERA" "$SCRIPT_DIR/fonts/BitstreamVeraSansMono.ttf"
		echo "  Linked $VERA"
	fi

	FONTIN=$(find /usr/share/fonts -iname "*fontin*smallcaps*" -name "*.ttf" 2>/dev/null | head -1)
	if [ -n "$FONTIN" ]; then
		ln -sf "$FONTIN" "$SCRIPT_DIR/fonts/FontinSmallCaps.ttf"
		echo "  Linked $FONTIN"
	elif [ -z "$FONTIN" ]; then
		# Use Liberation Sans as a fallback for the variable-width font
		LIBERATION=$(find /usr/share/fonts -name "LiberationSans-Regular.ttf" 2>/dev/null | head -1)
		if [ -n "$LIBERATION" ]; then
			ln -sf "$LIBERATION" "$SCRIPT_DIR/fonts/FontinSmallCaps.ttf"
			echo "  Linked $LIBERATION as FontinSmallCaps fallback"
		fi
	fi
fi

# Create lib directory if it doesn't exist
mkdir -p "$SCRIPT_DIR/lib"

echo "Starting Path of Building..."
cd "$SCRIPT_DIR"
exec "$LOVE_BIN" .

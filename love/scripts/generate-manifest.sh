#!/bin/bash
# cspell:words LÖVE
# Generate a LÖVE-specific manifest.xml for auto-updates.
# Runs the upstream update_manifest.py tool to regenerate SHA1 hashes,
# then patches Source URLs to point at this fork and adds branch="dev"
# to the Version element so UpdateCheck.lua works unmodified.
#
# Usage: ./love/scripts/generate-manifest.sh
# Idempotent — safe to run multiple times.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_DIR"

# Detect GitHub owner/repo from git remote
REMOTE_URL="$(git remote get-url origin 2>/dev/null || echo "")"
if [ -z "$REMOTE_URL" ]; then
	echo "Error: No git remote 'origin' found"
	exit 1
fi

# Extract owner/repo from HTTPS or SSH URL
# Handles: https://github.com/owner/repo.git, git@github.com:owner/repo.git
OWNER_REPO="$(echo "$REMOTE_URL" | sed -E 's#.*github\.com[:/]##' | sed 's/\.git$//')"
if [ -z "$OWNER_REPO" ] || [ "$OWNER_REPO" = "$REMOTE_URL" ]; then
	echo "Error: Could not parse GitHub owner/repo from remote URL: $REMOTE_URL"
	exit 1
fi

echo "Repository: $OWNER_REPO"
echo "Generating manifest..."

# Run upstream manifest tool to regenerate SHA1 hashes
python3 update_manifest.py --in-place

# Replace upstream Source URLs with fork URLs
UPSTREAM_BASE="https://raw.githubusercontent.com/PathOfBuildingCommunity/PathOfBuilding/"
FORK_BASE="https://raw.githubusercontent.com/${OWNER_REPO}/"
sed -i "s|${UPSTREAM_BASE}|${FORK_BASE}|g" manifest.xml

# Strip runtime entries (SimpleGraphic fonts, Windows DLLs) — not used by LÖVE
sed -i '/part="runtime"/d' manifest.xml

# Add branch="dev" to the Version element (idempotent)
# Matches <Version number="X.Y.Z" /> or <Version number="X.Y.Z" branch="..." />
sed -i -E 's|<Version number="([^"]+)"( branch="[^"]+")? />|<Version number="\1" branch="dev" />|' manifest.xml

echo "Done. manifest.xml updated for ${OWNER_REPO} (branch=dev)"

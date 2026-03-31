#!/bin/bash
# sync-upstream.sh
# Automates the repetitive task of rebasing on upstream/master and
# resolving the complex/noisy conflicts in manifest.xml and ModCache.lua

set -e

# 1. Fetch latest upstream
echo "--- Fetching upstream/master ---"
git fetch upstream master

# 2. Start the rebase
echo "--- Starting rebase onto upstream/master ---"
# We use -Xours here because during a rebase, 'ours' is the upstream branch 
# and 'theirs' is your work being re-applied. Confusing, but that's Git rebase.
if ! git rebase upstream/master; then
    echo "--- Conflict detected. Automating resolution for known files ---"
    
    # Always take upstream's ModCache (it's auto-generated anyway)
    if git status | grep -q "src/Data/ModCache.lua"; then
        echo "--- Resolving ModCache.lua (taking upstream) ---"
        git checkout --ours src/Data/ModCache.lua
        git add src/Data/ModCache.lua
    fi

    # Handle manifest.xml
    if git status | grep -q "manifest.xml"; then
        echo "--- Attempting intelligent merge of manifest.xml ---"
        # 1. Save your 'love' files and source to a temp file
        git show HEAD:manifest.xml | grep -E 'part="love"|<Source part="love"' > .love_parts.tmp || true
        
        # 2. Checkout upstream version
        git checkout --ours manifest.xml
        
        # 3. Inject your love parts before the closing tag if they aren't there
        if ! grep -q 'part="love"' manifest.xml; then
            sed -i '/<\/PoBVersion>/i \' manifest.xml
            sed -i '/<\/PoBVersion>/e cat .love_parts.tmp' manifest.xml
        fi
        rm -f .love_parts.tmp
        git add manifest.xml
    fi

    echo "--- Remaining conflicts (if any): ---"
    git status --short | grep "^UU"
    
    echo "--- After fixing remaining conflicts, run: git rebase --continue ---"
fi

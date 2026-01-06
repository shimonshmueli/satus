#!/bin/bash
set -e

SATUS_DIR="../Satus"

echo "Syncing changes to $SATUS_DIR..."

# 1. Preserve .git
if [ -d "$SATUS_DIR/.git" ]; then
    echo "Preserving .git directory..."
    mv "$SATUS_DIR/.git" "../Satus_git_temp"
fi

# 2. Clean Satus directory (to remove old AppLibrary folder)
rm -rf "$SATUS_DIR"/*

# 3. Copy new content
# Exclude .git and build artifacts from source
rsync -av --exclude '.git' --exclude '.build' --exclude '*.xcodeproj' . "$SATUS_DIR/"

# 4. Restore .git
if [ -d "../Satus_git_temp" ]; then
    mv "../Satus_git_temp" "$SATUS_DIR/.git"
fi

# 5. Git Commit & Push
cd "$SATUS_DIR"
git add .
git commit -m "Rename project structure to Satus"
git push origin main

echo "Done! Satus repo updated."

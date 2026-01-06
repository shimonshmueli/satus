#!/bin/bash
set -e

# Navigate to the Satus folder (sibling directory)
cd ../Satus

echo "Initializing Git in $(pwd)..."

# Initialize Git
git init

# Ensure .gitignore is respected
if [ -f .gitignore ]; then
    echo ".gitignore found."
else
    echo "Creating .gitignore..."
    echo ".DS_Store" > .gitignore
    echo ".build/" >> .gitignore
    echo "*.xcodeproj" >> .gitignore
fi

# Add all files
git add .

# Limit to one commit if already committed, or commit generic
if ! git diff-index --quiet HEAD --; then
    echo "Committing..."
    git commit -m "Initial release of Satus"
else
    echo "Nothing to commit or already committed."
fi

# Branch
git branch -M main

# Remote
echo "Setting remote..."
# Remove if exists to be safe
git remote remove origin 2>/dev/null || true
git remote add origin https://github.com/shimonshmueli/satusapp

# Push
echo "Pushing to GitHub..."
git push -u origin main

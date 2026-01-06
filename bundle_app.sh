#!/bin/bash
set -e

# 0. Quit Existing App
echo "Quitting Satus if running..."
pkill -x "Satus" || true
pkill -x "AppLibrary" || true # Cleanup old name too
sleep 1

# 1. Build
echo "Building Satus..."
swift build -c release

# 2. Bundle Structure
APP_NAME="Satus.app"
mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Resources"

# Copy binary (Note: Product name in Package.swift is now Satus)
cp .build/release/Satus "$APP_NAME/Contents/MacOS/Satus"

# 4. Create Info.plist
# 4. Copy Info.plist
echo "Copying Info.plist..."
cp Sources/Satus/Info.plist "$APP_NAME/Contents/Info.plist"

# 5. Sign (Ad-hoc)
echo "Signing Satus..."
codesign --force --deep --sign - "$APP_NAME"
echo "App signed."

# 6. Install
INSTALL_DIR="$HOME/Applications"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME"
mv "$APP_NAME" "$INSTALL_DIR/"

echo "App installed successfully at $INSTALL_DIR/$APP_NAME"
echo "You can now run it from your Applications folder."

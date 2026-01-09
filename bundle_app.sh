#!/bin/bash
set -e

# Defaults
BUILD_MODE="debug"
BUNDLE_ID_SUFFIX=".dev"
DO_CLEAN=false

# 0. Parse Arguments
for arg in "$@"
do
    case $arg in
        --release)
            BUILD_MODE="release"
            BUNDLE_ID_SUFFIX=""
            echo "📣 Switching to RELEASE mode"
            ;;
        --clean|--virgin)
            DO_CLEAN=true
            echo "🧹 Virgin Mode enabled: Cleaning local data..."
            ;;
    esac
done

if [[ "$BUILD_MODE" == "debug" ]]; then
    echo "🔧 Defaulting to DEBUG mode (Use --release for production)"
fi
    
# 0.1 Clean if requested
if [ "$DO_CLEAN" = true ]; then
    echo "💥 Resetting to VIRGIN STATE..."
    rm -f ~/Library/Application\ Support/AppLibrary/user_prefs_dev.json
    rm -f ~/Library/Application\ Support/AppLibrary/user_prefs_v2.json
    # com.shimonshmueli.Satus
    defaults delete com.shimonshmueli.Satus 2>/dev/null || echo "   (No defaults found for com.shimonshmueli.Satus)"
    echo "✅ Clean complete."
fi

# 0. Quit Existing App
echo "Quitting Satus if running..."
pkill -x "Satus" || true
pkill -x "AppLibrary" || true # Cleanup old name too
sleep 1

# 1. Build
echo "Building Satus ($BUILD_MODE)..."
swift build -c "$BUILD_MODE"

# 2. Bundle Structure
APP_NAME="Satus.app"
mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Resources"

# 3. Copy binary
echo "Copying binary from .build/$BUILD_MODE/..."
cp ".build/$BUILD_MODE/Satus" "$APP_NAME/Contents/MacOS/Satus"

# 4. Copy and Modify Info.plist
echo "Copying and Updating Info.plist..."
cp Sources/Satus/Info.plist "$APP_NAME/Contents/Info.plist"

# 4.1 Copy App Icon
if [ -f "Sources/Satus/Resources/AppIcon.icns" ]; then
    echo "Copying App Icon..."
    cp "Sources/Satus/Resources/AppIcon.icns" "$APP_NAME/Contents/Resources/AppIcon.icns"
fi

if [[ -n "$BUNDLE_ID_SUFFIX" ]]; then
    # Update Bundle ID for isolation (Requires plutil)
    ORIGINAL_ID=$(defaults read "$(pwd)/Sources/Satus/Info.plist" CFBundleIdentifier)
    NEW_ID="${ORIGINAL_ID}${BUNDLE_ID_SUFFIX}"
    plutil -replace CFBundleIdentifier -string "$NEW_ID" "$APP_NAME/Contents/Info.plist"
    echo "✅ Updated Bundle ID to $NEW_ID"
else
    echo "✅ Using default Bundle ID (Production)"
fi

# 5. Sign (Ad-hoc)
echo "Signing Satus..."
codesign --force --deep --sign - "$APP_NAME"
echo "App signed."

# 6. Install
INSTALL_DIR="$HOME/Applications"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME"
mv "$APP_NAME" "$INSTALL_DIR/"

echo "App ($BUILD_MODE) installed successfully at $INSTALL_DIR/$APP_NAME"
echo "You can now run it from your Applications folder."

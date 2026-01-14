#!/bin/bash
set -e

APP_NAME="Satus"
# Default to Development
SIGNING_IDENTITY="Apple Development"
TEAM_ID="7H7A38V8CV" # Default Team ID
IS_RELEASE=false

# Parse Arguments
for arg in "$@"
do
    case $arg in
        --release)
        IS_RELEASE=true
        # Use Development cert hash for archiving; most reliable method
        SIGNING_IDENTITY="BEC010CFEDA389AB331DDF14AC6BDB510C79952A" 
        echo "🚀 Building for RELEASE (Using Development Cert Hash for Archive)"
        ;;
    esac
done

if [ "$IS_RELEASE" = false ]; then
    echo "🔧 Building for DEVELOPMENT"
fi

# Sanitize PATH to avoid conda linker interference
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# Unset interference variables from conda/user env
unset LD LDFLAGS CFLAGS CXXFLAGS CC CXX SDKROOT CMAKE_PREFIX_PATH \
      CONDA_EXE CONDA_PYTHON_EXE CONDA_SHLVL CONDA_PREFIX CONDA_DEFAULT_ENV \
      CONDA_PROMPT_MODIFIER CONDA_BACKUP_HOST CONDA_TOOLCHAIN_HOST \
      CONDA_TOOLCHAIN_BUILD AR AS NM RANLIB STRIP \
      LIPO LIBTOOL OTOOL INSTALL_NAME_TOOL STRINGS SIZE SEGEDIT \
      CLANG CLANGXX OBJC OBJC_FOR_BUILD CPP CPP_FOR_BUILD CC_FOR_BUILD CXX_FOR_BUILD

ARCHIVE_PATH="$PWD/Builds/${APP_NAME}_$(date +%Y-%m-%d_%H-%M-%S).xcarchive"

echo "🚀 Archiving $APP_NAME using xcodebuild..."
echo "📍 Archive Path: $ARCHIVE_PATH"
echo "🔐 Signing with: $SIGNING_IDENTITY"

# Ensure Builds directory exists
mkdir -p Builds

# 1. Build the archive (this produces a binary in usr/local/bin because it's a CLI package)
xcodebuild archive \
    -scheme "$APP_NAME" \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath ".build/xcodebuild" \
    CODE_SIGN_STYLE="Manual" \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    CODE_SIGN_ENTITLEMENTS="" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO || {
        echo "❌ Archiving failed"
        echo "💡 If this failed due to signing, open the package in Xcode and ensure your Team is selected in Signing & Capabilities."
        exit 1
    }

echo "🛠️  Restructuring Archive into App Bundle..."

PRODUCTS_DIR="$ARCHIVE_PATH/Products"
APP_BUNDLE="$PRODUCTS_DIR/Applications/$APP_NAME.app"
BINARY_SOURCE="$PRODUCTS_DIR/usr/local/bin/$APP_NAME"

# Check if binary exists where expected
if [ ! -f "$BINARY_SOURCE" ]; then
    echo "❌ Binary not found at $BINARY_SOURCE"
    exit 1
fi

# Create App Bundle Structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Move Binary
mv "$BINARY_SOURCE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "Sources/Satus/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# --- Icon Generation ---
if [ -f "source_icon.png" ]; then
    echo "🎨 Generating AppIcon.icns..."
    # Ensure source is a valid PNG
    sips -s format png source_icon.png --out source_icon_converted.png --resampleHeightWidth 1024 1024 > /dev/null
    
    mkdir -p Satus.iconset
    sips -z 16 16     source_icon_converted.png --out Satus.iconset/icon_16x16.png > /dev/null
    sips -z 32 32     source_icon_converted.png --out Satus.iconset/icon_16x16@2x.png > /dev/null
    sips -z 32 32     source_icon_converted.png --out Satus.iconset/icon_32x32.png > /dev/null
    sips -z 64 64     source_icon_converted.png --out Satus.iconset/icon_32x32@2x.png > /dev/null
    sips -z 128 128   source_icon_converted.png --out Satus.iconset/icon_128x128.png > /dev/null
    sips -z 256 256   source_icon_converted.png --out Satus.iconset/icon_128x128@2x.png > /dev/null
    sips -z 256 256   source_icon_converted.png --out Satus.iconset/icon_256x256.png > /dev/null
    sips -z 512 512   source_icon_converted.png --out Satus.iconset/icon_512x512@2x.png > /dev/null
    sips -z 1024 1024 source_icon_converted.png --out Satus.iconset/icon_512x512@2x.png > /dev/null

    iconutil -c icns Satus.iconset
    cp Satus.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    
    # Cleanup
    rm -rf Satus.iconset Satus.icns source_icon_converted.png
else
    echo "⚠️  source_icon.png not found. Skipping icon generation."
fi

# Clean up old structure
rm -rf "$PRODUCTS_DIR/usr"

# Update Archive Info.plist to point to the App Bundle
# The default archive for a tool doesn't have ApplicationProperties, so we insert it.
INFO_PLIST="Sources/Satus/Info.plist"
VERSION_STRING=$(defaults read "$PWD/$INFO_PLIST" CFBundleShortVersionString)
BUILD_NUMBER=$(defaults read "$PWD/$INFO_PLIST" CFBundleVersion)
BUNDLE_ID=$(defaults read "$PWD/$INFO_PLIST" CFBundleIdentifier)

plutil -insert ApplicationProperties -xml "
<dict>
    <key>ApplicationPath</key>
    <string>Applications/$APP_NAME.app</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION_STRING</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>SigningIdentity</key>
    <string>$SIGNING_IDENTITY</string>
    <key>Team</key>
    <string>$TEAM_ID</string>
</dict>" "$ARCHIVE_PATH/Info.plist"

echo "✍️  Re-signing App Bundle with Entitlements..."
codesign --force --sign "$SIGNING_IDENTITY" \
    --entitlements "Entitlements.plist" \
    --options runtime \
    --timestamp \
    "$APP_BUNDLE"

echo "✅ Archive successful and restructured!"
echo "📂 Opening in Xcode Organizer..."
open "$ARCHIVE_PATH"

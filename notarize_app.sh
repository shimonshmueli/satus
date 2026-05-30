#!/bin/bash
set -e

# ============================================================================
# notarize_app.sh — Build, sign, notarize, and staple ZoneKey for distribution
# ============================================================================
#
# Prerequisites:
#   1. "Developer ID Application" certificate installed in Keychain
#   2. Credentials stored via:  ./notarize_app.sh --store-credentials
#
# Usage:
#   ./notarize_app.sh                  # Build & notarize ZoneKey (Free)
#   ./notarize_app.sh --pro            # Build & notarize ZoneKey Pro
#   ./notarize_app.sh --dmg            # Also create a DMG for distribution
#   ./notarize_app.sh --store-credentials  # One-time: store Apple ID creds
#   ./notarize_app.sh --skip-build     # Skip build, use existing binary
# ============================================================================

APP_NAME="Satus"
TEAM_ID="66WFCS85L8"
APPLE_ID="shimon.shmueli@outlook.com"
KEYCHAIN_PROFILE="ZoneKeyNotary"
ENTITLEMENTS="Entitlements.plist"

IS_PRO=false
MAKE_DMG=false
SKIP_BUILD=false
STORE_CREDS=false

# ── Parse Arguments ──────────────────────────────────────────────────────────
for arg in "$@"; do
    case $arg in
        --pro)
            IS_PRO=true
            echo "📣 Building PRO version (ZoneKey Pro)"
            ;;
        --dmg)
            MAKE_DMG=true
            echo "📦 Will create DMG after notarization"
            ;;
        --skip-build)
            SKIP_BUILD=true
            echo "⏩ Skipping build, using existing binary"
            ;;
        --store-credentials)
            STORE_CREDS=true
            ;;
        --help|-h)
            echo "Usage: ./notarize_app.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --pro                Build & notarize ZoneKey Pro"
            echo "  --dmg                Create a DMG for distribution"
            echo "  --skip-build         Skip build, use existing .build/release binary"
            echo "  --store-credentials  One-time: store Apple ID credentials in Keychain"
            echo "  --help, -h           Show this help message"
            exit 0
            ;;
    esac
done

# ── Store Credentials (one-time setup) ───────────────────────────────────────
if [ "$STORE_CREDS" = true ]; then
    echo "🔐 Storing notarization credentials in Keychain..."
    echo "   Apple ID: $APPLE_ID"
    echo "   Team ID:  $TEAM_ID"
    echo "   Profile:  $KEYCHAIN_PROFILE"
    echo ""
    echo "You will be prompted for your App-Specific Password."
    echo "Generate one at: https://appleid.apple.com → Sign-In and Security → App-Specific Passwords"
    echo ""
    xcrun notarytool store-credentials "$KEYCHAIN_PROFILE" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID"
    echo "✅ Credentials stored successfully under profile '$KEYCHAIN_PROFILE'"
    exit 0
fi

# ── Resolve Signing Identity ─────────────────────────────────────────────────
echo "🔍 Looking for Developer ID Application certificate..."
SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')

if [ -z "$SIGNING_IDENTITY" ]; then
    echo "❌ No 'Developer ID Application' certificate found!"
    echo ""
    echo "To fix this:"
    echo "  1. Go to https://developer.apple.com/account/resources/certificates/list"
    echo "  2. Click '+' → Select 'Developer ID Application'"
    echo "  3. Follow the CSR workflow via Keychain Access"
    echo "  4. Download and double-click the .cer to install"
    echo ""
    echo "Then re-run this script."
    exit 1
fi

echo "✅ Found signing identity: $SIGNING_IDENTITY"

# ── Verify Notarization Credentials ─────────────────────────────────────────
echo "🔐 Verifying notarization credentials..."
if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" > /dev/null 2>&1; then
    echo "❌ Keychain profile '$KEYCHAIN_PROFILE' not found or invalid!"
    echo ""
    echo "Run this first to store your credentials:"
    echo "  ./notarize_app.sh --store-credentials"
    exit 1
fi
echo "✅ Credentials verified."

# ── Set App Display Names ───────────────────────────────────────────────────
if [ "$IS_PRO" = true ]; then
    DISPLAY_APP_NAME="ZoneKey Pro"
    BUNDLE_ID="com.shimonshmueli.ZoneKeyPro"
else
    DISPLAY_APP_NAME="ZoneKey"
    BUNDLE_ID="com.shimonshmueli.ZoneKey"
fi
EXECUTABLE_NAME="ZoneKey"
APP_BUNDLE="$DISPLAY_APP_NAME.app"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Notarizing: $DISPLAY_APP_NAME"
echo "  Bundle ID:  $BUNDLE_ID"
echo "  Identity:   $SIGNING_IDENTITY"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Sanitize PATH ───────────────────────────────────────────────────────────
# Avoid conda/user env interference with linker
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
unset LD LDFLAGS CFLAGS CXXFLAGS CC CXX SDKROOT CMAKE_PREFIX_PATH \
      CONDA_EXE CONDA_PYTHON_EXE CONDA_SHLVL CONDA_PREFIX CONDA_DEFAULT_ENV \
      CONDA_PROMPT_MODIFIER CONDA_BACKUP_HOST CONDA_TOOLCHAIN_HOST \
      CONDA_TOOLCHAIN_BUILD AR AS NM RANLIB STRIP \
      LIPO LIBTOOL OTOOL INSTALL_NAME_TOOL STRINGS SIZE SEGEDIT \
      CLANG CLANGXX OBJC OBJC_FOR_BUILD CPP CPP_FOR_BUILD CC_FOR_BUILD CXX_FOR_BUILD

# ── Step 1: Build ────────────────────────────────────────────────────────────
if [ "$SKIP_BUILD" = false ]; then
    echo "🔨 Step 1/6: Building $APP_NAME (release)..."
    if [ "$IS_PRO" = true ]; then
        swift build -c release -Xswiftc -DSATUS_PRO
    else
        swift build -c release
    fi
    echo "✅ Build complete."
else
    echo "⏩ Step 1/6: Skipping build (using existing binary)."
    if [ ! -f ".build/release/$APP_NAME" ]; then
        echo "❌ No binary found at .build/release/$APP_NAME"
        echo "   Run without --skip-build first."
        exit 1
    fi
fi

# ── Step 2: Assemble App Bundle ─────────────────────────────────────────────
echo "📁 Step 2/6: Assembling app bundle..."

# Clean previous bundle if exists
rm -rf "$APP_BUNDLE"

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

# Copy and configure Info.plist
cp "Sources/Satus/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Set bundle ID and display name
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleName -string "$DISPLAY_APP_NAME" "$APP_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/Info.plist"

# Generate and copy app icon
if [ -f "source_icon.png" ]; then
    echo "🎨 Generating AppIcon.icns..."
    sips -s format png source_icon.png --out _icon_tmp.png --resampleHeightWidth 1024 1024 > /dev/null 2>&1

    mkdir -p _icon.iconset
    sips -z 16 16     _icon_tmp.png --out _icon.iconset/icon_16x16.png > /dev/null 2>&1
    sips -z 32 32     _icon_tmp.png --out _icon.iconset/icon_16x16@2x.png > /dev/null 2>&1
    sips -z 32 32     _icon_tmp.png --out _icon.iconset/icon_32x32.png > /dev/null 2>&1
    sips -z 64 64     _icon_tmp.png --out _icon.iconset/icon_32x32@2x.png > /dev/null 2>&1
    sips -z 128 128   _icon_tmp.png --out _icon.iconset/icon_128x128.png > /dev/null 2>&1
    sips -z 256 256   _icon_tmp.png --out _icon.iconset/icon_128x128@2x.png > /dev/null 2>&1
    sips -z 256 256   _icon_tmp.png --out _icon.iconset/icon_256x256.png > /dev/null 2>&1
    sips -z 512 512   _icon_tmp.png --out _icon.iconset/icon_256x256@2x.png > /dev/null 2>&1
    sips -z 512 512   _icon_tmp.png --out _icon.iconset/icon_512x512.png > /dev/null 2>&1
    sips -z 1024 1024 _icon_tmp.png --out _icon.iconset/icon_512x512@2x.png > /dev/null 2>&1

    iconutil -c icns _icon.iconset -o _icon.icns
    cp _icon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

    # Cleanup temp icon files
    rm -rf _icon.iconset _icon.icns _icon_tmp.png
elif [ -f "Sources/Satus/Resources/AppIcon.icns" ]; then
    echo "📎 Copying existing AppIcon.icns..."
    cp "Sources/Satus/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "⚠️  No icon source found. App will use default icon."
fi

echo "✅ App bundle assembled: $APP_BUNDLE"

# ── Step 3: Code Sign ───────────────────────────────────────────────────────
echo "✍️  Step 3/6: Code signing with Developer ID + hardened runtime..."

codesign --force --deep --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    --timestamp \
    "$APP_BUNDLE"

# Verify signature
echo "   Verifying signature..."
codesign -vvv --deep --strict "$APP_BUNDLE"
echo "✅ Code signing verified."

# ── Step 4: Create ZIP for Notarization ──────────────────────────────────────
echo "📦 Step 4/6: Creating ZIP for notarization submission..."
ZIP_FILE="${DISPLAY_APP_NAME// /_}_notarize.zip"
rm -f "$ZIP_FILE"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_FILE"
echo "✅ Created: $ZIP_FILE"

# ── Step 5: Submit for Notarization ──────────────────────────────────────────
echo "🚀 Step 5/6: Submitting to Apple notary service..."
echo "   This typically takes 2-5 minutes. Waiting for response..."
echo ""

xcrun notarytool submit "$ZIP_FILE" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

echo ""
echo "✅ Notarization complete!"

# Clean up zip
rm -f "$ZIP_FILE"

# ── Step 6: Staple ───────────────────────────────────────────────────────────
echo "📌 Step 6/6: Stapling notarization ticket to app..."
xcrun stapler staple "$APP_BUNDLE"

echo ""
echo "🔍 Final verification..."
# Verify Gatekeeper will accept the app
spctl --assess --type exec -vvv "$APP_BUNDLE" 2>&1 || true
xcrun stapler validate "$APP_BUNDLE"

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ✅ $DISPLAY_APP_NAME is notarized and ready for distribution!"
echo "══════════════════════════════════════════════════════════════"

# ── Optional: Create DMG ─────────────────────────────────────────────────────
if [ "$MAKE_DMG" = true ]; then
    echo ""
    echo "📀 Creating DMG..."

    VERSION_STRING=$(defaults read "$PWD/$APP_BUNDLE/Contents/Info.plist" CFBundleShortVersionString)
    BUILD_NUMBER=$(defaults read "$PWD/$APP_BUNDLE/Contents/Info.plist" CFBundleVersion)
    DMG_NAME="${DISPLAY_APP_NAME// /_}_v${VERSION_STRING}_b${BUILD_NUMBER}.dmg"

    # Create a temporary folder for DMG contents
    DMG_TEMP="dmg_temp"
    rm -rf "$DMG_TEMP"
    mkdir -p "$DMG_TEMP"

    # Copy app into DMG staging area
    cp -R "$APP_BUNDLE" "$DMG_TEMP/"

    # Create symlink to /Applications for drag-to-install
    ln -s /Applications "$DMG_TEMP/Applications"

    # Create DMG
    rm -f "$DMG_NAME"
    hdiutil create -volname "$DISPLAY_APP_NAME" \
        -srcfolder "$DMG_TEMP" \
        -ov -format UDZO \
        "$DMG_NAME"

    # Clean up staging
    rm -rf "$DMG_TEMP"

    # Sign the DMG
    echo "✍️  Signing DMG..."
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_NAME"

    # Notarize the DMG
    echo "🚀 Submitting DMG for notarization..."
    xcrun notarytool submit "$DMG_NAME" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    # Staple the DMG
    echo "📌 Stapling DMG..."
    xcrun stapler staple "$DMG_NAME"

    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "  📀 DMG ready: $DMG_NAME"
    echo "══════════════════════════════════════════════════════════════"
fi

# ── Install to ~/Applications ────────────────────────────────────────────────
echo ""
read -p "📥 Install to ~/Applications? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    INSTALL_DIR="$HOME/Applications"
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR/$APP_BUNDLE"
    cp -R "$APP_BUNDLE" "$INSTALL_DIR/"
    echo "✅ Installed to $INSTALL_DIR/$APP_BUNDLE"
fi

echo ""
echo "🎉 Done! Your notarized app is at: $(pwd)/$APP_BUNDLE"

#!/bin/bash
# Build Convoker with xcodebuild
#
# Usage: ./build.sh [command]
#   ./build.sh           — build only (Debug)
#   ./build.sh run       — build and run
#   ./build.sh install   — build, copy to /Applications, and launch
#   ./build.sh uninstall — quit app and remove from /Applications
#   ./build.sh dmg       — Release build + signed DMG (no notarization)
#   ./build.sh dist      — Release build + signed DMG + notarized + stapled

set -e
cd "$(dirname "$0")"

DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Convoker"
BUNDLE_ID="com.convoker.app"
INSTALL_DIR="/Applications/$APP_NAME.app"
SIGN_IDENTITY="${CONVOKER_SIGN_IDENTITY:-Developer ID Application: Varie.AI LLC (DT49XDQPKV)}"
ENTITLEMENTS="$SCRIPT_DIR/App/Convoker.entitlements"

# --- uninstall: no build needed ---
if [ "$1" = "uninstall" ]; then
    echo "Uninstalling $APP_NAME..."
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    sleep 1
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        echo "Removed $INSTALL_DIR"
    else
        echo "Nothing to remove — $INSTALL_DIR does not exist"
    fi
    exit 0
fi

# --- determine build configuration ---
if [ "$1" = "dist" ] || [ "$1" = "dmg" ]; then
    BUILD_CONFIG="Release"
else
    BUILD_CONFIG="Debug"
fi

# --- build ---

# 1. Resolve packages
echo "Resolving packages..."
xcodebuild -resolvePackageDependencies -scheme "$APP_NAME" -quiet 2>/dev/null || true

# 2. Find DerivedData project folder
DD_DIR=$(find "$DERIVED_DATA" -maxdepth 1 -name "${APP_NAME}-*" -type d 2>/dev/null | head -1)

# 3. Build
echo "Building ($BUILD_CONFIG)..."
xcodebuild build \
    -scheme "$APP_NAME" \
    -destination 'platform=OS X' \
    -configuration "$BUILD_CONFIG" \
    INFOPLIST_FILE="$SCRIPT_DIR/App/Info.plist" \
    CREATE_INFOPLIST_SECTION_IN_BINARY=YES \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    -quiet

# 4. Find the build output directory
DD_DIR=$(find "$DERIVED_DATA" -maxdepth 1 -name "${APP_NAME}-*" -type d 2>/dev/null | head -1)
BUILD_DIR="$DD_DIR/Build/Products/$BUILD_CONFIG"
BIN="$BUILD_DIR/$APP_NAME"

if [ ! -f "$BIN" ]; then
    echo "ERROR: Build failed — binary not found"
    exit 1
fi

# 5. Assemble .app bundle
APP_DIR="$BUILD_DIR/$APP_NAME.app"
echo "Assembling .app bundle..."

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Executable
cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Info.plist
cp "$SCRIPT_DIR/App/Info.plist" "$APP_DIR/Contents/Info.plist"

# PkgInfo
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# App icon (if exists)
if [ -f "$SCRIPT_DIR/App/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/App/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
    echo "  Copied AppIcon.icns"
fi

# Copy SPM resource bundles
for BUNDLE_PATH in "$BUILD_DIR"/*.bundle; do
    if [ -d "$BUNDLE_PATH" ]; then
        BUNDLE_NAME=$(basename "$BUNDLE_PATH")
        cp -R "$BUNDLE_PATH" "$APP_DIR/Contents/Resources/"
        echo "  Copied $BUNDLE_NAME"
    fi
done

# 6. Code sign
if [ "$1" = "dist" ] || [ "$1" = "dmg" ]; then
    echo "Signing with Developer ID + hardened runtime..."
    # Sign embedded bundles first
    for BUNDLE_PATH in "$APP_DIR/Contents/Resources"/*.bundle; do
        if [ -d "$BUNDLE_PATH" ]; then
            codesign --force --sign "$SIGN_IDENTITY" --options runtime "$BUNDLE_PATH"
        fi
    done
    # Sign main app
    codesign --force --sign "$SIGN_IDENTITY" --options runtime \
        --entitlements "$ENTITLEMENTS" --deep "$APP_DIR"
    echo "  Signed: $(codesign -dvv "$APP_DIR" 2>&1 | grep 'Authority=' | head -1)"
else
    # Developer ID for dev builds (stable accessibility permission)
    DEV_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')
    if [ -n "$DEV_IDENTITY" ]; then
        codesign --force --sign "$DEV_IDENTITY" --deep "$APP_DIR" 2>/dev/null
        echo "  Signed with: $DEV_IDENTITY"
    else
        codesign --force --sign - --deep "$APP_DIR" 2>/dev/null
        echo "  Signed with: ad-hoc (accessibility permission will reset each build)"
    fi
fi

echo ""
echo "Build complete!"
echo "App bundle: $APP_DIR"
echo "  Size: $(du -sh "$APP_DIR" | cut -f1)"

# --- run / install / dmg / dist ---
if [ "$1" = "run" ]; then
    echo "Launching..."
    open "$APP_DIR"
elif [ "$1" = "install" ]; then
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    sleep 1
    echo "Installing to /Applications..."
    rm -rf "$INSTALL_DIR"
    cp -R "$APP_DIR" "$INSTALL_DIR"
    echo "Installed: $INSTALL_DIR"
    echo "Launching..."
    open "$INSTALL_DIR"
elif [ "$1" = "dmg" ] || [ "$1" = "dist" ]; then
    VERSION=$(defaults read "$APP_DIR/Contents/Info.plist" CFBundleShortVersionString)
    DIST_DIR="$SCRIPT_DIR/dist"
    DMG_NAME="$APP_NAME-$VERSION.dmg"
    DMG_PATH="$DIST_DIR/$DMG_NAME"

    mkdir -p "$DIST_DIR"
    rm -f "$DMG_PATH"

    echo ""
    echo "Creating DMG..."

    # Create writable DMG, mount, copy files, unmount, convert to compressed.
    DMG_TEMP="$DIST_DIR/.temp.dmg"
    DMG_COPY_MOUNT="/tmp/convoker-dmg-mount"
    rm -f "$DMG_TEMP"
    mkdir -p "$DMG_COPY_MOUNT"

    # Estimate size: app size + 10MB headroom
    APP_SIZE_KB=$(du -sk "$APP_DIR" | cut -f1)
    DMG_SIZE_KB=$((APP_SIZE_KB + 10240))

    hdiutil create -size "${DMG_SIZE_KB}k" -fs HFS+ -volname "$APP_NAME" "$DMG_TEMP" -quiet
    hdiutil attach "$DMG_TEMP" -nobrowse -quiet -mountpoint "$DMG_COPY_MOUNT"

    cp -a "$APP_DIR" "$DMG_COPY_MOUNT/"
    ln -s /Applications "$DMG_COPY_MOUNT/Applications"

    hdiutil detach "$DMG_COPY_MOUNT" -quiet

    # Remount at /Volumes/ for Finder styling
    hdiutil attach "$DMG_TEMP" -quiet
    sleep 3

    osascript <<APPLESCRIPT
    tell application "Finder"
        tell disk "$APP_NAME"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {200, 200, 700, 500}
            set opts to icon view options of container window
            set icon size of opts to 80
            set arrangement of opts to not arranged
            set position of item "$APP_NAME.app" of container window to {120, 150}
            set position of item "Applications" of container window to {380, 150}
            close
            open
            update without registering applications
            delay 2
            close
        end tell
    end tell
APPLESCRIPT

    sync
    hdiutil detach "/Volumes/$APP_NAME" -quiet
    hdiutil convert "$DMG_TEMP" -format UDZO -o "$DMG_PATH" -quiet -ov
    rm -f "$DMG_TEMP"

    echo "DMG created: $DMG_PATH"
    echo "  Size: $(du -sh "$DMG_PATH" | cut -f1)"

    if [ "$1" = "dist" ]; then
        echo ""
        echo "Submitting for notarization..."
        xcrun notarytool submit "$DMG_PATH" --keychain-profile "notary" --wait

        echo "Stapling notarization ticket..."
        xcrun stapler staple "$DMG_PATH"

        echo ""
        echo "Distribution ready!"
    else
        echo ""
        echo "DMG ready (not notarized — use 'dist' for notarized build)"
    fi

    echo "  DMG: $DMG_PATH"
fi

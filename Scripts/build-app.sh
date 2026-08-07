#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="HarvestButGood"
PRODUCT_NAME="HarvestTimer"
BUILD_DIR=".build/release"
APP_DIR="dist/${APP_NAME}.app"

swift build -c release --product "$PRODUCT_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$PRODUCT_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>HarvestButGood</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.rolemodel.HarvestTimer</string>
    <key>CFBundleName</key>
    <string>HarvestButGood</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>RoleModel Software</string>
</dict>
</plist>
PLIST

# A stable identity keeps the signature the same between builds, so the
# Keychain doesn't ask for your password after every rebuild. Prefer a real
# Apple identity, then the self-signed one from Scripts/create-signing-cert.sh.
find_identity() {
    security find-identity -v -p codesigning \
        | awk -F'"' -v want="$1" '$0 ~ want {print $2; exit}'
}

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="$(find_identity 'Apple Development')"
fi
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="$(find_identity 'HarvestButGood Dev')"
fi
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="-"
    echo "Warning: no signing identity, falling back to ad-hoc signing."
    echo "         The Keychain will prompt again after every rebuild."
    echo "         Run Scripts/create-signing-cert.sh once to stop that."
fi

codesign --force --sign "$SIGN_IDENTITY" "$APP_DIR"

echo "Built $APP_DIR"
echo "Run it with:      open \"$APP_DIR\""
echo "Install it with:  cp -R \"$APP_DIR\" /Applications/"

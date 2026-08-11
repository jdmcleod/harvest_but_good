#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="HarvestButGood"
PRODUCT_NAME="HarvestTimer"
BUILD_DIR=".build/release"
# The bundle is assembled here and then moved, so nothing launchable is left
# behind. Two copies of the app cost you a duplicate Spotlight hit and a second
# Keychain prompt, because the credentials trust one path and you launch the
# other. Set INSTALL_DIR to install somewhere else.
STAGED_APP="dist/${APP_NAME}.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
INSTALLED_APP="${INSTALL_DIR}/${APP_NAME}.app"

# Stamped into the bundle so the app can ask GitHub what has landed since it
# was built. Tracked files only: an untracked scratch file changes nothing that
# ends up in the binary, and calling that dirty would cry wolf.
GIT_COMMIT="$(git rev-parse HEAD 2>/dev/null || true)"
if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    GIT_DIRTY="true"
else
    GIT_DIRTY="false"
fi

swift build -c release --product "$PRODUCT_NAME"

rm -rf "$STAGED_APP"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"

cp "$BUILD_DIR/$PRODUCT_NAME" "$STAGED_APP/Contents/MacOS/$APP_NAME"
cp Resources/AppIcon.icns "$STAGED_APP/Contents/Resources/AppIcon.icns"

# Unquoted, so the git stamps below expand. Nothing else in here needs
# escaping: the plist carries no dollar signs, backticks, or backslashes.
cat > "$STAGED_APP/Contents/Info.plist" <<PLIST
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
    <key>GitCommit</key>
    <string>${GIT_COMMIT}</string>
    <key>GitDirty</key>
    <string>${GIT_DIRTY}</string>
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
#
# A self-signed certificate only gets you halfway: it carries no Team ID, so
# macOS pins the Keychain to this exact build's hash rather than to the
# certificate, and the first launch after a rebuild asks once more. Click
# "Always Allow" there, or sign with an Apple Development identity to be rid
# of it for good.
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

codesign --force --sign "$SIGN_IDENTITY" "$STAGED_APP"

# Quit only once the build has succeeded and been signed, so a broken build
# leaves the working app running. The install below replaces the bundle a
# running copy is reading from, so it has to go first either way.
if pgrep -xq "$APP_NAME"; then
    echo "Quitting running ${APP_NAME}..."
    pkill -x "$APP_NAME"
    while pgrep -xq "$APP_NAME"; do sleep 0.2; done
fi

# Replace rather than merge: dropping a new bundle on top of an old one leaves
# whatever the old one had and the new one doesn't, and a stale file inside a
# signed bundle breaks the signature. Check what is there before removing it,
# since this deletes a directory in $INSTALL_DIR.
# Read the identifier off the staged plist rather than repeating it here, but
# treat an unreadable one as fatal: this guards an rm -rf, and a guard that ends
# up comparing two empty strings waves everything through. plutil rather than
# defaults, which wants a domain and quietly fails on a relative path like this
# one -- that failure left BUNDLE_ID empty, so the check refused to replace the
# real app and deleted anything whose plist it couldn't read.
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$STAGED_APP/Contents/Info.plist")"
if [ -z "$BUNDLE_ID" ]; then
    echo "Couldn't read CFBundleIdentifier from $STAGED_APP/Contents/Info.plist." >&2
    echo "Refusing to touch $INSTALLED_APP without knowing what this build is." >&2
    exit 1
fi

if [ -e "$INSTALLED_APP" ]; then
    # Unreadable here is not fatal, unlike above: it means whatever is sitting
    # there is not ours, which the refusal below is for. Assign only on success,
    # since plutil reports "no such file" on stdout and that would otherwise be
    # captured as the identifier and printed as if it were one.
    installed_id=""
    if id_read="$(
        plutil -extract CFBundleIdentifier raw "$INSTALLED_APP/Contents/Info.plist" 2>/dev/null
    )"; then
        installed_id="$id_read"
    fi
    if [ "$installed_id" != "$BUNDLE_ID" ]; then
        echo "Refusing to replace $INSTALLED_APP:" >&2
        echo "  expected $BUNDLE_ID, found \"${installed_id:-nothing readable}\"." >&2
        echo "  Move it aside by hand, or set INSTALL_DIR elsewhere." >&2
        echo "  The build is waiting at $STAGED_APP." >&2
        exit 1
    fi
    rm -rf "$INSTALLED_APP"
fi

mkdir -p "$INSTALL_DIR"
# ditto rather than cp, which drops the extended attributes on a bundle.
ditto "$STAGED_APP" "$INSTALLED_APP"
rm -rf "$STAGED_APP"

codesign --verify --strict "$INSTALLED_APP"

echo "Installed $INSTALLED_APP"

open "$INSTALLED_APP"
echo "Launched $APP_NAME."

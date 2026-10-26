#!/bin/sh
# Install or update Harvest But Good from the latest GitHub release:
#   curl -fsSL https://github.com/jdmcleod/harvest_but_good/releases/latest/download/install.sh | sh
# Once installed, the app updates itself from Settings → Updates.
set -eu

REPO="jdmcleod/harvest_but_good"
APP="/Applications/HarvestButGood.app"
# The app checks the same thing before swapping in an update. See
# ReleaseInstaller.requirement for why each part is there.
REQUIREMENT='anchor apple generic and identifier "com.rolemodel.HarvestTimer" and certificate leaf[subject.OU] = "4UDYMLGB25"'

# ponytail: Apple silicon only; build universal if an Intel Mac turns up.
[ "$(uname -m)" = arm64 ] || { echo "Releases are built for Apple silicon only." >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading the latest release..."
curl -fsSL "https://github.com/$REPO/releases/latest/download/HarvestButGood.zip" -o "$TMP/app.zip"
ditto -x -k "$TMP/app.zip" "$TMP"
codesign --verify --strict -R="$REQUIREMENT" "$TMP/HarvestButGood.app"

# The same guard as Scripts/build-app.sh: this removes a directory in
# /Applications, so it has to be ours.
if [ -e "$APP" ]; then
    installed_id="$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist" 2>/dev/null || true)"
    if [ "$installed_id" != "com.rolemodel.HarvestTimer" ]; then
        echo "Refusing to replace $APP: it isn't Harvest But Good. Move it aside first." >&2
        exit 1
    fi
fi

if pgrep -xq HarvestButGood; then
    echo "Quitting the running copy..."
    pkill -x HarvestButGood
    while pgrep -xq HarvestButGood; do sleep 0.2; done
fi

# Copy beside the old app and swap by renaming, so a failed copy leaves the
# old one in place. Same steps as the swap in ReleaseInstaller.swift.
rm -rf "$APP.updating" "$APP.old"
ditto "$TMP/HarvestButGood.app" "$APP.updating"
if [ -e "$APP" ]; then
    mv "$APP" "$APP.old"
fi
if ! mv "$APP.updating" "$APP"; then
    if [ -e "$APP.old" ]; then
        mv "$APP.old" "$APP"
    fi
    echo "Couldn't move the new app into place; the old one is back." >&2
    exit 1
fi
rm -rf "$APP.old"
echo "Installed $APP"
open "$APP"

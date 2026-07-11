#!/bin/zsh
# Builds CommandCentral and assembles dist/CommandCentral.app.
# Intentionally avoids `rm`: files are overwritten in place.
set -e
cd "$(dirname "$0")"

swift build -c release

APP="dist/CommandCentral.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Stop a running instance so the binary can be replaced cleanly.
pkill -x CommandCentral 2>/dev/null || true

cp .build/release/CommandCentral "$APP/Contents/MacOS/CommandCentral"
cp Info.plist "$APP/Contents/Info.plist"
if [[ -f AppIcon.icns ]]; then
  cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force -s - "$APP"

echo "Built $APP — launch with: open $APP"

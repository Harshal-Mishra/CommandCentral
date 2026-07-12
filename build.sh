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

# Sign with the stable dev certificate when present — TCC permissions
# (Screen Recording etc.) are tied to the signature and break on every
# rebuild with ad-hoc (-) signing.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "CommandCentral Dev"; then
  codesign --force -s "CommandCentral Dev" "$APP"
else
  echo "warning: 'CommandCentral Dev' certificate missing — ad-hoc signing (TCC grants will not survive rebuilds)"
  codesign --force -s - "$APP"
fi

echo "Built $APP — launch with: open $APP"

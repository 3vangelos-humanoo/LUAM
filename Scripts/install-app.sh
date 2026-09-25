#!/bin/zsh
# Builds LUAM (Release) and installs it into /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED="build/DerivedData"
# Stop on a failed build rather than installing whatever an earlier one left.
if ! xcodebuild -project LUAM.xcodeproj -scheme LUAM -configuration Release \
    -derivedDataPath "$DERIVED" build > "$DERIVED.log" 2>&1; then
    grep -a -E "error:" "$DERIVED.log" || tail -20 "$DERIVED.log"
    echo "Build failed — full log in $DERIVED.log"
    exit 1
fi
grep -a -E "warning:" "$DERIVED.log" | sort -u || true

APP="$DERIVED/Build/Products/Release/LUAM.app"
[[ -d "$APP" ]] || { echo "Build failed — no $APP"; exit 1; }

# /Applications if writable, otherwise the per-user ~/Applications.
DEST="/Applications"
[[ -w "$DEST" ]] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }

osascript -e 'quit app "LUAM"' 2>/dev/null || true
rm -rf "$DEST/LUAM.app"
ditto "$APP" "$DEST/LUAM.app"
echo "Installed $DEST/LUAM.app"
open "$DEST/LUAM.app"

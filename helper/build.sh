#!/bin/bash
#
# Builds and installs the WifiSSID helper (reads the Wi-Fi name through Location Services).
# Idempotent: safe to re-run.
#
# ⚠️ The Location grant is bound to the SIGNATURE of the binary: rebuilding the .app
#    invalidates it, so "--grant" has to be done once more (see the end of this script).
#
# ⚠️ INSTALL_DIR and the bundle id in Info.plist are named "connexion-menubar" for
#    historical reasons. The Location grant is tied to that identity — renaming either
#    revokes it and forces every existing user to grant again. Leave them alone.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/Library/Application Support/connexion-menubar"
APP="$INSTALL_DIR/WifiSSID.app"
BIN="$APP/Contents/MacOS/WifiSSID"
TMP_BIN="$(mktemp -t WifiSSID)"

echo "→ Compiling…"
swiftc "$HERE/agent.swift" -o "$TMP_BIN" \
  -framework Cocoa -framework CoreLocation -framework CoreWLAN

echo "→ Assembling the bundle: $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mv "$TMP_BIN" "$BIN"
cp "$HERE/Info.plist" "$APP/Contents/Info.plist"

echo "→ Ad-hoc signing…"
codesign --force --deep --sign - "$APP"

echo
echo "✅ Helper installed: $APP"
echo
echo "──────────────────────────────────────────────────────────────────────"
echo " LAST STEP (once, from Terminal.app — not from a script):"
echo
echo "   \"$BIN\" --grant"
echo
echo " then click \"Allow\" on the macOS dialog."
echo " The Wi-Fi name shows up in the SwiftBar dropdown within 30 s."
echo "──────────────────────────────────────────────────────────────────────"

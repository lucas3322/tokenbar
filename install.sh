#!/bin/bash
# Instala o TokenBar em ~/Applications e faz ele subir junto com o login.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

DEST="$HOME/Applications"
mkdir -p "$DEST"
rm -rf "$DEST/TokenBar.app"
cp -R TokenBar.app "$DEST/"

PLIST="$HOME/Library/LaunchAgents/local.tokenbar.plist"
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>local.tokenbar</string>
    <key>ProgramArguments</key>
    <array><string>$DEST/TokenBar.app/Contents/MacOS/TokenBar</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PL

launchctl unload "$PLIST" 2>/dev/null || true
pkill -f "TokenBar.app/Contents/MacOS/TokenBar" 2>/dev/null || true
launchctl load "$PLIST"

echo "✓ TokenBar instalado em $DEST e habilitado no login"

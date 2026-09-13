#!/bin/bash
# Instala o TokenBar em ~/Applications e faz ele subir junto com o login.
set -euo pipefail
cd "$(dirname "$0")"

# --system instala em /Applications (a pasta Aplicativos que todo mundo enxerga).
# Sem a flag, instala em ~/Applications, que é pessoal e não pede permissão nenhuma.
DEST="$HOME/Applications"
if [ "${1:-}" = "--system" ]; then
  DEST="/Applications"
fi

./build.sh
mkdir -p "$DEST"
# Remove qualquer cópia antiga, inclusive na outra pasta, para não ficarem duas rodando.
pkill -f "TokenBar.app/Contents/MacOS/TokenBar" 2>/dev/null || true
rm -rf "$HOME/Applications/TokenBar.app" "/Applications/TokenBar.app"
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

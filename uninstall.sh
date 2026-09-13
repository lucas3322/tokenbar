#!/bin/bash
# Remove o TokenBar por completo: app, início automático e cache.
set -euo pipefail
PLIST="$HOME/Library/LaunchAgents/local.tokenbar.plist"
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
pkill -f "TokenBar.app/Contents/MacOS/TokenBar" 2>/dev/null || true
rm -rf "$HOME/Applications/TokenBar.app"
rm -rf "$HOME/.tokenbar"
echo "✓ TokenBar removido (config e cache incluídos)"

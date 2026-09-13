#!/bin/bash
# Compila o TokenBar.app sem Xcode — só com os Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="TokenBar.app"
BIN="$APP/Contents/MacOS/TokenBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -whole-module-optimization \
  -target arm64-apple-macos14.0 \
  -framework AppKit -framework SwiftUI -framework Combine \
  -o "$BIN" \
  Sources/*.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>TokenBar</string>
    <key>CFBundleDisplayName</key><string>TokenBar</string>
    <key>CFBundleIdentifier</key><string>local.tokenbar</string>
    <key>CFBundleExecutable</key><string>TokenBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Assinatura ad-hoc: o app roda localmente sem conta de desenvolvedor.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✓ $APP pronto"

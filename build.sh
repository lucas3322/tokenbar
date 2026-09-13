#!/bin/bash
# Compila o TokenBar.app sem Xcode — só com os Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="TokenBar.app"
BIN="$APP/Contents/MacOS/TokenBar"

# Fonte única da verdade da versão. Mude com ./version.sh, nunca aqui.
VERSION="$(cat VERSION)"
# Número de build = quantidade de commits. Sempre cresce, como o macOS espera.
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Ícone: desenhado por código, gerado só quando ainda não existe.
if [ ! -f "Resources/AppIcon.icns" ]; then
  echo "gerando ícone..."
  mkdir -p Resources
  swiftc -O -target arm64-apple-macos14.0 -framework AppKit \
    -o tools/makeicon/makeicon tools/makeicon/main.swift
  ./tools/makeicon/makeicon build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
  rm -rf build
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

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
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>__VERSION__</string>
    <key>CFBundleVersion</key><string>__BUILD__</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Substitui os marcadores do plist pelos valores reais.
/usr/bin/sed -i '' "s/__VERSION__/$VERSION/; s/__BUILD__/$BUILD/" "$APP/Contents/Info.plist"

# Assinatura ad-hoc: o app roda localmente sem conta de desenvolvedor.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✓ $APP pronto — versão $VERSION (build $BUILD)"

#!/bin/bash
# Akıntı'yı derleyip Akinti.app paketi üretir. macOS 13+ ve Xcode komut satırı araçları gerekir.
set -euo pipefail
cd "$(dirname "$0")"

if ! brew list libtorrent-rasterbar >/dev/null 2>&1; then
  echo "libtorrent kuruluyor…"
  brew install libtorrent-rasterbar boost openssl pkg-config
fi

# libtorrent'in kendi derleme bayraklarını pkg-config'ten al
export PKG_CONFIG_PATH="$(brew --prefix)/lib/pkgconfig:$(brew --prefix openssl)/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
EXTRA=()
for f in $(pkg-config --cflags libtorrent-rasterbar); do EXTRA+=(-Xcxx "$f"); done

swift build -c release "${EXTRA[@]}"

APP="Akinti.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
cp ".build/release/Akinti" "$APP/Contents/MacOS/Akinti"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Akıntı</string>
  <key>CFBundleDisplayName</key><string>Akıntı</string>
  <key>CFBundleIdentifier</key><string>com.akinti.app</string>
  <key>CFBundleExecutable</key><string>Akinti</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>Magnet</string>
    <key>CFBundleURLSchemes</key><array><string>magnet</string></array>
  </dict></array>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>BitTorrent</string>
    <key>CFBundleTypeExtensions</key><array><string>torrent</string></array>
    <key>CFBundleTypeRole</key><string>Viewer</string>
  </dict></array>
</dict></plist>
EOF

# Homebrew dylib'lerini pakete göm (başka Mac'lerde çalışması için)
if command -v dylibbundler >/dev/null 2>&1; then
  dylibbundler -od -b -x "$APP/Contents/MacOS/Akinti" -d "$APP/Contents/Frameworks" -p @executable_path/../Frameworks
else
  echo "Not: 'brew install dylibbundler' kurarsanız bağımlılıklar .app içine gömülür."
fi

codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "Hazır: $(pwd)/$APP"

# DMG üret
rm -rf dmg-staging Akinti.dmg
mkdir dmg-staging
cp -R "$APP" dmg-staging/
ln -s /Applications dmg-staging/Applications
hdiutil create -volname "Akıntı" -srcfolder dmg-staging -ov -format UDZO Akinti.dmg
rm -rf dmg-staging
echo "DMG hazır: $(pwd)/Akinti.dmg"
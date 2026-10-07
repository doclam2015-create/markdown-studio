#!/bin/zsh
# Compila Markdown Studio.app y la instala en /Applications
set -e
cd "$(dirname "$0")/.."
B=build; APP="$B/Markdown Studio.app"
mkdir -p "$B"
swiftc -O mac/icon.swift -o "$B/icongen" && "$B/icongen" "$B"
rm -rf "$B/AppIcon.iconset" "$APP"; mkdir -p "$B/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$B/icon-mac-1024.png" --out "$B/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s*2)); sips -z $d $d "$B/icon-mac-1024.png" --out "$B/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$B/AppIcon.iconset" -o "$B/AppIcon.icns"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O mac/main.swift -o "$APP/Contents/MacOS/MarkdownStudio" -target arm64-apple-macos13.0
cp mac/Info.plist "$APP/Contents/Info.plist"
cp index.html "$APP/Contents/Resources/index.html"
cp "$B/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
rm -rf "/Applications/Markdown Studio.app"
cp -R "$APP" /Applications/
echo "Instalada en /Applications/Markdown Studio.app"

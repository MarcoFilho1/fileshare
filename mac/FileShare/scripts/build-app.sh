#!/bin/sh
# Gera build/FileShare.app (app só de barra de menu) a partir do pacote Swift, sem Xcode.
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP=build/FileShare.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/FileShare" "$APP/Contents/MacOS/FileShare"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.marcofilho.fileshare</string>
    <key>CFBundleName</key><string>FileShare</string>
    <key>CFBundleExecutable</key><string>FileShare</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>2.0.0-dev</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"

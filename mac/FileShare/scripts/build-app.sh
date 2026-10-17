#!/bin/sh
# Gera build/FileShare.app (app só de barra de menu) a partir do pacote Swift, sem Xcode.
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP=build/FileShare.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # gerado por scripts/make-icon.swift
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
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>2.3.1</string>
    <key>CFBundleVersion</key><string>2.3.1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSLocalNetworkUsageDescription</key><string>O FileShare conversa com o seu tablet pela rede Wi-Fi local.</string>
    <key>NSBonjourServices</key><array><string>_fileshare._tcp</string></array>
    <!-- Finder: botão direito → Ações Rápidas/Serviços → Enviar ao tablet -->
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Enviar ao tablet</string></dict>
            <key>NSMessage</key><string>sendToTablet</string>
            <key>NSPortName</key><string>FileShare</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.item</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"

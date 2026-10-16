#!/bin/sh
# Gera os arquivos de download da release em dist/: FileShare.dmg (Mac) e FileShare.apk (Android,
# assinado com a chave definitiva em ~/.fileshare). Os nomes não têm versão de propósito: o site
# aponta para releases/latest/download/<nome>.
set -e
cd "$(dirname "$0")/.."
rm -rf dist && mkdir -p dist

# Android
[ -f "$HOME/.fileshare/release.jks" ] || { echo "falta a chave em ~/.fileshare/release.jks"; exit 1; }
android/scripts/build.sh assembleRelease
cp android/app/build/outputs/apk/release/app-release.apk dist/FileShare.apk

# Mac: o app num .dmg com o atalho para Aplicativos, como os apps do Mac costumam vir
mac/FileShare/scripts/build-app.sh >/dev/null
STAGE=$(mktemp -d)
ditto mac/FileShare/build/FileShare.app "$STAGE/FileShare.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname FileShare -srcfolder "$STAGE" -format UDZO -ov dist/FileShare.dmg
rm -rf "$STAGE"

ls -la dist

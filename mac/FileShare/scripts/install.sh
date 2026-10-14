#!/bin/sh
# Compila, instala em /Applications e reabre o FileShare. Rode de novo para atualizar.
set -e
cd "$(dirname "$0")/.."
scripts/build-app.sh >/dev/null
echo "Fechando o FileShare em execução…"
osascript -e 'quit app id "dev.marcofilho.fileshare"' >/dev/null 2>&1 || true
sleep 1
pkill -x FileShare 2>/dev/null || true
TMP=/Applications/.FileShare.app.new
rm -rf "$TMP"
ditto build/FileShare.app "$TMP"
rm -rf /Applications/FileShare.app
mv "$TMP" /Applications/FileShare.app
open /Applications/FileShare.app
echo "Instalado em /Applications/FileShare.app"
echo "Se o macOS pedir acesso às Chaves, clique em \"Sempre permitir\" (acontece a cada atualização)."

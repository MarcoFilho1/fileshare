#!/bin/sh
# Compila e testa o app do tablet com a chave definitiva (em ~/.fileshare, senha nas Chaves do macOS).
# Uso: scripts/build.sh [tarefas do Gradle]   (padrão: assembleDebug testDebugUnitTest)
set -e
cd "$(dirname "$0")/.."
export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}
if [ -f "$HOME/.fileshare/release.jks" ]; then
    export FILESHARE_KEYSTORE="$HOME/.fileshare/release.jks"
    FILESHARE_KEY_PASSWORD=$(security find-generic-password -s fileshare-android-release -a release -w)
    export FILESHARE_KEY_PASSWORD
fi
./gradlew -q ${@:-assembleDebug testDebugUnitTest}

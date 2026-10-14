#!/bin/sh
# Roda os testes com só as Command Line Tools (sem Xcode): o Swift Testing fica fora do caminho padrão.
set -e
cd "$(dirname "$0")/.."
CLT=/Library/Developer/CommandLineTools/Library/Developer
if [ -d "$CLT/Frameworks/Testing.framework" ]; then
    exec swift test -Xswiftc -F"$CLT/Frameworks" -Xlinker -F"$CLT/Frameworks" \
        -Xlinker -rpath -Xlinker "$CLT/Frameworks" -Xlinker -rpath -Xlinker "$CLT/usr/lib" "$@"
fi
exec swift test "$@"

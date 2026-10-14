# FileShare

Área de transferência compartilhada entre **macOS** e **Android**: copie um texto ou uma imagem em um aparelho e cole no outro, como o Phone Link faz no Windows.

Feito e testado com um Mac (macOS 26) e um Galaxy Tab S9 FE (Android 16 / One UI 8.5).

## Status

| Versão | O que faz |
|---|---|
| **v0.1.0** | Tablet → Mac pelo botão **Enviar ao Mac** nas Configurações rápidas |
| v1.0.0 | Tablet → Mac automático: copiou, já está no Mac |
| **v1.1.0** | App de barra de menu no Mac: Mac → tablet automático |
| **v2.0.0** | Sem cabo: conexão pelo Wi-Fi, pareamento por QR code e tudo criptografado |

Veja o [plano](docs/plano.md).

### Limitações conhecidas

- Mac e tablet precisam estar no mesmo Wi-Fi.
- Um tablet pareado por vez: parear de novo substitui o anterior.
- O Android só deixa um app comum ler a área de transferência quando ele está em primeiro plano. Por isso o botão abre uma tela invisível por um instante.
- Imagens copiadas no Samsung Notes chegam como JPG (é o formato que o próprio app entrega).

## Como rodar

### Pré-requisitos (macOS)

```sh
brew install android-platform-tools openjdk@17 android-commandlinetools
sdkmanager "platforms;android-36" "build-tools;36.0.0"
```

No tablet: ative as **Opções do desenvolvedor** e a **Depuração USB** e conecte o cabo para instalar o app. Depois disso, a conexão entre os dois é pelo Wi-Fi.

### Android

```sh
cd android
echo "sdk.dir=$(brew --prefix)/share/android-commandlinetools" > local.properties
JAVA_HOME=$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home ./gradlew installDebug
```

Abra o app **FileShare** uma vez no tablet para iniciar o serviço. Depois adicione o botão **Enviar ao Mac** nas Configurações rápidas (deslize o topo da tela para baixo → lápis → arraste o botão).

### Mac

```sh
cd mac/FileShare
scripts/build-app.sh            # gera build/FileShare.app
open build/FileShare.app        # ícone ⇄ aparece na barra de menu
scripts/test.sh                 # testes (funciona só com as Command Line Tools)
```

**Parear (uma vez):** ícone ⇄ → **Parear tablet…** → aponte a câmera do tablet para o QR code e toque no link. Depois disso, com os dois no mesmo Wi-Fi, o tablet acha o Mac sozinho: copiou no Mac (inclusive print com ⌘⇧4 e imagens copiadas no Finder), já dá para colar no tablet; o que vem do tablet cai na área de transferência do Mac. Cópias de gerenciadores de senha são ignoradas.

## Segurança

- O QR code leva uma chave secreta de 32 bytes, guardada no Keychain do Mac e cifrada pelo Android Keystore no tablet.
- Cada conexão deriva chaves novas (HKDF-SHA256 com nonces dos dois lados) e cifra tudo com ChaCha20-Poly1305; mensagens repetidas ou adulteradas são recusadas.
- Sem pareamento o Mac não aparece na rede; pareado, ele se anuncia com nome genérico e só responde a quem prova ter a chave.

## Estrutura

```
android/   app Android (Java): serviço de recepção, botão e leitura da área de transferência
mac/       app de barra de menu (Swift Package, sem Xcode)
tools/     scripts de desenvolvimento e teste
docs/      plano e resultados dos testes
```

## Contribuição

Git flow: `main` recebe só versões estáveis; o trabalho acontece em `feature/*` a partir de `develop`, com PR revisado antes do merge.

## Licença

[MIT](LICENSE)

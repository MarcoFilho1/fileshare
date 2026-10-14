# FileShare

Área de transferência compartilhada entre **macOS** e **Android**: copie um texto ou uma imagem em um aparelho e cole no outro, como o Phone Link faz no Windows.

Feito e testado com um Mac (macOS 26) e um Galaxy Tab S9 FE (Android 16 / One UI 8.5).

## Status

| Versão | O que faz |
|---|---|
| **v0.1.0** | Mac → tablet automático; tablet → Mac pelo botão **Enviar ao Mac** nas Configurações rápidas |
| v1 (em teste) | Tablet → Mac automático: copiou, já está no Mac |
| próximas | Conexão por Wi-Fi com pareamento por QR code e app de barra de menu no Mac |

Hoje a conexão passa pelo **cabo USB** (túnel do `adb`). O Wi-Fi vem nas próximas versões. Veja o [plano](docs/plano.md).

### Limitações conhecidas

- Mac → tablet: por enquanto o envio é feito pelo script `tools/send_to_tablet.py`; a detecção automática de cópias no Mac chega com o app da barra de menu.
- O Android só deixa um app comum ler a área de transferência quando ele está em primeiro plano. Por isso o botão abre uma tela invisível por um instante.
- Imagens copiadas no Samsung Notes chegam como JPG (é o formato que o próprio app entrega).

## Como rodar

### Pré-requisitos (macOS)

```sh
brew install android-platform-tools openjdk@17 android-commandlinetools
sdkmanager "platforms;android-36" "build-tools;36.0.0"
```

No tablet: ative as **Opções do desenvolvedor** e a **Depuração USB**, e conecte o cabo.

### Android

```sh
cd android
echo "sdk.dir=$(brew --prefix)/share/android-commandlinetools" > local.properties
JAVA_HOME=$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home ./gradlew installDebug
```

Abra o app **FileShare** uma vez no tablet para iniciar o serviço. Depois adicione o botão **Enviar ao Mac** nas Configurações rápidas (deslize o topo da tela para baixo → lápis → arraste o botão).

### Mac

```sh
mac/receiver.py                              # recebe o que vem do tablet e põe na área de transferência
tools/send_to_tablet.py text "olá"           # envia texto ao tablet
tools/send_to_tablet.py image print.png      # envia imagem ao tablet
```

## Estrutura

```
android/   app Android (Java): serviço de recepção, botão e leitura da área de transferência
mac/       receptor provisório (Python) até o app da barra de menu
tools/     scripts de desenvolvimento e teste
docs/      plano e resultados dos testes
```

## Contribuição

Git flow: `main` recebe só versões estáveis; o trabalho acontece em `feature/*` a partir de `develop`, com PR revisado antes do merge.

## Licença

[MIT](LICENSE)

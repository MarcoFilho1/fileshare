# FileShare

Área de transferência compartilhada entre **macOS** e **Android**: copie um texto ou uma imagem em um aparelho e cole no outro, e mande arquivos nos dois sentidos, como o Phone Link faz no Windows.

Feito e testado com um Mac (macOS 26) e um Galaxy Tab S9 FE (Android 16 / One UI 8.5).

## Status

| Versão | O que faz |
|---|---|
| **v0.1.0** | Tablet → Mac pelo botão **Enviar ao Mac** nas Configurações rápidas |
| v1.0.0 | Tablet → Mac automático: copiou, já está no Mac |
| **v1.1.0** | App de barra de menu no Mac: Mac → tablet automático |
| **v2.0.0** | Sem cabo: conexão pelo Wi-Fi, pareamento por QR code e tudo criptografado |
| **v2.1.0** | Uso diário: abre sozinho com o sistema, entrega a cópia quando o tablet acorda, arquivos nos dois sentidos e o painel **Send to Tablet** |
| **v2.2.0** | Ícone e interface nova: painel no estilo da Central de Controle no Mac, tela inicial com a configuração e a permissão de acessibilidade explicada no tablet |
| **v2.3.0** | Para novos usuários: site com downloads, `FileShare.dmg` e `FileShare.apk` nas releases, e QR que abre o app ou ensina a instalar |

Veja o [plano](docs/plano.md).

### Limitações conhecidas

- Mac e tablet precisam estar no mesmo Wi-Fi.
- Um tablet pareado por vez: parear de novo substitui o anterior.
- O Android só deixa um app comum ler a área de transferência quando ele está em primeiro plano. Por isso o botão abre uma tela invisível por um instante.
- Imagens copiadas no Samsung Notes chegam como JPG (é o formato que o próprio app entrega).
- Depois de atualizar o app do Mac, o macOS pede de novo acesso às Chaves: clique em **Sempre permitir**.
- Os avisos de arquivo recebido no Mac só aparecem com as notificações do FileShare ligadas (o menu ⇄ mostra **Ativar notificações de arquivos…** quando estão desligadas).

## Instalar

Baixe pelo site: **https://marcofilho1.github.io/fileshare/**. Os mesmos arquivos estão em [Releases](https://github.com/MarcoFilho1/fileshare/releases/latest).

1. **Mac:** abra o `FileShare.dmg` e arraste o app para Aplicativos. Como o app ainda não é notarizado pela Apple, na primeira vez o macOS avisa que não conseguiu verificá-lo. Clique em OK e vá em **Ajustes do Sistema → Privacidade e Segurança → Abrir mesmo assim**.
2. O app do Mac abre mostrando um **QR code**. Leia com a câmera do tablet e toque no link.
3. **Tablet:** a página do link abre o FileShare e pareia. Sem o app instalado, ela mostra como baixar o `FileShare.apk`. Depois de instalar, é só voltar à página e tocar em **Conectar**, sem ler o QR de novo. A chave do pareamento vai depois do `#` no link: o navegador nunca a envia ao site, e a página não carrega nada de fora.

## Compilar a partir do código

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

Sem a chave de lançamento, o build usa a chave de teste do Android. Os arquivos da release são gerados por `scripts/package.sh` (`dist/FileShare.dmg` e `dist/FileShare.apk`), que assina o APK com a chave definitiva guardada fora do repositório.

Abra o app **FileShare** uma vez no tablet para iniciar o serviço. Depois adicione o botão **Enviar ao Mac** nas Configurações rápidas (deslize o topo da tela para baixo → lápis → arraste o botão).

### Mac

```sh
cd mac/FileShare
scripts/build-app.sh            # gera build/FileShare.app
open build/FileShare.app        # ícone ⇄ aparece na barra de menu
scripts/test.sh                 # testes (funciona só com as Command Line Tools)
```

**Parear (uma vez):** na primeira vez que abre, o app do Mac já mostra o QR code (depois, clique no ícone ⇄ → **Parear tablet…**). Aponte a câmera do tablet para o código e toque no link. Depois disso, com os dois no mesmo Wi-Fi, o tablet acha o Mac sozinho: copiou no Mac (inclusive print com ⌘⇧4 e imagens copiadas no Finder), já dá para colar no tablet; o que vem do tablet cai na área de transferência do Mac. Cópias de gerenciadores de senha são ignoradas.

## Arquivos

- **Tablet → Mac:** em qualquer app, **Compartilhar → FileShare** (ou o atalho com o nome do Mac). O arquivo cai em `~/Downloads/FileShare`.
- **Mac → tablet**, de três jeitos:
  - **Arrastar até o ícone ⇄:** quando um arquivo arrastado chega perto do ícone, o painel **Send to Tablet** sai de dentro dele, no mesmo vidro da Central de Controle. É só soltar no painel; ele mostra o progresso e confirma a entrega. Se o tablet estiver dormindo, o arquivo espera e vai quando ele acordar.
  - Ícone ⇄ → **Enviar arquivo ao tablet…**
  - No Finder, botão direito → **Ações Rápidas** (ou **Serviços**) → **Enviar ao tablet**.

  No tablet, os arquivos ficam em `Download/FileShare`, e a notificação abre o arquivo no app que você escolher. Limite de 100 MB por arquivo.

Para perceber o arrasto chegando perto, o app observa só os movimentos do mouse com o botão apertado. Ele não lê o teclado e não precisa de permissão especial.

## Interface

- **Mac:** clicar no ícone ⇄ abre um painel no estilo da Central de Controle, com o tablet e o estado da conexão, botões para pausar a sincronização e abrir ao iniciar, a atividade recente (com o progresso dos arquivos) e atalhos para enviar um arquivo ou abrir os recebidos.
- **Tablet:** o app mostra o Mac pareado com o estado da conexão ao vivo e uma lista do que falta configurar (cópia automática, notificações, bateria sem restrição e botão nas Configurações rápidas). Cada item tem um botão que leva direto ao ajuste certo.
- Textos em português ou inglês, conforme o idioma do aparelho. O ícone do app é gerado por `mac/FileShare/scripts/make-icon.swift`; o do Android usa a mesma geometria.

## Uso diário

- **Abre sozinho:** o app do Mac abre junto com o sistema (botão **Abrir ao iniciar** no painel do ícone ⇄); o serviço do tablet volta sozinho depois de reiniciar ou atualizar.
- **Tablet dormindo:** o Mac guarda a última cópia por 10 minutos e entrega quando o tablet acorda e reconecta; os arquivos esperam na fila do mesmo jeito.

## Bateria

O macOS não avisa os apps quando algo é copiado (no Windows e no Android há esse aviso). Por isso o FileShare do Mac, como todo gerenciador de área de transferência para Mac (Maccy, Raycast, Paste…), consulta a cada 0,5 s um **contador** do sistema que muda a cada cópia. É a leitura de um único número; o conteúdo só é lido quando o contador muda, ou seja, quando você copiou algo.

Essa checagem tem **folga** de 0,2 s: o macOS pode atrasá-la um pouco para fazê-la num momento em que o processador já acordou por outro motivo (relógio, rede, outros apps). Na maior parte das vezes o FileShare pega **carona** nesses despertares em vez de acordar o processador só para ele, e uma cópia continua sendo percebida em até 0,7 s.

Entre os aparelhos não há varredura: a conexão fica aberta e cada lado manda a cópia na hora em que ela acontece. O único tráfego periódico é um sinal do tablet a cada 20 s para saber se a conexão continua viva.

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

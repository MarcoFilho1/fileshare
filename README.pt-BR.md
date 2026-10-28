<h1 align="center">
  <img alt="" src="site/icon.png" width="96"><br>
  FileShare
</h1>

<p align="center">
  <a href="README.md">English</a> · <b>Português</b>
</p>

<p align="center">
  Copie no Mac, cole no tablet Android. E o contrário.<br>
  Texto, imagens e arquivos pelo seu próprio Wi-Fi, criptografados de ponta a ponta. Sem conta, sem nuvem.
</p>

<p align="center">
  <a href="https://marcofilho1.github.io/fileshare/"><b>Site</b></a> ·
  <a href="#instalar"><b>Instalar</b></a> ·
  <a href="#recursos"><b>Recursos</b></a> ·
  <a href="#perguntas-frequentes"><b>Perguntas</b></a> ·
  <a href="LICENSE"><b>Licença MIT</b></a>
</p>

<p align="center">
  <img alt="Uma foto é copiada no Mac com ⌘C, colada num app de notas no tablet e anotada com a caneta" src="docs/media/copy-paste.gif" width="800">
</p>

> [!TIP]
> **Gostou ou te ajudou?** ⭐ [Deixe uma estrela no repositório](https://github.com/MarcoFilho1/fileshare): é o que ajuda outras pessoas a encontrar o FileShare.

## Por quê

O Phone Link faz um PC com Windows e um Android parecerem um só: copiou num, cola no outro. Entre o Mac e o Android não havia nada parecido, e todo print, link ou PDF virava um e-mail para você mesmo, uma conversa no WhatsApp ou um cabo.

O FileShare resolve isso. O Mac e o tablet passam a ter uma área de transferência só: copie uma foto no Mac e cole direto no Samsung Notes para escrever por cima com a S Pen; copie um trecho das suas notas no tablet e use ⌘V no Mac. Arquivos de qualquer tamanho também vão nos dois sentidos (e pastas inteiras, do Mac para o tablet), com um toque ou um arrasto. Tudo vai direto de um aparelho para o outro pelo seu Wi-Fi, criptografado, sem passar por nenhum servidor.

Foi feito e testado com um MacBook Air (macOS 26) e um Galaxy Tab S9 FE (Android 16 / One UI 8.5).

## Instalar

### 1. No Mac

<p>
  <a href="https://github.com/MarcoFilho1/fileshare/releases/latest/download/FileShare.dmg"><b>⬇ Baixar FileShare.dmg</b></a> · macOS 14 ou mais novo
</p>

> [!IMPORTANT]
> **Na primeira vez que você abrir, o macOS vai bloquear o FileShare. É esperado.**
>
> <img alt="Aviso do macOS (em inglês): “FileShare.app” Not Opened. Apple could not verify “FileShare.app” is free of malware. Botões: Move to Trash e Done." src="docs/media/macos-alert.png" width="240" align="right">
>
> O FileShare é gratuito e ainda não é notarizado pela Apple (um programa pago), por isso o macOS mostra este aviso. Para abrir:
>
> 1. Abra o `FileShare.dmg`, arraste o FileShare para **Aplicativos** e abra-o.
> 2. No aviso, clique no **botão de baixo** (*Done* no macOS em inglês). **Não** clique em *Move to Trash* (Mover para o Lixo), o botão azul de cima.
> 3. Abra **Ajustes do Sistema → Privacidade e Segurança**, role até **Segurança** e clique em **Abrir mesmo assim**. Confirme com a sua senha ou o Touch ID.
>
>    <img alt="Ajustes do Sistema (em inglês), Privacidade e Segurança: “FileShare.app” foi bloqueado para proteger o Mac, com o botão Open Anyway (Abrir mesmo assim)" src="docs/media/macos-open-anyway.png" width="460">
>
> Pronto: daí em diante ele abre normalmente. O código é aberto, então dá para conferir tudo neste repositório.

O app fica na barra de menu (o ícone ⇄) e abre mostrando um QR code para parear o tablet.

### 2. No tablet

<p>
  <a href="https://github.com/MarcoFilho1/fileshare/releases/latest/download/FileShare.apk"><b>⬇ Baixar FileShare.apk</b></a> · Android 13 ou mais novo
</p>

O jeito mais fácil: **leia o QR code do Mac com a câmera do tablet** e toque no link. Se o FileShare já estiver instalado, a página abre o app e pareia; se não, ela mostra como baixar, e depois de instalar é só voltar e tocar em **Conectar**, sem ler o QR de novo. Ao instalar, o Android pede para permitir apps desta fonte (só na primeira vez).

<p align="center">
  <img alt="A janela de pareamento do Mac: um QR code com o ícone do FileShare no meio e três passos numerados" src="docs/media/pairing.png" width="340">
</p>

### 3. Configure no tablet

O app do tablet mostra a conexão ao vivo e uma lista curta do que vale ativar, cada item com um botão que leva direto ao ajuste certo: notificações, bateria sem restrição (para o tablet não cortar a conexão quando dorme), o botão **Enviar ao Mac** nas Configurações rápidas e a **permissão de acessibilidade** da cópia automática.

<p align="center">
  <img alt="O app do tablet: o Mac pareado como Conectado, criptografado, e a lista de configuração com notificações, bateria sem restrição e o botão Enviar ao Mac" src="docs/media/tablet-home.png" width="420">
  <img alt="O cartão da permissão de acessibilidade: Cópia automática, Permitida, com os botões Revogar e Mostrar detalhes" src="docs/media/tablet-access.png" width="420">
</p>

> [!NOTE]
> **Por que acessibilidade?** Só para a cópia automática: o Android só avisa um app de que você tocou em *Copiar* por meio de um serviço de acessibilidade. O FileShare recebe apenas o nome do botão tocado e avisos do sistema como "Copiado"; ele não consegue ler a tela nem o que você digita. É opcional: sem ela, use o botão Enviar ao Mac. O cartão explica isso e deixa revogar quando quiser.

## Recursos

### Uma área de transferência para os dois

Copie um texto ou uma imagem num aparelho e cole no outro, sem botão e sem abrir app. Inclusive prints do Mac (⌘⇧4). Cópias de gerenciadores de senha são ignoradas de propósito.

<p align="center">
  <img alt="Um trecho selecionado no Samsung Notes é copiado no tablet e aparece num documento no Mac com ⌘V" src="docs/media/back.gif" width="800">
</p>

### Arraste o arquivo até o ⇄

Quando um arquivo arrastado chega perto do ícone na barra de menu, o painel **Send to Tablet** sai de dentro dele, no mesmo vidro da Central de Controle. Soltou, o arquivo vai para o tablet, com progresso e confirmação. Também dá para usar o painel do ⇄ (**Enviar arquivo…**) ou o Finder (botão direito → **Ações Rápidas** ou **Serviços** → **Enviar ao tablet**).

<p align="center">
  <img alt="Um PDF é arrastado até o ícone da barra de menu; o painel Send to Tablet aparece, mostra o progresso e um ✓, e uma notificação chega no tablet" src="docs/media/drag.gif" width="800">
</p>

### Exporte o PDF direto para o Mac

No Samsung Notes (ou em qualquer app), toque em **⋮ → Compartilhar** e escolha o seu Mac na fileira de cima, no mesmo lugar onde aparece o "Ligar ao Windows" do Phone Link. O arquivo cai em **Downloads › FileShare** e o Mac avisa; clique no aviso para abrir.

<p align="center">
  <img alt="No Samsung Notes, o menu de três pontos abre, Compartilhar é tocado, a folha de compartilhamento mostra o Mac ao lado do Ligar ao Windows, o Mac é tocado e um aviso chega no Mac" src="docs/media/pdf.gif" width="800">
</p>

### As últimas cópias à mão

A aba **Cópias** do painel guarda as últimas 10 cópias trocadas, com miniatura das imagens e de onde cada uma veio. Clique numa e ela volta a ser a cópia atual no Mac e no tablet. Fica só na memória e tem o botão **Limpar**.

### Links que abrem no outro aparelho

No tablet, **Compartilhar → Abrir no Mac** abre a página no navegador do Mac. Copie um link no Mac e o tablet mostra o aviso **Link do Mac** com **Abrir**. Só links da web (http/https) são abertos.

### Um painel que parece parte do macOS

Clique no ⇄ para abrir um painel no estilo da Central de Controle: o tablet, a conexão e a bateria, botões redondos de **Sync** (pausar) e **Abrir ao iniciar**, a atividade recente com o progresso dos arquivos e atalhos para enviar um arquivo ou abrir os recebidos.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/mac-panel-dark.png">
    <img alt="O painel do ⇄: Galaxy Tab S9 FE conectado e criptografado, botões Sync e Abrir ao iniciar, atividade recente, Enviar arquivo e Recebidos" src="docs/media/mac-panel-light.png" width="360">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/media/send-to-tablet-dark.png">
    <img alt="O painel Send to Tablet aceso em azul com Solte para enviar" src="docs/media/send-to-tablet-light.png" width="300">
  </picture>
</p>

Os textos do app acompanham o idioma do aparelho; as imagens do Mac estão em inglês porque o Mac usado nelas está em inglês.

### Um longe do outro? Ele espera

Nos dois sentidos. O Mac guarda a última cópia por até 10 minutos e os arquivos ficam na fila até o tablet acordar. O tablet faz o mesmo quando o Mac está longe: a última cópia espera 10 minutos e os arquivos compartilhados esperam até 24 horas, com o aviso **Esperando o Mac** e o botão **Cancelar**. Quando os dois se encontram de novo na rede (em poucos segundos), tudo é entregue; se você copiou algo mais novo enquanto isso, a sua cópia mais nova é que fica. Os dois apps sobem sozinhos: o do Mac ao entrar no sistema, o serviço do tablet depois de reiniciar ou atualizar.

## Perguntas frequentes

**Precisa de internet?** Não, mas precisa de Wi-Fi: o Mac e o tablet têm que estar na **mesma rede**. O que você copia vai direto de um para o outro pelo roteador e nunca passa pela internet, então funciona até com a internet fora do ar, desde que o roteador esteja ligado.

**Funciona fora de casa?** Em qualquer rede em que os dois estejam juntos, como a do trabalho. Algumas redes públicas (hotel, faculdade, aeroporto) bloqueiam a conversa entre aparelhos.

**Onde ficam os arquivos recebidos?** No Mac, em `Downloads/FileShare`; no tablet, em `Download/FileShare`. Sem limite de tamanho, só o espaço livre de quem recebe; se o Wi-Fi cair no meio, o envio continua de onde parou. Pastas inteiras também vão (Mac → tablet).

**É rápido?** Depende mais do seu Wi-Fi do que do app. Com os dois aparelhos numa rede de 5 GHz, medimos 1 GB em 95 s (11 MB/s) do Mac para o tablet, e um CSV de 200 MB em 4,9 s (41 MB/s), porque textos e planilhas vão comprimidos sem você perceber. O arquivo sempre chega idêntico. Detalhes em [docs/metricas.md](docs/metricas.md).

**Alguém na mesma rede pode ver o que eu copio?** Não. Tudo é criptografado com uma chave que só os seus dois aparelhos têm, criada no pareamento. Sem essa chave, o aparelho é recusado, e sem pareamento o Mac nem aparece na rede.

**Funciona com outros Androids?** Deve funcionar no Android 13 ou mais novo, mas foi testado num Galaxy Tab S9 FE. Em outras marcas, a cópia automática pode não reconhecer o botão Copiar; o Enviar ao Mac e o Compartilhar funcionam em todos.

**iPhone, iPad ou Windows?** Por enquanto não: é Mac com Android.

Mais respostas no [site](https://marcofilho1.github.io/fileshare/#perguntas).

## Bateria

O macOS não avisa os apps quando algo é copiado (no Windows e no Android há esse aviso). Por isso o FileShare do Mac, como todo gerenciador de área de transferência para Mac (Maccy, Raycast, Paste…), consulta a cada 0,5 s um **contador** do sistema que muda a cada cópia. É a leitura de um único número; o conteúdo só é lido quando o contador muda, ou seja, quando você copiou algo.

Essa checagem tem **folga** de 0,2 s: o macOS pode atrasá-la um pouco para fazê-la num momento em que o processador já acordou por outro motivo (relógio, rede, outros apps). Na maior parte das vezes o FileShare pega **carona** nesses despertares em vez de acordar o processador só para ele, e uma cópia continua sendo percebida em até 0,7 s.

Entre os aparelhos não há varredura: a conexão fica aberta e cada lado manda a cópia na hora em que ela acontece. O único tráfego periódico é um sinal do tablet a cada 20 s para saber se a conexão continua viva.

## Segurança

- O QR code leva uma chave secreta de 32 bytes, guardada no Keychain do Mac e cifrada pelo Android Keystore no tablet.
- Cada conexão deriva chaves novas (HKDF-SHA256 com nonces dos dois lados) e cifra tudo com ChaCha20-Poly1305; mensagens repetidas ou adulteradas são recusadas.
- Sem pareamento o Mac não aparece na rede; pareado, ele se anuncia com nome genérico e só responde a quem prova ter a chave.
- O QR é um link para o site com a chave depois do `#`, parte que o navegador nunca envia a um servidor; a página tira a chave da barra de endereço logo ao abrir e não carrega nada de fora.

## Compilar a partir do código

Pré-requisitos (macOS):

```sh
brew install android-platform-tools openjdk@17 android-commandlinetools
sdkmanager "platforms;android-36" "build-tools;36.0.0"
```

**Android** (ative a Depuração USB no tablet e conecte o cabo para instalar):

```sh
cd android
echo "sdk.dir=$(brew --prefix)/share/android-commandlinetools" > local.properties
JAVA_HOME=$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home ./gradlew installDebug
```

**Mac** (Swift Package, sem Xcode):

```sh
cd mac/FileShare
scripts/build-app.sh       # gera build/FileShare.app
scripts/install.sh         # instala em /Applications e abre
scripts/test.sh            # testes (funciona só com as Command Line Tools)
```

**Arquivos da release:** `scripts/package.sh` gera `dist/FileShare.dmg` e `dist/FileShare.apk`, assinando o APK com a chave de lançamento guardada fora do repositório. Sem essa chave, o build usa a chave de teste do Android.

```
android/   app Android (Java): serviço de conexão, área de transferência, Compartilhar, botão rápido
mac/       app de barra de menu (Swift Package): conexão, área de transferência, painéis, pareamento
site/      o site (GitHub Pages), publicado pelo workflow Site
scripts/   empacotamento da release
tools/     utilitários de desenvolvimento
docs/      plano, resultados dos testes e as imagens do README
```

**Contribuição:** a `main` recebe só versões estáveis; o trabalho acontece em branches `feature/*` a partir da `develop`, com pull request revisado. Issues e ideias são bem-vindas.

## Licença

[MIT](LICENSE)

<p align="center">
  Se o FileShare te ajudou, ⭐ <a href="https://github.com/MarcoFilho1/fileshare"><b>deixe uma estrela no repositório</b></a>. Obrigado!
</p>

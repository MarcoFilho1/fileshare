# Plano das próximas versões (2.4 → 3.0)

Escrito em 27/10/2026, a partir da v2.3.1. Cada etapa vira uma versão própria, com PRs `feature/*` → `develop` e uma release `develop` → `main` só depois de testada no Mac e no tablet. As etapas estão em ordem: primeiro o que corrige incômodos e é barato, por último o que é grande e arriscado.

| Etapa | Versão | O que entrega | Tamanho |
|---|---|---|---|
| 0 | junto da 2.4 | Os apps passam a aceitar mensagens novas sem cair | pequeno |
| 1 | 2.4.0 | App não trava no pedido das Chaves · tablet → Mac com o Mac longe · bateria do tablet no painel | médio |
| 2 | 2.5.0 | Histórico da área de transferência no painel · abrir link no outro aparelho | médio |
| 3 | 2.6.0 | Arquivos grandes (até 2 GB) e pastas | médio |
| 4 | 2.7.0 | Notificações do tablet no Mac | grande |
| 5 | 3.0.0 | Receber do celular pelo Quick Share | muito grande |

---

## Etapa 0: compatibilidade entre versões

**Por quê.** Hoje, se o Mac ou o tablet recebe um tipo de mensagem que não conhece, ele encerra a conexão (`Wire.decodeMessage` no Mac e `Wire.java` no Android jogam erro). Toda etapa abaixo cria mensagens novas, e as pessoas não atualizam os dois apps no mesmo dia: um Mac 2.4 com um tablet 2.3 ficaria se desconectando.

**O que muda.**
- Cada lado passa a **ignorar** mensagens desconhecidas, sem derrubar a conexão.
- O `HELLO` passa a levar a versão e uma lista de recursos (por exemplo `HELLO Marco MacBook Air;v=2.4;caps=batt,held,hist`). Cada lado só envia uma mensagem nova se o outro anunciou que a entende.
- Os testes cobrem: mensagem desconhecida não derruba, `HELLO` antigo (sem recursos) continua funcionando.

**Limite.** Um app 2.3 continua caindo se receber algo novo. Por isso a regra de só enviar o que o outro anunciou vale desde já.

---

## Etapa 1 (v2.4.0): os incômodos de hoje

### 1.1 Pedido das Chaves a cada atualização do Mac (investigado em 27/10)

**O que se tentou.** Assinar todas as versões com um certificado próprio, para o macOS reconhecer cada atualização como o mesmo app.

**O que se descobriu.**
- O certificado próprio deixa a identidade do app estável, mas **o macOS continua perguntando a cada build nova**.
- Sem um Team ID, que só a Apple emite, as Chaves amarram a permissão à impressão digital exata de cada build. Um campo de equipe (OU) no certificado próprio não gera Team ID.
- O "chaveiro moderno" (*data protection keychain*) exige uma permissão da conta paga da Apple (erro `-34018`).

**Decisão (27/10).**
- A chave do pareamento **continua nas Chaves**, que protegem mais que um arquivo, e o "Sempre permitir" a cada atualização continua.
- O certificado próprio foi descartado.
- Só o Apple Developer Program resolveria, junto com o aviso do Gatekeeper.

**O que entra na 2.4 mesmo assim.**
- A chave é lida **fora da thread principal**: o app não trava enquanto o macOS pergunta.
- Uma **recusa** nas Chaves não é mais tratada como "não pareado". Antes, o app abriria o pareamento e substituiria a chave boa. Agora ele avisa no painel e tenta de novo na próxima abertura.

### 1.2 Tablet → Mac com o Mac longe ou desligado

**O que o usuário vê.** Copiou algo ou compartilhou um arquivo no tablet com o Mac fechado: aparece "Guardado, vai para o Mac quando ele estiver por perto". Quando o Mac volta, chega tudo, e o tablet avisa "3 arquivos enviados ao Mac".

**Como funciona.**
- **Cópia:** o tablet guarda a última cópia por 10 minutos e a entrega ao reconectar com a mensagem `HELD`, como o Mac já faz no sentido contrário. O Mac só cola se ninguém copiou nada mais novo nele nesse meio-tempo.
- **Arquivos:** ficam numa fila no armazenamento do app. O arquivo é copiado para a fila na hora de compartilhar, porque a permissão de leitura que o Android dá ao app expira.
- **Notificação no tablet:** fixa enquanto há algo na fila, com o botão **Cancelar**.
- **Limites:** a fila guarda até 500 MB ou 24 h, e o que passa disso é descartado com aviso.

**Reconexão (descoberto no teste, 27/10).** A volta levava até 2,5 min: depois de uma conexão que caía com erro, o tablet mantinha a espera máxima, e só procurava o Mac 15 s a cada 45 s. Agora ele escuta a rede quase o tempo todo e volta a tentar rápido depois de uma conexão, voltando **em cerca de 2 s** quando o Mac reaparece.

**Testes.** Mac desligado → compartilhar dois arquivos → ligar o Mac → os dois chegam. Copiar no tablet → copiar outra coisa no Mac → reconectar → o Mac não perde a própria cópia.

### 1.3 Bateria do tablet no painel do Mac

**O que o usuário vê.** No painel ⇄: "Galaxy Tab S9 FE · Conectado · 🔋 72%", com um raio quando está carregando.

**Como funciona.** O tablet envia `BATT 72 1` (nível e se está carregando) ao conectar e quando a porcentagem ou o carregamento muda. Na prática, o nível muda cerca de 1% a cada 6 minutos. O Android avisa as mudanças sozinho, então isso não gasta bateria a mais.

---

## Etapa 2 (v2.5.0): histórico e links

### 2.1 Histórico da área de transferência no painel ⇄

**O que o usuário vê.** Uma seção "Recentes" no painel com as **últimas 10 cópias trocadas** entre os aparelhos: texto (primeira linha) ou miniatura da imagem, a origem (Mac ou tablet) e há quanto tempo. Um clique recoloca a cópia na área de transferência do Mac. Um botão ao lado manda a cópia de novo para o tablet. Há também **Limpar histórico**.

**Privacidade.**
- O histórico fica **só na memória** e some ao fechar o app.
- Cópias de gerenciadores de senha continuam fora, como hoje.
- Para imagens, guarda-se a miniatura e o original até 25 MB. As mais antigas saem primeiro.

**Por que só no Mac.** O teclado da Samsung já tem histórico da área de transferência no tablet.

### 2.2 Abrir um link no outro aparelho

**O que o usuário vê.**
- **Tablet → Mac:** no menu Compartilhar de um link (navegador, YouTube…), aparece **Abrir no Mac** ao lado do "Mac" que já existe. O link abre no navegador do Mac.
- **Mac → tablet:** ao copiar no Mac algo que é só um link, o tablet mostra uma notificação "Link do Mac" com o botão **Abrir**. O Android não deixa um app abrir telas sozinho em segundo plano, então o toque no botão é necessário.

**Como funciona.** Mensagem nova `OPEN url`. Só endereços `http` e `https` são aceitos, para não abrir apps ou arquivos por engano.

---

## Etapa 3 (v2.6.0): arquivos grandes e pastas

**O que o usuário vê.**
- O limite passa de 100 MB para **2 GB**, com barra de progresso e botão **Cancelar** dos dois lados.
- **Pastas:** arrastar uma pasta para o ⇄ funciona. Ela chega no tablet como uma pasta, não como um .zip.

**Como funciona.**
- O envio já é feito em pedaços de 512 KB. O que limita hoje é a regra dos 100 MB e o cálculo do espaço livre. Antes de aceitar, cada lado confere se há espaço, e a gravação continua direto no disco, sem segurar o arquivo inteiro na memória.
- **Pasta:** o Mac compacta numa pasta temporária, envia como um arquivo com a marca de "pasta" e o tablet descompacta em `Download/FileShare/<nome>`. A descompactação **recusa caminhos que tentem sair da pasta** (`../`), para proteger o tablet.
- **Vários arquivos de uma vez:** o tablet passa a aceitar compartilhar vários arquivos juntos, e eles vão em sequência.
- Se a conexão cair no meio, o envio recomeça do zero na v2.6. Continuar de onde parou fica para depois.

**Testes.** Um vídeo de 1,5 GB nos dois sentidos, uma pasta com subpastas e acentos nos nomes, e o tablet sem espaço (precisa recusar com aviso).

---

## Etapa 4 (v2.7.0): notificações do tablet no Mac

**O que o usuário vê.** Chegou uma mensagem no tablet: aparece no Mac como notificação, com o ícone e o nome do app ("WhatsApp: Ana — chego em 10 min"). Fechar a notificação no Mac fecha também no tablet.

**Como funciona.**
- **Permissão nova no tablet: "Acesso a notificações".** É uma permissão especial do Android. Fica como mais um item na lista de Configuração do app, opcional e com explicação do que é lido.
- O tablet envia `NOTIF app título texto ícone`. O Mac mostra pelo sistema de notificações do macOS.
- **Escolha de apps:** por padrão, só apps de mensagens e e-mail. A lista completa fica no tablet para ligar e desligar.
- **Não espelha:** notificações fixas (música, download, o próprio FileShare), notificações silenciosas e as do modo Não Perturbe.
- **Códigos de verificação:** desde o Android 15, o sistema esconde o texto de notificações sensíveis (como códigos SMS) de apps comuns. Elas vão aparecer no Mac sem o código. É uma proteção do Android, e o plano não tenta contornar.

**Fica para depois:** responder pelo Mac. Dá para fazer com as ações de resposta do Android, mas aumenta muito a superfície de testes.

**Risco.** É a parte com mais dado pessoal do projeto. Tudo continua cifrado e só na rede local, e nada é gravado em disco no Mac.

---

## Etapa 5 (v3.0.0): receber do celular pelo Quick Share

**O que o usuário vê.** Num celular Android qualquer da casa, sem o FileShare instalado: **Compartilhar → Quick Share → "Mac do Marco"**. O Mac pergunta "Aceitar 3 fotos do Galaxy S24?" e salva em `Downloads/FileShare`.

**Como funciona.**
- O Mac passa a anunciar na rede local o serviço que o Quick Share procura e a falar o protocolo dele: o aperto de mão criptografado UKEY2 e mensagens em protobuf.
- O projeto **NearDrop** (código aberto, em Swift) já fez a engenharia reversa desse protocolo para receber no Mac. O plano é **estudar o NearDrop**, conferir a licença antes de reaproveitar qualquer código e implementar só o recebimento.
- O Mac sempre pede confirmação. Ninguém consegue largar arquivos no Mac sem você aceitar.
- Pode ser desligado no painel: **Visível para o Quick Share**.

**Riscos.**
- É um protocolo do Google sem documentação oficial e pode mudar sem aviso.
- Pode exigir Wi-Fi e Bluetooth no celular, e alguns aparelhos só mostram dispositivos de contatos.
- É a etapa mais longa. Começa com um **teste de viabilidade**: um celular envia uma foto e o Mac recebe. Só segue para a versão se esse teste passar.

**Fica de fora:** enviar do Mac para celulares pelo Quick Share. O tablet pareado continua usando o canal próprio do FileShare.

---

## Itens que acompanham todas as etapas

- **Testes:** os automáticos (Mac `scripts/test.sh`) ganham casos para cada mensagem nova. Cada versão passa por um roteiro manual no Mac e no Tab S9 FE antes da release.
- **Site e README:** cada recurso novo entra nas duas línguas, com print ou GIF sem dados pessoais.
- **Pendências antigas que entram quando couber:**
  - teste de uma noite inteira com o tablet conectado;
  - colar no GoodNotes;
  - reconexão lenta logo depois de reinstalar o app;
  - opção "Mac" na seleção inteligente da S Pen.

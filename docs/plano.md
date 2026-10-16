# Plano do MVP

Objetivo: copiar texto e imagens no Mac e colar no tablet sem fazer nada; do tablet para o Mac com o mínimo de toques. Só na rede local, criptografado, para uso pessoal.

## Testes de viabilidade (14/10/2026)

| # | Teste | Resultado |
|---|---|---|
| T1 | App em segundo plano grava imagem na área de transferência do tablet | ✅ colou no Samsung Notes (GoodNotes não testado) |
| T2 | Botão nas Configurações rápidas lê texto e imagem | ✅ após tratar o HTML do Samsung Notes e a visibilidade de pacote |
| T3 | Mac lê a área de transferência a cada 0,5 s (macOS 26.4) | ✅ sem pedido de permissão; ⌘⇧4 chega como PNG |
| T4 | Serviço do tablet sobrevive à noite | pendente |
| T5 | Tablet → Mac automático por serviço de acessibilidade | ✅ texto; imagem em teste após corrigir a perda de dados no túnel do adb |

Descobertas:

- O Samsung Notes copia tudo como `text/html`; imagens vêm como `<img src="content://0@...">` de um provider dele.
- O túnel do `adb` não repassa o fechamento só da escrita (half-close): o protocolo leva o tamanho no cabeçalho e uma confirmação `k`.

## Versões

- **v0.1.0** botão Enviar ao Mac · **v1.0.0** cópia automática tablet → Mac · **v1.1.0** app do Mac, Mac → tablet automático · **v2.0.0** Wi-Fi + pareamento por QR + criptografia · **v2.1.0** uso diário (etapa D) · **v2.2.0** ícone e interface nova.

## Etapa D: uso diário (v2.1.0)

1. ✅ App do Mac abre junto com o sistema; serviço do tablet volta sozinho após reiniciar, atualizar ou ligar a acessibilidade.
2. ✅ Tablet em repouso: o Mac guarda a última cópia por 10 min e entrega quando o tablet acorda (reconecta ao ligar a tela).
3. ✅ Arquivos tablet → Mac pelo menu Compartilhar (com atalho direto do Mac), salvos em `~/Downloads/FileShare`.
4. ✅ Arquivos Mac → tablet: arrastar até o ⇄ (painel **Send to Tablet**, abre ao aproximar), menu e Finder; salvos em `Download/FileShare`.
5. ✅ Folga no timer da área de transferência do Mac (bateria).

## Próximas etapas

- T4: serviço do tablet durante uma noite inteira; colar no GoodNotes.
- Assinatura estável do app do Mac, para não pedir acesso às Chaves a cada atualização, e leitura das Chaves fora da thread principal.
- Tablet → Mac com o Mac fora do alcance: hoje só mostra um aviso; guardar e mandar depois.
- Reconexão lenta do tablet logo depois de reinstalar o app.
- Opção "Mac" na seleção inteligente da S Pen e guia de exceções de bateria do One UI.
- Pesquisa: Quick Share no Mac (NearDrop).

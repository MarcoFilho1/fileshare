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

- **v0.1.0** botão Enviar ao Mac · **v1.0.0** cópia automática tablet → Mac · **v1.1.0** app do Mac, Mac → tablet automático · **v2.0.0** Wi-Fi + pareamento por QR + criptografia.

## Próximas etapas (D: uso diário)

1. App do Mac abre junto com o sistema; serviço do tablet volta sozinho após reiniciar ou atualizar.
2. Conexão com o tablet em repouso (Doze/economia de bateria do One UI) e guia de exceções de bateria.
3. Opção "Mac" no menu Compartilhar e na seleção inteligente da S Pen.

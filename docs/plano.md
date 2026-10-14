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

## Próximas etapas

1. **Conexão Wi-Fi**: descoberta por Bonjour, pareamento por QR code com chave compartilhada, mensagens criptografadas, reconexão automática.
2. **App do Mac (Swift)**: barra de menu, detecção automática de cópias (texto, PNG/TIFF, arquivos de imagem do Finder), ignora senhas de gerenciadores (`org.nspasteboard.ConcealedType`).
3. **Uso diário**: abrir com o sistema, retomar após reiniciar o tablet, guia de bateria do Samsung, opção "Mac" no menu Compartilhar e na seleção inteligente da S Pen.

# Métricas de transferência

Velocidades reais medidas com o FileShare, sempre com o ambiente junto: a velocidade depende mais do Wi-Fi que do app. Desde a 2.6, os dois apps registram no log o tamanho, o tempo e a velocidade de cada arquivo:
- **Mac:** linhas "enviado ao tablet" e "recebido do tablet";
- **tablet:** linhas "file sent to Mac" e "file from Mac saved".

## Recorde atual

| Sentido | Velocidade média | Arquivo | Ambiente |
|---|---|---|---|
| Mac → tablet | **5,2 MB/s** (picos de 7,5 MB/s) | 1,5 GB em 303 s, chegou idêntico (SHA-256) | Mac em 5 GHz, tablet em 2,4 GHz |
| Tablet → Mac | **~3,6 MB/s** (antes da queda) | 1,5 GB em 532 s com uma queda no meio, chegou idêntico | Mac em 5 GHz, tablet em 2,4 GHz |

## Medições

| Data | Versão | Sentido | Arquivo | Tempo | Média | Ambiente | Observação |
|---|---|---|---|---|---|---|---|
| 27/10/2026 | 2.6.0 (dev) | Mac → tablet | 1,5 GB (aleatório) | — | ~3 MB/s | Mac e tablet em 2,4 GHz (canal 11, 20 MHz), mesmo roteador | Interrompido pela troca de rede do Mac, recomeçou do zero |
| 27/10/2026 | 2.6.0 (dev) | Mac → tablet | 1,5 GB (aleatório) | 303 s | 5,2 MB/s | Mac em 5 GHz (canal 153, 40 MHz, 309 Mb/s); tablet em 2,4 GHz (2462 MHz, 98–138 Mb/s) | Picos de 7,5 MB/s; o gargalo é o tablet em 2,4 GHz |
| 27/10/2026 | 2.6.0 (dev) | Tablet → Mac | 1,5 GB (aleatório) | 532 s | 2,8 MB/s (com a queda) | Igual à anterior | Wi-Fi do tablet desligado por ~5 s no meio: continuou de 253 MB, sem recomeçar; ~3,6 MB/s enquanto enviava |
| 27/10/2026 | 2.6.0 (dev) | Mac → tablet | Pasta: 4 arquivos, 294 KB | 0,5 s | — | Igual à anterior | Subpastas e acentos preservados, .DS_Store fora |

## Aparelhos

- **Mac:** MacBook Air (macOS 26), Wi-Fi 802.11ax.
- **Tablet:** Galaxy Tab S9 FE (SM-X510, Android 16), Wi-Fi 802.11ax.
- **Rede:** roteador da casa, com 2,4 GHz e 5 GHz.

## Como medir

1. Gerar um arquivo aleatório no Mac: `dd if=/dev/urandom of=teste.bin bs=1m count=1500`.
2. Enviar (arrastar até o ⇄ ou Finder → Enviar ao tablet) e ler a velocidade no log do tablet: `adb logcat -s FileShare`.
3. Conferir que chegou idêntico: `shasum -a 256` no Mac e `adb shell sha256sum /sdcard/Download/FileShare/teste.bin`.
4. Anotar a banda e o canal de cada lado:
   - **Mac:** `system_profiler SPAirPortDataType`, em Current Network;
   - **tablet:** `adb shell dumpsys wifi`, em Frequency e Link speed.

Para comparar: um pen drive USB 2.0 grava tipicamente entre 5 e 15 MB/s. Com os dois aparelhos em 5 GHz, a expectativa é ficar nessa faixa ou acima.

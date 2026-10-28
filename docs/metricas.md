# Métricas de transferência

Velocidades reais medidas com o FileShare, sempre com o ambiente junto: a velocidade depende mais do Wi-Fi que do app. Desde a 2.6, os dois apps registram no log o tamanho, o tempo e a velocidade de cada arquivo:
- **Mac:** linhas "enviado ao tablet" e "recebido do tablet";
- **tablet:** linhas "file sent to Mac" e "file from Mac saved".

## Recorde atual

| Sentido | Velocidade média | Arquivo | Ambiente |
|---|---|---|---|
| Mac → tablet | **10,8 MB/s** | 1 GB em 95 s, chegou idêntico (SHA-256) | Mac e tablet em 5 GHz, mesmo canal (153) |
| Tablet → Mac | **6,2 MB/s** | 1 GB em 164,5 s, chegou idêntico | Mac e tablet em 5 GHz, mesmo canal (153) |

O FileShare usa praticamente toda a rede, mesmo com a criptografia de ponta a ponta. Do tablet para o Mac, o teto medido na rede, sem o app, foi de 6,3 MB/s, e o app fez 6,2 MB/s.

## Teto da rede (sem o FileShare)

Bytes "crus" com `nc` por 10 segundos, sem criptografia, só para saber o limite da rede entre os dois aparelhos:

| Data | Sentido | Resultado | Ambiente |
|---|---|---|---|
| 27/10/2026 | Tablet → Mac | 6,3 MB/s (63 MB em 10 s) | Os dois em 5 GHz, canal 153; tablet com enlace de 573/310 Mb/s, Mac com 344 Mb/s |
| 27/10/2026 | Mac → tablet | 7,3 MB/s (73 MB em 10 s) | Igual |

Os 10 segundos pegam o começo mais lento de toda conexão, então o envio longo do FileShare (10,8 MB/s) passou do número cru. A rede fica bem abaixo dos números de enlace, porque tudo passa pelo roteador, que recebe de um aparelho e retransmite ao outro no mesmo canal.

## Medições

| Data | Versão | Sentido | Arquivo | Tempo | Média | Ambiente | Observação |
|---|---|---|---|---|---|---|---|
| 27/10/2026 | 2.6.0 (dev) | Mac → tablet | 1,5 GB (aleatório) | — | ~3 MB/s | Mac e tablet em 2,4 GHz (canal 11, 20 MHz), mesmo roteador | Interrompido pela troca de rede do Mac, recomeçou do zero |
| 27/10/2026 | 2.6.0 (dev) | Mac → tablet | 1,5 GB (aleatório) | 303 s | 5,2 MB/s | Mac em 5 GHz (canal 153, 40 MHz, 309 Mb/s); tablet em 2,4 GHz (2462 MHz, 98–138 Mb/s) | Picos de 7,5 MB/s; o gargalo é o tablet em 2,4 GHz |
| 27/10/2026 | 2.6.0 (dev) | Tablet → Mac | 1,5 GB (aleatório) | 532 s | 2,8 MB/s (com a queda) | Igual à anterior | Wi-Fi do tablet desligado por ~5 s no meio: continuou de 253 MB, sem recomeçar; ~3,6 MB/s enquanto enviava |
| 27/10/2026 | 2.6.0 (dev) | Mac → tablet | Pasta: 4 arquivos, 294 KB | 0,5 s | — | Igual à anterior | Subpastas e acentos preservados, .DS_Store fora |
| 27/10/2026 | 2.6.0 (dev) | Mac → tablet | 1 GB (aleatório) | 95,0 s | **10,8 MB/s** | Os dois em 5 GHz (canal 153, 5765 MHz); tablet 573/310 Mb/s, Mac 344 Mb/s | Hash idêntico |
| 27/10/2026 | 2.6.0 (dev) | Tablet → Mac | 1 GB (aleatório) | 164,5 s | **6,2 MB/s** | Igual | Hash idêntico; ~98% do teto da rede nesse sentido |

## Aparelhos

- **Mac:** MacBook Air (macOS 26), Wi-Fi 802.11ax.
- **Tablet:** Galaxy Tab S9 FE (SM-X510, Android 16), Wi-Fi 802.11ax.
- **Rede:** roteador da casa, com uma rede de 2,4 GHz e outra de 5 GHz ("turbo").

## Como medir

1. Conferir que os dois aparelhos estão na mesma rede de 5 GHz e que o FileShare está conectado.
2. Gerar um arquivo aleatório no Mac: `dd if=/dev/urandom of=teste.bin bs=1m count=1500`.
3. Enviar (arrastar até o ⇄ ou Finder → Enviar ao tablet) e ler a velocidade no log do tablet: `adb logcat -s FileShare`.
4. Conferir que chegou idêntico: `shasum -a 256` no Mac e `adb shell sha256sum /sdcard/Download/FileShare/teste.bin`.
5. Anotar a banda e o canal de cada lado:
   - **Mac:** `system_profiler SPAirPortDataType`, em Current Network;
   - **tablet:** `adb shell dumpsys wifi`, em Frequency e Link speed.

Para comparar: um pen drive USB 2.0 grava tipicamente entre 5 e 15 MB/s. Com os dois aparelhos em 5 GHz, o FileShare já está nessa faixa (10,8 MB/s do Mac para o tablet), sem cabo e criptografado.
6. Para saber o teto da rede sem o app:
   - **tablet → Mac:** no Mac, `nc -l 5201 | wc -c`; no tablet, `adb shell "timeout 10 nc <ip-do-Mac> 5201 < /dev/zero"`;
   - **Mac → tablet:** no tablet, `adb shell "nc -l -p 5202 | wc -c"`; no Mac, `nc <ip-do-tablet> 5202 < /dev/zero`, por 10 s.
   - O `nc` do Android para cedo se lê de um pipe; use `< /dev/zero`.

#!/usr/bin/env python3
"""Receptor provisório no Mac: grava na área de transferência o que o tablet envia.

Configura o túnel `adb reverse` (cabo USB) e escuta em 127.0.0.1:47801.
Protocolo: "mime\\ntamanho\\n<bytes>"; responde "k" depois de gravar.
Será substituído pelo app da barra de menu (Wi-Fi, pareamento por QR).

Uso: mac/receiver.py
"""
import os
import socket
import subprocess
import tempfile
import time

PORT = 47801
MAX_PAYLOAD = 25 * 1024 * 1024


def read_line(f) -> str:
    line = f.readline(256)
    if not line.endswith(b"\n"):
        raise ValueError("cabeçalho inválido")
    return line.decode().strip()


def set_clipboard(mime: str, body: bytes) -> None:
    if mime.startswith("text/"):
        subprocess.run(["pbcopy"], input=body, env={**os.environ, "LANG": "en_US.UTF-8"}, check=True)
        return
    with tempfile.TemporaryDirectory() as d:
        src, png = os.path.join(d, "in"), os.path.join(d, "clip.png")
        with open(src, "wb") as f:
            f.write(body)
        subprocess.run(["sips", "-s", "format", "png", src, "--out", png], capture_output=True, check=True)
        subprocess.run(["osascript", "-e", f'set the clipboard to (read (POSIX file "{png}") as «class PNGf»)'],
                       capture_output=True, check=True)


def handle(conn: socket.socket) -> None:
    conn.settimeout(10)
    f = conn.makefile("rb")
    mime = read_line(f)
    size = int(read_line(f))
    if not 0 < size <= MAX_PAYLOAD:
        raise ValueError(f"tamanho inválido: {size}")
    body = f.read(size)
    if len(body) != size:
        raise ValueError(f"recebidos {len(body)} de {size} bytes")
    set_clipboard(mime, body)
    conn.sendall(b"k")
    print(time.strftime("%H:%M:%S"), "colado no Mac:", mime, len(body), "bytes", flush=True)


def main() -> None:
    subprocess.run(["adb", "reverse", f"tcp:{PORT}", f"tcp:{PORT}"], check=True, capture_output=True)
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", PORT))
    srv.listen(1)
    print(f"aguardando o tablet em 127.0.0.1:{PORT} (Ctrl+C para sair)", flush=True)
    while True:
        conn, _ = srv.accept()
        with conn:
            try:
                handle(conn)
            except Exception as e:
                print(time.strftime("%H:%M:%S"), "erro:", e, flush=True)


if __name__ == "__main__":
    main()

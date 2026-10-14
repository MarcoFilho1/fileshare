#!/usr/bin/env python3
"""Envia texto ou imagem para a área de transferência do tablet (via USB/adb).

Uso:
  tools/send_to_tablet.py text "olá"
  tools/send_to_tablet.py image caminho/para/imagem.png
"""
import socket
import subprocess
import sys

PORT = 47800


def main() -> None:
    if len(sys.argv) != 3 or sys.argv[1] not in ("text", "image"):
        sys.exit(__doc__)
    kind, arg = sys.argv[1], sys.argv[2]
    if kind == "text":
        mime, data = "text/plain", arg.encode()
    else:
        mime, data = "image/png", open(arg, "rb").read()

    subprocess.run(["adb", "forward", f"tcp:{PORT}", f"tcp:{PORT}"], check=True, capture_output=True)
    with socket.create_connection(("127.0.0.1", PORT), timeout=5) as s:
        s.sendall(f"{mime}\n{len(data)}\n".encode() + data)
        ok = s.recv(1) == b"k"
    print(f"{'enviado' if ok else 'sem confirmação do tablet'}: {mime}, {len(data)} bytes")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

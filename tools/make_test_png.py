#!/usr/bin/env python3
"""Gera uma imagem PNG de teste (xadrez colorido 1200x700) sem dependências.

Uso: tools/make_test_png.py saida.png
"""
import struct
import sys
import zlib

W, H = 1200, 700


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    rows = []
    for y in range(H):
        row = bytearray([0])
        for x in range(W):
            band = (x // 150) % 2 ^ (y // 140) % 2
            row += bytes([30 + 200 * x // W, 120 if band else 60, 230 - 200 * y // H])
        rows.append(bytes(row))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
           + chunk(b"IEND", b""))
    with open(sys.argv[1], "wb") as f:
        f.write(png)


if __name__ == "__main__":
    main()
